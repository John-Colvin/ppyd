import pyd.pyd;

import std.meta : AliasSeq, staticMap, Filter, Alias;
import std.typecons : tuple, Tuple;
import std.traits;

private struct Pdef(Args ...){}

@property auto pdef(Args ...)()
{
    return Pdef!Args();
}

template TryTypeof(TL ...)
if(TL.length == 1)
{
    static if(is(TL[0]))
        alias TryTypeof = TL[0];
    else static if(is(typeof(TL[0])))
        alias TryTypeof = typeof(TL[0]);
    else static assert("Can't get a type out of this");
}

bool containsPdef(attrs...)()
{
    static foreach(attr; attrs)
        static if(!is(done) && is(TryTypeof!attr == Pdef!Args, Args...))
        {
            enum done;
            return true;
        }
    static if (!is(done))
        return false;
}

private auto registerFunctionImpl(alias define, alias parent, string mem)()
{
    //pragma(msg, "callable");
    alias ols = AliasSeq!(__traits(getOverloads, parent, mem));
    foreach(i, ol; ols)
    {
        alias attrs = AliasSeq!(__traits(getAttributes, ol));
        static if(containsPdef!attrs)
            foreach(attr; attrs)
            {
                static if(is(TryTypeof!attr == Pdef!Args, Args...))
                {
                    return define!(ol, Args)();
                }
            }
        // issue 14747
        else static if(i == ols.length - 1)
        {
            return;
        }
    }
    // issue 14747
    assert(0);
}

alias registerFunction(alias parent, string mem) = registerFunctionImpl!(def, parent, mem);

alias MemberFunction(alias parent, string mem) = ReturnType!(registerFunctionImpl!(Def, parent, mem));
alias StaticMemberFunction(alias parent, string mem) = ReturnType!(registerFunctionImpl!(StaticDef, parent, mem));
alias PropertyMember(alias parent, string mem) = ReturnType!(registerFunctionImpl!(Property, parent, mem));

private auto MemberHelper(alias parent, string mem)()
{
    alias agg = Alias!(mixin(`parent.`~mem));

    alias attrs = AliasSeq!(__traits(getAttributes, agg));
    foreach(i, attr; attrs)
    {
        static if(is(TryTypeof!attr == Pdef!Args, Args...))
        {
            return Member!(mem, Args)();
        }
        // issue 14747
        else static if(i == attrs.length - 1)
            return;
    }
    // issue 14747
    assert(0);
}

alias _Member(alias parent, string mem) = ReturnType!(MemberHelper!(parent, mem));

auto registerAggregateType(string aggStr, alias parent)()
{
    alias agg = Alias!(mixin(`parent.`~aggStr));

    alias attrs = AliasSeq!(__traits(getAttributes, agg));
    foreach(attr; attrs)
    {
        static if(is(TryTypeof!attr == Pdef!Args, Args...))
        {
            enum NotVoid(T) = !is(T == void);
            return wrap_class!(agg, Args,
                    Filter!(NotVoid,
                        staticMap!(Symbol!agg, __traits(allMembers, agg))))();
            /+
            import std.algorithm, std.string;
            /*pragma(msg, `return wrap_class!(agg, Args, ` ~
                        [__traits(allMembers, agg)]
                            .map!(a => `registerSymbol!("` ~ a ~ `", agg)()`).join(", ") ~ `);`);*/
            mixin(`return wrap_class!(agg, Args, ` ~
                        [__traits(allMembers, agg)]
                            .map!(a => `registerSymbol!("` ~ a ~ `", agg)`).join(", ") ~ `);`);+/
        }
    }
}

template Symbol(alias parent)
{
    alias Symbol(string mem) = .Symbol!(mem, parent);
}

template Symbol(string mem, alias parent)
{
    pragma(msg, "registering " ~ parent.stringof ~ '.' ~ mem);
    static if(is(parent == struct) || is(parent == class))
    {
        pragma(msg, "with class/struct parent");
        static if(!(__traits(compiles, mixin(`isAggregateType!(parent.`~mem~')'))
                    && mixin(`isAggregateType!(parent.`~mem~')')
                   )
                    && mixin(`isCallable!(parent.`~mem~')'))
        {
            static if(__traits(isStaticFunction, mixin(`parent.`~mem)))
            {
                pragma(msg, "as static member function");
                alias Symbol =  StaticMemberFunction!(parent, mem);
            }
            static if(functionAttributes!(mixin(`parent.`~mem)) & FunctionAttribute.property)
            {
                pragma(msg, "as property member");
                alias Symbol = PropertyMember!(parent, mem);
            }
            else
            {
                pragma(msg, "as member function");
                alias Symbol =  MemberFunction!(parent, mem);
            }
        }
        else
        {
            pragma(msg, "as member");
            alias Symbol = _Member!(parent, mem);
        }
    }
    else static assert(false);
}

void registerModuleScopeSymbol(string mem, alias parent)()
{
    pragma(msg, "registering " ~ parent.stringof ~ '.' ~ mem);
    static if(mixin(`isCallable!(parent.`~mem~')'))
    {
        pragma(msg, "as free function");
        registerFunction!(parent, mem);
    }
    else static if(__traits(compiles, mixin(`isAggregateType!(parent.`~mem~')'))
            && mixin(`isAggregateType!(parent.`~mem~')'))
    {
        pragma(msg, "as aggregate type");
        registerAggregateType!(mem, parent);
    }
    else pragma(msg, "not registered");
}

void registerAll(alias extModule)()
{
    //Horrible hacks because typeinfo init seems be both there and not there,
    //depending on when you look
    import std.algorithm : startsWith, canFind, endsWith;
    alias membersAll = __traits(allMembers, extModule);
    enum isNotTypeInfoInit(string a) = !(a.startsWith("_")
        && a.canFind("TypeInfo") && a.endsWith("__initZ"));
    alias members = Filter!(isNotTypeInfoInit, membersAll);
    foreach(mem; members)
    {
        static if (__traits(compiles, __traits(getMember, extModule, mem))
            && isCallable!(__traits(getMember, extModule, mem)))
                registerFunction!(extModule, mem)();
    }
    static if(__traits(hasMember, extModule, "preInit"))
        extModule.preInit();

    module_init();

    foreach(mem; members)
    {
        static if (__traits(compiles, __traits(getMember, extModule, mem))
            && isCallable!(__traits(getMember, extModule, mem)))
                registerModuleScopeSymbol!(mem, extModule)();
    }

    static if(__traits(hasMember, extModule, "postInit"))
        extModule.postInit();
}

