/++
$(SCRIPT inhibitQuickIndex = 1;)

Basic API to construct non-uniform random number generators and stochastic algorithms.
Non-unoform and uniform random variable can be found at `mir.random.variable`.

$(TABLE $(H2 Generation functions),
$(TR $(TH Function Name) $(TH Description))
$(T2 rand, Generates real, integral, boolean, and enumerated uniformly distributed values.)
$(T2 randIndex, Generates uniformly distributed index.)
$(T2 randGeometric, Generates geometric distribution with `p = 1/2`.)
$(T2 randExponential2, Generates scaled Exponential distribution.)
)

Publicly includes  `mir.random.engine`.

Authors: Ilya Yaroshenko
Copyright: Copyright, Ilya Yaroshenko 2016-.
License:    $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
Macros:
SUBREF = $(REF_ALTTEXT $(TT $2), $2, mir, ndslice, $1)$(NBSP)
T2=$(TR $(TDNW $(LREF $1)) $(TD $+))

+/
module mir.random;

import std.traits;

public import mir.random.engine;

static import core.simd;

version (LDC)
{
    import ldc.intrinsics: log2 = llvm_log2;

    private
    pragma(inline, true)
    T bsf(T)(T v) pure @safe nothrow @nogc
    {
        import ldc.intrinsics;
        return llvm_cttz(v, true);
    }
}
else
{
    import std.math: log2;
    import core.bitop: bsf;
}

/++
Params:
    gen = saturated random number generator
Returns:
    Uniformly distributed integer for interval `[0 .. T.max]`.
+/
T rand(T, G)(ref G gen)
    if (isSaturatedRandomEngine!G && isIntegral!T && !is(T == enum))
{
    alias R = EngineReturnType!G;
    enum P = T.sizeof / R.sizeof;
    static if (P > 1)
    {
        static if (is(typeof((ref G g) @safe => g())))
        {
            return () @trusted {
            T ret = void;
            foreach(p; 0..P)
                (cast(R*)(&ret))[p] = gen();
            return ret;
                }();
        }
        else
        {
            T ret = void;
            foreach(p; 0..P)
                (cast(R*)(&ret))[p] = gen();
            return ret;
        }
    }
    else static if (preferHighBits!G && P == 0)
    {
        version(LDC) pragma(inline, true);
        return cast(T) (gen() >>> ((R.sizeof - T.sizeof) * 8));
    }
    else
    {
        version(LDC) pragma(inline, true);
        return cast(T) gen();
    }
}

///
version(mir_random_test) unittest
{
    import mir.random.engine.xorshift;
    auto gen = Xorshift(1);
    auto s = gen.rand!short;
    auto n = gen.rand!ulong;
}

/++
Params:
    gen = saturated random number generator
Returns:
    Uniformly distributed boolean.
+/
bool rand(T : bool, G)(ref G gen)
    if (isSaturatedRandomEngine!G)
{
    import std.traits : Signed;
    return 0 > cast(Signed!(EngineReturnType!G)) gen();
}

///
version(mir_random_test) unittest
{
    import mir.random.engine.xorshift;
    auto gen = Xorshift(1);
    auto s = gen.rand!bool;
}

private alias Iota(size_t j) = Iota!(0, j);

private template Iota(size_t i, size_t j)
{
    import std.meta;
    static assert(i <= j, "Iota: i should be less than or equal to j");
    static if (i == j)
        alias Iota = AliasSeq!();
    else
        alias Iota = AliasSeq!(i, Iota!(i + 1, j));
}

/++
Params:
    gen = saturated random number generator
Returns:
    Uniformly distributed enumeration.
+/
T rand(T, G)(ref G gen)
    if (isSaturatedRandomEngine!G && is(T == enum))
{
    static if (is(T : long))
        enum tiny = [EnumMembers!T] == [Iota!(EnumMembers!T.length)];
    else
        enum tiny = false;
    static if (tiny)
    {
        return cast(T) gen.randIndex(EnumMembers!T.length);
    }
    else
    {
        static immutable T[EnumMembers!T.length] members = [EnumMembers!T];
        return members[gen.randIndex($)];
    }
}

