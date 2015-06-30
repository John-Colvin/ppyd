# ppyd
Pretty pyd

Use ```@pdef!()``` to annotate function, types, members etc. that you want to expose to python via pyd.

Add template arguments to ```@pdef!()``` just like you would add to ```def```, ```Def``` and similar in pyd.
E.g. ```@pdef!(PyName!"pyFoo") int foo();```
