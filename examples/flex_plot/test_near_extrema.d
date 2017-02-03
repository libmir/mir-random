#!/usr/bin/env dub
/+ dub.json:
{
    "name": "flex_plot_test_near_extrema",
    "dependencies": {"flex_common_pack": {"path": "./flex_common_pack"}},
    "versions": ["Flex_logging", "Flex_single"]
}
+/
/**
Test at and near extrema.
*/
void test(S, F)(in ref F test)
{
    import std.math : pow;
    import std.conv : to;
    auto f0 = (S x) => -2 * pow(x, 4) + 4 * x * x;
    auto f1 = (S x) => -8 * pow(x, 3) + 8 * x;
    auto f2 = (S x) => -24 * x * x + 8;

    enum name = "dist_near_extrema";

    foreach (c; [-2, -1.1, -1, 0.5, 1, 1.5, 2])
    {
        test.plot(name ~ "_c_" ~ c.to!string, f0, f1, f2, c, [-3, -1, 0, 1, 3]);
        test.plot(name ~ "_d_" ~ c.to!string, f0, f1, f2, c,
            [-3, -1 + (cast(S) 2) ^^-52, 1e-20, 1 - (cast(S) 2)^^(-53), 3]);
    }

    foreach (c; [-0.9, -0.5, -0.2, 0])
    {
        test.plot(name ~ "_a_" ~ c.to!string, f0, f1, f2, c,
            [-S.infinity, -2, -1, 0, 1, 2, S.infinity]);
        test.plot(name ~ "_b_" ~ c.to!string, f0, f1, f2, c,
            [-S.infinity, -2, -1 + (cast(S)2)^^-52, 1e-20, 1-(cast(S)2)^^(-53), 2, S.infinity]);
    }
}

version(Flex_single) void main()
{
    import flex_common;
    alias T = double;
    auto cf = CFlex!T(5_000, "plots", 1.1);
    test!T(cf);
}