///
version(mir_random_test) unittest
{
    import mir.random.engine.xorshift;
    auto gen = Xorshift(1);
    enum A { a, b, c }
    auto e = gen.rand!A;
}

///
version(mir_random_test) unittest
{
    import mir.random.engine.xorshift;
    auto gen = Xorshift(1);
    enum A : dchar { a, b, c }
    auto e = gen.rand!A;
}

///
version(mir_random_test) unittest
{
    import mir.random.engine.xorshift;
    auto gen = Xorshift(1);
    enum A : string { a = "a", b = "b", c = "c" }
    auto e = gen.rand!A;
}

private static union _U
{
    real r;
    struct
    {
        version(LittleEndian)
        {
            ulong m;
            ushort e;
        }
        else
        {
            ushort e;
            align(2)
            ulong m;
        }
    }
}

/++
Params:
    gen = saturated random number generator
    boundExp = bound exponent (optional). `boundExp` must be less or equal to `T.max_exp`.
Returns:
    Uniformly distributed real for interval `(-2^^boundExp , 2^^boundExp)`.
Note: `fabs` can be used to get a value from positive interval `[0, 2^^boundExp$(RPAREN)`.
+/
T rand(T, G)(ref G gen, sizediff_t boundExp = 0)
    if (isSaturatedRandomEngine!G && isFloatingPoint!T)
{
    assert(boundExp <= T.max_exp);
    enum W = T.sizeof * 8 - T.mant_dig - 1 - bool(T.mant_dig == 64);
    static if (T.mant_dig == float.mant_dig)
    {
        auto d = gen.rand!int;
        enum uint EXPMASK = 0x7F80_0000;
        boundExp -= T.min_exp - 1;
        size_t exp = EXPMASK & d;
        exp = boundExp - (exp ? bsf(exp) - (T.mant_dig - 1) : gen.randGeometric + W);
        d &= ~EXPMASK;
        if(cast(sizediff_t)exp < 0)
        {
            exp = -cast(sizediff_t)exp;
            uint m = d & int.max;
            if(exp >= T.mant_dig)
                m = 0;
            else
                m >>= cast(uint)exp;
            d = (d & ~int.max) ^ m;
            exp = 0;
        }
        d = cast(uint)(exp << (T.mant_dig - 1)) ^ d;
        return *cast(T*)&d;
    }
    else
    static if (T.mant_dig == double.mant_dig)
    {
        auto d = gen.rand!long;
        enum ulong EXPMASK = 0x7FF0_0000_0000_0000;
        boundExp -= T.min_exp - 1;
        ulong exp = EXPMASK & d;
        exp = boundExp - (exp ? bsf(exp) - (T.mant_dig - 1) : gen.randGeometric + W);
        d &= ~EXPMASK;
        if(cast(long)exp < 0)
        {
            exp = -cast(sizediff_t)exp;
            ulong m = d & long.max;
            if(exp >= T.mant_dig)
                m = 0;
            else
                m >>= cast(uint)exp;
            d = (d & ~long.max) ^ m;
            exp = 0;
        }
        d = (exp << (T.mant_dig - 1)) ^ d;
        return *cast(T*)&d;
    }
    else
    static if (T.mant_dig == 64)
    {
        auto d = gen.rand!int;
        auto m = gen.rand!ulong;
        enum uint EXPMASK = 0x7FFF;
        boundExp -= T.min_exp - 1;
        size_t exp = EXPMASK & d;
        exp = boundExp - (exp ? bsf(exp) : gen.randGeometric + W);
        if (cast(sizediff_t)exp > 0)
            m |= ~long.max;
        else
        {
            m &= long.max;
            exp = -cast(sizediff_t)exp;
            if(exp >= T.mant_dig)
                m = 0;
            else
                m >>= cast(uint)exp;
            exp = 0;
        }
        d = cast(uint) exp ^ (d & ~EXPMASK);
        _U ret = void;
        ret.e = cast(ushort)d;
        ret.m = m;
        return ret.r;
    }
    /// TODO: quadruple
    else static assert(0);
}

