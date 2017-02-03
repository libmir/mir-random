#!/usr/bin/env dub
/+ dub.json:
{
    "name": "flex_plot_test_different_c_values",
    "dependencies": {"flex_common_pack": {"path": "./flex_common_pack"}},
    "versions": ["Flex_logging", "Flex_single"]
}
+/
/**
Test different values for c.
*/
void test(S, F)(in ref F test)
{
    import std.math : pow;
    auto f0 = (S x) => -2 * pow(x, 4)  + 4 * x * x;
    auto f1 = (S x) => -8 * pow(x, 3) + 8 * x;
    auto f2 = (S x) => -24 * x * x + 8;

    enum name = "diff_c_values";

    test.plot(name ~ "_a", f0, f1, f2, [-0.5, 2, -2, 0.5, -1, 0],
        [-S.infinity, -2, -1, 0, 1, 2, S.infinity]);

    test.plot(name ~ "_b", f0, f1, f2, [-0.5, 2, -2, 0.5, -1, 0], [-3, -2, -1, 0, 1, 2, 3]);
}

version(Flex_single) void main()
{
    import flex_common;
    alias T = double;
    auto cf = CFlex!T(5_000, "plots", 1.1);
    test!T(cf);
}
