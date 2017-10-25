#!/usr/bin/env dub --build=release-nobounds --compiler=ldmd2 -v --single
/+ dub.json: {
    "name":"randindex_bench",
    "dependencies": {
        "mir-random":{"path": "../"}
    }
} +/
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
randIndexV1: 2.32964 * 10 ^^ 8 calls/s
randIndexV2: 2.48911 * 10 ^^ 8 calls/s

Benchmarks for XorshiftStarEngine!(ulong, 1024u, 31u, 11u, 30u, 11400714819323198483LU, ulong):
randIndexV1: 3.73308 * 10 ^^ 8 calls/s
randIndexV2: 3.78072 * 10 ^^ 8 calls/s

Benchmarks for Xoroshiro128Plus:
randIndexV1: 6.09292 * 10 ^^ 8 calls/s
randIndexV2: 7.22022 * 10 ^^ 8 calls/s

Benchmarks for PermutedCongruentialEngine!(rxs_m_xs_forward, cast(stream_t)2, true):
randIndexV1: 4.40771 * 10 ^^ 8 calls/s
randIndexV2: 3.87409 * 10 ^^ 8 calls/s <-- check this out

--------
The performance appeared to be worse for the PCG for some reason.
I tried special-casing the algorithm for PCGs but that didn't help,
leading me to suspect that something else was going on.

To investigate I ran another test with randIndexV2 being run again
with the label "randIndexV3".
--------

Benchmarks for MersenneTwisterEngine!(ulong, 64LU, 312LU, 156LU, 31LU, 13043109905998158313LU, 29LU, 6148914691236517205LU, 17LU, 8202884508482404352LU, 37LU, 18444473444759240704LU, 43LU, 6364136223846793005LU):
randIndexV1: 2.28115 * 10 ^^ 8 calls/s
randIndexV2: 2.41036 * 10 ^^ 8 calls/s
randIndexV3: 2.41619 * 10 ^^ 8 calls/s

Benchmarks for XorshiftStarEngine!(ulong, 1024u, 31u, 11u, 30u, 11400714819323198483LU, ulong):
randIndexV1: 3.64133 * 10 ^^ 8 calls/s
randIndexV2: 3.76471 * 10 ^^ 8 calls/s
randIndexV3: 3.75059 * 10 ^^ 8 calls/s

Benchmarks for Xoroshiro128Plus:
randIndexV1: 6.03774 * 10 ^^ 8 calls/s
randIndexV2: 7.08592 * 10 ^^ 8 calls/s
randIndexV3: 7.02371 * 10 ^^ 8 calls/s

Benchmarks for PermutedCongruentialEngine!(rxs_m_xs_forward, cast(stream_t)2, true):
randIndexV1: 4.28266 * 10 ^^ 8 calls/s
randIndexV2: 3.75587 * 10 ^^ 8 calls/s
randIndexV3: 4.25532 * 10 ^^ 8 calls/s <--- check this out


We can see that for PCG, it isn't that one method is faster than the
other, but something else is going on.
*/

T randIndexV1(T, G)(ref G gen, T m)
    if(isSaturatedRandomEngine!G && isUnsigned!T)
{
    assert(m, "m must be positive");
    T ret = void;
    T val = void;
    do
    {
        //val = gen.rand!T;
        val = cast(T) gen();
        ret = val % m;
    }
    while (val - ret > -m);
    return ret;
}

T randIndexV2(T, G)(ref G gen, T m)
    if (isSaturatedRandomEngine!G && isUnsigned!T
        && (T.sizeof * 2) <= (EngineReturnType!G).sizeof)
{
    //https://lemire.me/blog/2016/06/30/fast-random-shuffling/
    alias R = Unqual!(EngineReturnType!G);
    enum rshift = (R.sizeof - T.sizeof) * 8;
    auto randombits = gen() >>> rshift;
    auto multiresult = randombits * m;
    auto leftover = cast(T) multiresult;
    if (leftover < m)
    {
        immutable threshold = -m % m ;
        while (leftover < threshold)
        {
            randombits =  gen() >>> rshift;
            multiresult = randombits * m;
            leftover = cast(T) multiresult;
        }
    }
    return cast(T) (multiresult >>> rshift);
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
        StopWatch sw;
        sw.start;
        foreach(_; 0 .. min(count / 2, 200_000_000u)) //boost CPU
        {
            s += gen.randIndexV1(cast(uint)100);
            s += gen.randIndexV2(cast(uint)100);
        }
        sw.stop;
        sw.reset;
        gen.__ctor(seed);
        sw.start;
        foreach(_; 0..count)
            s += gen.randIndexV1(cast(uint)100);
        sw.stop;
        writefln("randIndexV1: %s * 10 ^^ 8 calls/s", double(count) / sw.peek.msecs / 100_000);
        sw.reset;
        gen.__ctor(seed);
        sw.start;
        foreach(_; 0..count)
            s += gen.randIndexV2(cast(uint)100);
        sw.stop;
        writefln("randIndexV2: %s * 10 ^^ 8 calls/s", double(count) / sw.peek.msecs / 100_000);
        //sw.reset;
        //gen.__ctor(seed);
        //sw.start;
        //foreach(_; 0..count)
        //    s += gen.randIndexV2(cast(uint)100);
        //sw.stop;
        //writefln("randIndexV3: %s * 10 ^^ 8 calls/s", double(count) / sw.peek.msecs / 100_000);
    }
    writeln("Meaningless sum: ", s);
}