///
version(mir_random_test) unittest
{
    import mir.math.common: fabs;
    import mir.random.engine.xorshift;
    auto gen = Xorshift(1);
    
    auto a = gen.rand!float;
    assert(-1 < a && a < +1);

    auto b = gen.rand!double(4);
    assert(-16 < b && b < +16);
    
    auto c = gen.rand!double(-2);
    assert(-0.25 < c && c < +0.25);
    
    auto d = gen.rand!real.fabs;
    assert(0.0L <= d && d < 1.0L);
}


/// Subnormal numbers
version(mir_random_test) unittest
{
    import mir.random.engine.xorshift;
    auto gen = Xorshift(1);
    auto x = gen.rand!double(double.min_exp-1);
    assert(-double.min_normal < x && x < double.min_normal);
}

version (LDC)
{
    //TODO: figure out specific feature flag or CPU versions where 128 bit multiplication works!
    version (X86_64)
        private enum bool probablyCanMultiply128 = true;
    else
        private enum bool probablyCanMultiply128 = size_t.sizeof >= ulong.sizeof;

    static if (probablyCanMultiply128 && is(core.simd.Vector!(ulong[2])) && !is(ucent))
    {
        private @nogc nothrow pure @safe
        {
            pragma(LDC_inline_ir) R inlineIR(string s, R, P...)(P);

            pragma(inline, true)
            core.simd.ulong2 mul_128(ulong a, ulong b)
            {
                return inlineIR!(`
                    %a = zext i64 %0 to i128
                    %b = zext i64 %1 to i128
                    %ra = mul i128 %a, %b
                    %rb = bitcast i128 %ra to <2 x i64>
                    ret <2 x i64> %rb`, core.simd.ulong2)(a, b);
            }

            static union mul_128_u
            {
                core.simd.ulong2 v;

                version (LittleEndian)
                    struct { ulong leftover, highbits; }
                else version (BigEndian)
                    struct { ulong highbits, leftover; }
                else
                    static assert(0, "Neither LittleEndian nor BigEndian!");
            }
        }
    }
}

/++
Params:
    gen = uniform random number generator
    m = positive module
Returns:
    Uniformly distributed integer for interval `[0 .. m$(RPAREN)`.
