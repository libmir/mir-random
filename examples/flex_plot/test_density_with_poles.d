#!/usr/bin/env dub
/+ dub.json:
{
    "name": "flex_plot_test_density_with_poles",
    "dependencies": {"flex_common_pack": {"path": "./flex_common_pack"}},
    "versions": ["Flex_logging", "Flex_single"]
}
+/
/**
Test density with pole.
*/
void test(S, F)(in ref F test)
{
    import std.math : abs, log;
    auto f0 = (S x) => - cast(S) log(abs(x)) * S(0.5);
    auto f1 = (S x) => -1 / (2 * x);
    auto f2 = (S x) => S(0.5) / (x * x);

    test.plot("dist_with_poles", f0, f1, f2, -1.5, [-1.0, 0, 1]);
}

version(Flex_single) void main()
{
    import flex_common;
    alias T = double;
    auto cf = CFlex!T(5_000, "plots", 1.1);
    test!T(cf);
}
