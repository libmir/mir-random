#!/usr/bin/env dub --build=release-nobounds --compiler=ldmd2 -v --single
/+ dub.json: {
    "name":"randindex_bench",
    "dependencies": {
        "mir-random":{"path": "../"}
    }
} +/
import mir.random : rand, randIndex;
import mir.random.engine : isSaturatedRandomEngine, EngineReturnType;
import mir.random.engine.mersenne_twister : Mt19937, Mt19937_64;
import mir.random.engine.pcg : pcg32_oneseq, pcg64_oneseq_once_insecure;
import mir.random.engine.xorshift : Xoroshiro128Plus, Xorshift1024StarPhi;
import mir.utility : min, max;

import std.traits: isUnsigned, Unqual;

import std.stdio, std.datetime, std.conv;

/*
Sample results on Intel(R) Core(TM) i7-7920HQ CPU @ 3.10GHz

Benchmarks for MersenneTwisterEngine!(ulong, 64LU, 312LU, 156LU, 31LU, 13043109905998158313LU, 29LU, 6148914691236517205LU, 17LU, 8202884508482404352LU, 37LU, 18444473444759240704LU, 43LU, 6364136223846793005LU):
randIndexV1: 1.34454 * 10 ^^ 8 calls/s
randIndexV2: 1.82066 * 10 ^^ 8 calls/s
new mir.random.randIndex (potential inlining shenanigans): 2.34949 * 10 ^^ 8 calls/s

Benchmarks for XorshiftStarEngine!(ulong, 1024u, 31u, 11u, 30u, 11400714819323198483LU, ulong):
randIndexV1: 2.26436 * 10 ^^ 8 calls/s
randIndexV2: 3.0349 * 10 ^^ 8 calls/s
new mir.random.randIndex (potential inlining shenanigans): 3.83693 * 10 ^^ 8 calls/s

Benchmarks for Xoroshiro128Plus:
randIndexV1: 2.60671 * 10 ^^ 8 calls/s
randIndexV2: 3.848 * 10 ^^ 8 calls/s
new mir.random.randIndex (potential inlining shenanigans): 7.06714 * 10 ^^ 8 calls/s

Benchmarks for PermutedCongruentialEngine!(rxs_m_xs_forward, cast(stream_t)2, true):
randIndexV1: 1.45243 * 10 ^^ 8 calls/s
randIndexV2: 2.47755 * 10 ^^ 8 calls/s
new mir.random.randIndex (potential inlining shenanigans): 4.18848 * 10 ^^ 8 calls/s
*/

T randIndexV1(T, G)(ref G gen, T m)
    if(isSaturatedRandomEngine!G && isUnsigned!T)
{
    pragma(inline, false);//Try to prevent LDC from doing anything clever with the modulus.
    static assert(is(T == uint), "During this test, if !is(T == uint) there is a mistake!");

    assert(m, "m must be positive");
    T ret = void;
    T val = void;
    do
    {
        val = gen.rand!T;
        ret = val % m;
    }
    while (val - ret > -m);
    return ret;
}

T randIndexV2(T, G)(ref G gen, T m)
    if (isSaturatedRandomEngine!G && isUnsigned!T
        && (T.sizeof * 2) <= (EngineReturnType!G).sizeof)
{
    pragma(inline, false);//Try to prevent LDC from doing anything clever with the modulus.
    static assert(is(T == uint), "During this test, if !is(T == uint) there is a mistake!");

    //https://lemire.me/blog/2016/06/30/fast-random-shuffling/
    import mir.ndslice.internal: _expect;
    alias R = Unqual!(EngineReturnType!G);
    R randombits = cast(R) gen.rand!T;
    R multiresult = randombits * m;
    T leftover = cast(T) multiresult;
    if (_expect(leftover < m, false))
    {
        immutable threshold = -m % m ;
        while (leftover < threshold)
        {
            randombits =  cast(R) gen.rand!T;
            multiresult = randombits * m;
            leftover = cast(T) multiresult;
        }
    }
    enum finalshift = T.sizeof * 8;
    return cast(T) (multiresult >>> finalshift);
}

void main(string[] args)
{
    import std.meta : AliasSeq;
    uint s = 0;
    foreach (PrngType; AliasSeq!(Mt19937_64, Xorshift1024StarPhi, Xoroshiro128Plus, pcg64_oneseq_once_insecure))
    {
        writeln("\nBenchmarks for ", PrngType.stringof, ":");
        enum seed = PrngType.max / 2;
        auto gen = PrngType(seed);
        enum ulong count = 800_000_000;
        enum uint modulus_min = 6;
        enum uint modulus_max = 6 + 100;
        static assert(count % (modulus_max - modulus_min) == 0);
        enum outer_loop_iterations = count / (modulus_max - modulus_min);
        enum warmup_outer_loop_iterations = min(outer_loop_iterations / 2, 2_000_000u);

        StopWatch sw;
        sw.start;
        foreach(_; 0 .. warmup_outer_loop_iterations) //boost CPU
        {
            foreach (m; modulus_min .. modulus_max)
            {
                s += gen.randIndexV1(m);
                s += gen.randIndexV2(m);
            }
        }
        sw.stop;
        sw.reset;
        gen.__ctor(seed);
        sw.start;
        foreach(_; 0..outer_loop_iterations)
        {
            foreach (m; modulus_min .. modulus_max)
                s += gen.randIndexV1(m);
        }
        sw.stop;
        writefln("randIndexV1: %s * 10 ^^ 8 calls/s", double(count) / sw.peek.msecs / 100_000);
        sw.start;
        foreach(_; 0 .. warmup_outer_loop_iterations) //boost CPU
        {
            foreach (m; modulus_min ..modulus_max)
            {
                s += gen.randIndexV1(m);
                s += gen.randIndexV2(m);
            }
        }
        sw.stop;
        sw.reset;
        gen.__ctor(seed);
        sw.start;
        foreach(_; 0..outer_loop_iterations)
        {
            foreach (m; modulus_min .. modulus_max)
                s += gen.randIndexV2(m);
        }
        sw.stop;
        writefln("randIndexV2: %s * 10 ^^ 8 calls/s", double(count) / sw.peek.msecs / 100_000);
        sw.start;
        foreach(_; 0 .. warmup_outer_loop_iterations) //boost CPU
        {
            foreach (m; modulus_min ..modulus_max)
            {
                s += gen.randIndexV1(m);
                s += gen.randIndex(m);
            }
        }
        sw.stop;
        sw.reset;
        gen.__ctor(seed);
        sw.start;
        foreach(_; 0..outer_loop_iterations)
        {
            foreach (m; modulus_min .. modulus_max)
                s += gen.randIndex(m);
        }
        sw.stop;
        writefln("new mir.random.randIndex (potential inlining shenanigans): %s * 10 ^^ 8 calls/s", double(count) / sw.peek.msecs / 100_000);
    }
    writeln("Meaningless sum: ", s);
}