+/
T randIndex(T, G)(ref G gen, T m)
    if(isSaturatedRandomEngine!G && isUnsigned!T)
{
    static if (EngineReturnType!G.sizeof >= T.sizeof * 2)
        alias MaybeR = EngineReturnType!G;
    else static if (uint.sizeof >= T.sizeof * 2)
        alias MaybeR = uint;
    else static if (ulong.sizeof >= T.sizeof * 2)
        alias MaybeR = ulong;
    else static if (is(ucent) && __traits(compiles, {static assert(ucent.sizeof >= T.sizeof * 2);}))
        mixin ("alias MaybeR = ucent;");
    else
        alias MaybeR = void;

    static if (!is(MaybeR == void))
    {
        if (!__ctfe)
        {
            alias R = MaybeR;
            static assert(R.sizeof >= T.sizeof * 2);
            import mir.ndslice.internal: _expect;
            //Use Daniel Lemire's fast alternative to modulo reduction:
            //https://lemire.me/blog/2016/06/30/fast-random-shuffling/
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
    }
    else version(LDC)
    {
        static if (T.sizeof == ulong.sizeof && probablyCanMultiply128 && is(core.simd.Vector!(ulong[2])))
        {
            if (!__ctfe)
            {
                import mir.ndslice.internal: _expect;
                //Use Daniel Lemire's fast alternative to modulo reduction:
                //https://lemire.me/blog/2016/06/30/fast-random-shuffling/
                mul_128_u u = void;
                u.v = mul_128(gen.rand!ulong, cast(ulong)m);
                if (_expect(u.leftover < m, false))
                {
                    immutable T threshold = -m % m;
                    while (u.leftover < threshold)
                    {
                        u.v = mul_128(gen.rand!ulong, cast(ulong)m);
                    }
                }
                return u.highbits;
            }
        }
    }
    //Default algorithm.
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

///
@nogc nothrow pure @safe version(mir_random_test) unittest
{
    import mir.random.engine.xorshift;
    auto gen = Xorshift(1);
    auto s = gen.randIndex!uint(100);
    auto n = gen.randIndex!ulong(-100);
}

@nogc nothrow pure @safe version(mir_random_test) unittest
{
    //Test randIndex!uint from generator with return type ulong.
    import mir.random.engine.xorshift;
    auto gen = Xoroshiro128Plus(1);
    static assert(is(EngineReturnType!(typeof(gen)) == ulong));
    uint s = gen.randIndex!uint(100);

    //Test CTFE of randIndex!uint from generator with return type ulong. 
    enum uint e = () {
            auto g = Xoroshiro128Plus(1);
            return g.randIndex!uint(100);
        }();
}

@nogc nothrow pure @safe version(mir_random_test) unittest
{
    //Test production of ulong from ulong generator.
    import mir.random.engine.xorshift;
    auto gen = Xoroshiro128Plus(1);
    enum ulong limit = 10;
    enum count = 10;
    ulong[limit] buckets;
    foreach (_; 0 .. count)
    {
        ulong x = gen.randIndex!ulong(limit);
        assert(x < limit);
        buckets[cast(size_t) x] += 1;
    }
    foreach (i, x; buckets)
        assert(x != count, "All values were the same!");
}

/++
    Returns: `n >= 0` such that `P(n) := 1 / (2^^(n + 1))`.
+/
size_t randGeometric(G)(ref G gen)
    if(isSaturatedRandomEngine!G)
{
    alias R = EngineReturnType!G;
    static if (is(R == ulong))
        alias T = size_t;
    else
        alias T = R;
    for(size_t count = 0;; count += T.sizeof * 8)
        if(auto val = gen.rand!T())
            return count + bsf(val);
}

/++
Params:
    gen = saturated random number generator
Returns:
    `X ~ Exp(1) / log(2)`.
Note: `fabs` can be used to get a value from positive interval `[0, 2^^boundExp$(RPAREN)`.
+/
T randExponential2(T, G)(ref G gen)
    if (isSaturatedRandomEngine!G && isFloatingPoint!T)
{
    enum W = T.sizeof * 8 - T.mant_dig - 1 - bool(T.mant_dig == 64);
    static if (is(T == float))
    {
        auto d = gen.rand!uint;
        enum uint EXPMASK = 0xFF80_0000;
        auto exp = EXPMASK & d;
        d &= ~EXPMASK;
        d ^= 0x3F000000; // 0.5
        auto y = exp ? bsf(exp) - (T.mant_dig - 1) : gen.randGeometric + W;
        auto x = *cast(T*)&d;
    }
    else
    static if (is(T == double))
    {
        auto d = gen.rand!ulong;
        enum ulong EXPMASK = 0xFFF0_0000_0000_0000;
        auto exp = EXPMASK & d;
        d &= ~EXPMASK;
        d ^= 0x3FE0000000000000; // 0.5
        auto y = exp ? bsf(exp) - (T.mant_dig - 1) : gen.randGeometric + W;
        auto x = *cast(T*)&d;
    }
    else
    static if (T.mant_dig == 64)
    {
        _U ret = void;
        ret.e = 0x3FFE;
        ret.m = gen.rand!ulong | ~long.max;
        auto y = gen.randGeometric;
        auto x = ret.r;
    }
    /// TODO: quadruple
    else static assert(0);

    if (x == 0.5f)
        return y;
    else
        return -log2(x) + y;
}

///
version(mir_random_test) unittest
{
    import mir.random.engine.xorshift;
    auto gen = Xorshift(cast(uint)unpredictableSeed);
    auto v = gen.randExponential2!double();
}
