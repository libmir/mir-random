/++
$(SCRIPT inhibitQuickIndex = 1;)

$(BOOKTABLE $(H2 Utilities),

    $(TR $(TH Name), $(TH Description))
    $(T2 RandomVariable, Attribute)
    $(T2 isRandomVariable, Trait)
)

$(BOOKTABLE $(H2 Random Variables),

    $(TR $(TH Generator name) $(TH Description))
    $(RVAR Bernoulli, $(WIKI_D Bernoulli))
    $(RVAR Bernoulli2, Optimized $(WIKI_D Bernoulli) for `p = 1/2`)
    $(RVAR Beta, $(WIKI_D Beta))
    $(RVAR Binomial, $(WIKI_D Binomial))
    $(RVAR Cauchy, $(WIKI_D Cauchy))
    $(RVAR ChiSquared, $(WIKI_D Chi-squared))
    $(RVAR Discrete, Discrete distribution)
    $(RVAR Exponential, $(WIKI_D Exponential))
    $(RVAR ExtremeValue, $(WIKI_D2 Generalized_extreme_value, Extreme value))
    $(RVAR FisherF, $(WIKI_D F))
    $(RVAR Gamma, $(WIKI_D Gamma))
    $(RVAR Geometric, $(WIKI_D Geometric))
    $(RVAR LogNormal, $(WIKI_D Log-normal))
    $(RVAR NegativeBinomial, $(WIKI_D Negative_binomial))
    $(RVAR Normal, $(WIKI_D Normal))
    $(RVAR PiecewiseConstant, Piecewise constant distribution)
    $(RVAR PiecewiseLinear, Piecewise linear distribution)
    $(RVAR Poisson, $(WIKI_D Poisson))
    $(RVAR StudentT, $(WIKI_D Student's_t))
    $(RVAR Uniform, $(WIKI_D Discrete_uniform)
and $(HTTP en.wikipedia.org/wiki/Uniform_distribution_(continuous),
    Uniform distribution (continuous)))
    $(RVAR Weibull, $(WIKI_D Weibull))
)

Authors: Ilya Yaroshenko, Sebastian Wilzbach (DiscreteVariable)
Copyright: Copyright, Ilya Yaroshenko 2016-.
License:    $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).

Macros:
    WIKI_D = $(HTTP en.wikipedia.org/wiki/$1_distribution, $1 random variable)
    WIKI_D2 = $(HTTP en.wikipedia.org/wiki/$1_distribution, $2 random variable)
    T2=$(TR $(TDNW $(LREF $1)) $(TD $+))
    RVAR = $(TR $(TDNW $(LREF $1Variable)) $(TD $+))
+/
module mir.random.variable;

import mir.random;
import std.traits;

import std.math : nextDown, isFinite, LN2;

import mir.math.internal;

private T sumSquares(T)(const T a, const T b)
{
    return fmuladd(a, a, b * b);
}

/// User Defined Attribute definition for Random Variable.
enum RandomVariable;

/++
Test if T is a random variable.
+/
template isRandomVariable(T)
{
    static if (is(typeof(T.isRandomVariable) : bool))
    {
        enum isRandomVariable = T.isRandomVariable && 
            is(typeof({
                auto gen = Random(1);
                T rv;
                auto x = rv(gen);
                auto y = rv!Random(gen);
                static assert(is(typeof(x) == typeof(y)));
            }));
    }
    else enum isRandomVariable = false;
}

/++
$(WIKI_D Discrete_uniform).
Returns: `X ~ U[a, b]`
+/
struct UniformVariable(T)
    if (isIntegral!T)
{
    ///
    enum isRandomVariable = true;

    private alias U = Unsigned!T;
    private U length;
    private T location = 0;

    /++
    Constraints: `a <= b`.
    +/
    this(T a, T b)
    {
        assert(a <= b, "constraint: a <= b");
        length = b - a + 1;
        location = a;
    }

    ///
    T opCall(G)(ref G gen)
        if (isSaturatedRandomEngine!G)
    {
        return length ? gen.randIndex!U(length) + location : gen.rand!U;
    }

    ///
    T min() @property { return location; }
    ///
    T max() @property { return length - 1 + location; }
}

///
unittest
{
    auto gen = Random(unpredictableSeed);
    auto rv = UniformVariable!int(-10, 10); // [-10, 10]
    auto x = rv(gen); // random variable
    assert(rv.min == -10);
    assert(rv.max == 10);
}

/++
$(HTTP en.wikipedia.org/wiki/Uniform_distribution_(continuous), Uniform distribution (continuous)).
Returns: `X ~ U[a, b)`
+/
struct UniformVariable(T)
    if (isFloatingPoint!T)
{
    ///
    enum isRandomVariable = true;

    private T _a;
    private T _b;

    /++
    Constraints: `a < b`, `a` and `b` are finite numbers.
    +/
    this(T a, T b)
    {
        assert(a < b, "constraint: a < b");
        assert(a.isFinite);
        assert(b.isFinite);
        _a = a;
        _b = b;
    }

    ///
    T opCall(G)(ref G gen)
        if (isSaturatedRandomEngine!G)
    {
        auto ret =  gen.rand!T.fabs.fmuladd(_b - _a, _a);
        if(ret < _b)
            return ret;
        return max;
    }

    ///
    T min() @property { return _a; }
    ///
    T max() @property { return _b.nextDown; }
}

///
unittest
{
    import std.math : nextDown;
    auto gen = Random(unpredictableSeed);
    auto rv = UniformVariable!double(-8, 10); // [-8, 10)
    auto x = rv(gen); // random variable
    assert(rv.min == -8.0);
    assert(rv.max == 10.0.nextDown);
}

unittest
{
    import std.math : nextDown;
    auto gen = Random(unpredictableSeed);
    auto rv = UniformVariable!double(-8, 10); // [-8, 10)
    foreach(_; 0..1000)
    {
        auto x = rv(gen);
        assert(rv.min <= x && x <= rv.max);
    }
}

/++
$(WIKI_D Exponential).
Returns: `X ~ Exp(β)`
+/
struct ExponentialVariable(T)
    if (isFloatingPoint!T)
{
    ///
    enum isRandomVariable = true;

    private T scale = T(LN2);

    ///
    this(T scale)
    {
        this.scale = T(LN2) * scale;
    }

    ///
    T opCall(G)(ref G gen)
        if (isSaturatedRandomEngine!G)
    {
        return gen.randExponential2!T * scale;
    }

    ///
    enum T min = 0;
    ///
    enum T max = T.infinity;
}

///
unittest
{
    auto gen = Random(unpredictableSeed);
    auto rv = ExponentialVariable!double(1);
    auto x = rv(gen);
}

/++
$(WIKI_D Weibull).
+/
struct WeibullVariable(T)
    if (isFloatingPoint!T)
{
    ///
    enum isRandomVariable = true;

    private T _pow = 1;
    private T scale = 1;

    ///
    this(T shape, T scale = 1)
    {
        _pow = 1 / shape;
        this.scale = scale;
    }

    ///
    T opCall(G)(ref G gen)
        if (isSaturatedRandomEngine!G)
    {
        return ExponentialVariable!T()(gen).pow(_pow) * scale;
    }

    ///
    enum T min = 0;
    ///
    enum T max = T.infinity;
}

///
unittest
{
    auto gen = Random(unpredictableSeed);
    auto rv = WeibullVariable!double(3, 2);
    auto x = rv(gen);
}

/++
$(WIKI_D Gamma).
Returns: `X ~ Gamma(𝝰, 𝞫)`
Params:
    T = floating point type
    Exp = if true log-scaled values are produced. `ExpGamma(𝝰, 𝞫)`.
        The flag is useful when shape parameter is small (`𝝰 << 1`).
+/
struct GammaVariable(T, bool Exp = false)
    if (isFloatingPoint!T)
{
    ///
    enum isRandomVariable = true;

    private T shape = 1;
    private T scale = 1;

    ///
    this(T shape, T scale = 1)
    {
        this.shape = shape;
        if(Exp)
            this.scale = log(scale);
        else
            this.scale = scale;
    }

    ///
    T opCall(G)(ref G gen)
        if (isSaturatedRandomEngine!G)
    {
        T x = void;
        if (shape > 1)
        {
            T b = shape - 1;
            T c = fmuladd(3, shape, - 0.75f);
            for(;;)
            {
                T u = gen.rand!T;
                T v = gen.rand!T;
                T w = (u + 1) * (1 - u);
                T y = sqrt(c / w) * u;
                x = b + y;
                if (!(0 <= x && x < T.infinity))
                    continue;
                auto z = w * v;
                if (z * z * w <= 1 - 2 * y * y / x)
                    break;
                if (fmuladd(3, log(w), 2 * log(fabs(v))) <= 2 * (b * log(x / b) - y))
                    break;
            }
        }
        else
        if (shape < 1)
        {
            T b = 1 - shape;
            T c = 1 / shape;
            for (;;)
            {
                T u = gen.rand!T.fabs;
                T v = gen.randExponential2!T * T(LN2);
                if (u > b)
                {
                    T e = -log((1 - u) * c);
                    u = fmuladd(shape, e, b);
                    v += e;
                }
                static if (Exp)
                {
                    x = log(u) * c;
                    if (x <= log(v))
                        return x + scale;
                }
                else
                {
                    x = pow(u, c);
                    if (x <= v)
                        break;
                }
            }
        }
        else
        {
            x = gen.randExponential2!T * T(LN2);
        }
        static if (Exp)
            return log(x) + scale;
        else
            return x * scale;
    }

    ///
    enum T min = Exp ? -T.infinity : 0;
    ///
    enum T max = T.infinity;
}

///
unittest
{
    auto gen = Random(unpredictableSeed);
    auto rv = GammaVariable!double(1, 1);
    auto x = rv(gen);
}

/++
$(WIKI_D Beta).
Returns: `X ~ Beta(𝝰, 𝞫)`
+/
struct BetaVariable(T)
    if (isFloatingPoint!T)
{
    ///
    enum isRandomVariable = true;

    private T a = 1;
    private T b = 1;

    ///
    this(T a, T b)
    {
        this.a = a;
        this.b = b;
    }

    ///
    T opCall(G)(ref G gen)
        if (isSaturatedRandomEngine!G)
    {
        if (a <= 1 && b <= 1) for (;;)
        {
            T u = gen.randExponential2!T;
            T v = gen.randExponential2!T;
            u = -u;
            v = -v;
            u /= a;
            v /= b;
            T x = exp2(u);
            T y = exp2(v);
            T z = x + y;
            if (z <= 1)
            {
                if (z)
                    return x / z;
                z = fmax(u, v);
                u -= z;
                v -= z;
                return exp2(u - log2(exp2(u) + exp2(v)));
            }
        }
        T x = GammaVariable!T(a)(gen);
        T y = GammaVariable!T(b)(gen);
        T z = x + y;
        return x / z;
    }

    ///
    enum T min = 0;
    ///
    enum T max = 1;
}

///
unittest
{
    auto gen = Random(unpredictableSeed);
    auto rv = BetaVariable!double(2, 5);
    auto x = rv(gen);
}

/++
$(WIKI_D Chi-squared).
+/
struct ChiSquaredVariable(T)
    if (isFloatingPoint!T)
{
    ///
    enum isRandomVariable = true;

    private T _shape = 1;

    ///
    this(size_t k)
    {
        _shape = T(k) / 2;
    }

    ///
    T opCall(G)(ref G gen)
        if (isSaturatedRandomEngine!G)
    {
        return GammaVariable!T(_shape, 2)(gen);
    }

    ///
    enum T min = 0;
    ///
    enum T max = T.infinity;
}

///
unittest
{
    auto gen = Random(unpredictableSeed);
    auto rv = ChiSquaredVariable!double(3);
    auto x = rv(gen);
}

/++
$(WIKI_D F).
+/
struct FisherFVariable(T)
    if (isFloatingPoint!T)
{
    ///
    enum isRandomVariable = true;

    private T _d1 = 1, _d2 = 1;

    ///
    this(T d1, T d2)
    {
        _d1 = d1;
        _d2 = d2;
    }

    ///
    T opCall(G)(ref G gen)
        if (isSaturatedRandomEngine!G)
    {
        auto xv = GammaVariable!T(_d1 * 0.5f);
        auto yv = GammaVariable!T(_d2 * 0.5f);
        auto x = xv(gen);
        auto y = yv(gen);
        x *= _d1;
        y *= _d2;
        return x / y; 
    }

    ///
    enum T min = 0;
    ///
    enum T max = T.infinity;
}

///
unittest
{
    auto gen = Random(unpredictableSeed);
    auto rv = FisherFVariable!double(3, 4);
    auto x = rv(gen);
}

/++
$(WIKI_D Student's_t).
+/
struct StudentTVariable(T)
    if (isFloatingPoint!T)
{
    ///
    enum isRandomVariable = true;

    private NormalVariable!T _nv;
    private T _nu = 1;

    ///
    this(T nu)
    {
        _nu = nu;
    }

    ///
    T opCall(G)(ref G gen)
        if (isSaturatedRandomEngine!G)
    {
        auto x = _nv(gen);
        auto y = _nu / GammaVariable!T(_nu * 0.5f, 2)(gen);
        if(y < T.infinity)
            x *= y.sqrt;
        return x;
    }

    ///
    enum T min = -T.infinity;
    ///
    enum T max = T.infinity;
}

///
unittest
{
    auto gen = Random(unpredictableSeed);
    auto rv = StudentTVariable!double(10);
    auto x = rv(gen);
}

private T hypot01(T)(const T x, const T y)
{
    // Scale x and y to avoid underflow and overflow.
    // If one is huge and the other tiny, return the larger.
    // If both are huge, avoid overflow by scaling by 1/sqrt(real.max/2).
    // If both are tiny, avoid underflow by scaling by sqrt(real.min_normal*real.epsilon).

    enum T SQRTMIN = 0.5f * sqrt(T.min_normal); // This is a power of 2.
    enum T SQRTMAX = 1 / SQRTMIN; // 2^^((max_exp)/2) = nextUp(sqrt(T.max))

    static assert(2*(SQRTMAX/2)*(SQRTMAX/2) <= T.max);

    // Proves that sqrt(T.max) ~~  0.5/sqrt(T.min_normal)
    static assert(T.min_normal*T.max > 2 && T.min_normal*T.max <= 4);

    T u = fabs(x);
    T v = fabs(y);
    if (u < v)
    {
        auto t = v;
        v = u;
        u = t;
    }

    if (u <= SQRTMIN)
    {
        // hypot (tiny, tiny) -- avoid underflow
        // This is only necessary to avoid setting the underflow
        // flag.
        u *= SQRTMAX / T.epsilon;
        v *= SQRTMAX / T.epsilon;
        return sumSquares(u, v).sqrt * (SQRTMIN * T.epsilon);
    }

    if (u * T.epsilon > v)
    {
        // hypot (huge, tiny) = huge
        return u;
    }

    // both are in the normal range
    return sumSquares(u, v).sqrt;
}

/++
$(WIKI_D Normal).
Returns: `X ~ N(μ, σ)`
+/
struct NormalVariable(T)
    if (isFloatingPoint!T)
{
    ///
    enum isRandomVariable = true;

    private T location = 0;
    private T scale = 1;
    private T y = 0;
    private bool hot;

    ///
    this(T location, T scale = 1)
    {
        this.location = location;
        this.scale = scale;
    }

    this(this)
    {
        hot = false;
    }

    ///
    T opCall(G)(ref G gen)
        if (isSaturatedRandomEngine!G)
    {
        T x = void;
        if (hot)
        {
            hot = false;
            x = y;
        }
        else
        {
            T u = void;
            T v = void;
            T s = void;
            do
            {
                u = gen.rand!T;
                v = gen.rand!T;
                s = hypot01(u, v);
            }
            while (s > 1 || s == 0);
            s = 2 * sqrt(-log(s)) / s;
            y = v * s;
            x = u * s;
            hot = true;
        }
        return fmuladd(x, scale, location);
    }

    ///
    enum T min = -T.infinity;
    ///
    enum T max = T.infinity;
}

///
unittest
{
    auto gen = Random(unpredictableSeed);
    auto rv = NormalVariable!double(0, 1);
    auto x = rv(gen);
}

/++
$(WIKI_D Log-normal).
+/
struct LogNormalVariable(T)
    if (isFloatingPoint!T)
{
    ///
    enum isRandomVariable = true;

    private NormalVariable!T _nv;

    /++
    Params:
        normalLocation = location of associated normal
        normalScale = scale of associated normal
    +/
    this(T normalLocation, T normalScale = 1)
    {
        _nv = NormalVariable!T(normalLocation, normalScale);
    }

    ///
    T opCall(G)(ref G gen)
        if (isSaturatedRandomEngine!G)
    {
       return _nv(gen);
    }

    ///
    enum T min = 0;
    ///
    enum T max = T.infinity;
}

///
unittest
{
    auto gen = Random(unpredictableSeed);
    auto rv = LogNormalVariable!double(0, 1);
    auto x = rv(gen);
}

/++
$(WIKI_D Cauchy).
Returns: `X ~ Cauchy(x, γ)`
+/
struct CauchyVariable(T)
    if (isFloatingPoint!T)
{
    ///
    enum isRandomVariable = true;

    private T location = 0;
    private T scale = 1;

    ///
    this(T location, T scale = 1)
    {
        this.location = location;
        this.scale = scale;
    }

    ///
    T opCall(G)(ref G gen)
        if (isSaturatedRandomEngine!G)
    {
        T u = void;
        T v = void;
        T x = void;
        do
        {
            u = gen.rand!T;
            v = gen.rand!T;
        }
        while (sumSquares(u, v) > 1 || !(fabs(x = u / v) < T.infinity));
        return fmuladd(x, scale, location);
    }

    ///
    enum T min = -T.infinity;
    ///
    enum T max = T.infinity;
}

///
unittest
{
    auto gen = Random(unpredictableSeed);
    auto rv = CauchyVariable!double(0, 1);
    auto x = rv(gen);
}

/++
$(WIKI_D2 Generalized_extreme_value, Extreme value).
+/
struct ExtremeValueVariable(T)
    if (isFloatingPoint!T)
{
    ///
    enum isRandomVariable = true;

    private T location = 0;
    private T scale = 1;

    ///
    this(T location, T scale = 1)
    {
        this.location = location;
        this.scale = scale * -T(LN2);
    }

    ///
    T opCall(G)(ref G gen)
        if (isSaturatedRandomEngine!G)
    {
        return fmuladd(log2(gen.randExponential2!T * T(LN2)), scale, location);
    }

    ///
    enum T min = -T.infinity;
    ///
    enum T max = T.infinity;
}

///
unittest
{
    auto gen = Random(unpredictableSeed);
    auto rv = ExtremeValueVariable!double(0, 1);
    auto x = rv(gen);
}

/++
$(WIKI_D Bernoulli).
+/
struct BernoulliVariable(T)
    if (isFloatingPoint!T)
{
    ///
    enum isRandomVariable = true;

    private T p = 0;

    /++
    Params:
        p = `true` probability
    +/
    this(T p)
    {
        assert(0 <= p && p <= 1);
        this.p = p;
    }

    ///
    bool opCall(RNG)(ref RNG gen)
        if (isSaturatedRandomEngine!RNG)
    {
        return gen.rand!T.fabs < p;
    }

    ///
    enum bool min = 0;
    ///
    enum bool max = 1;
}

///
unittest
{
    auto gen = Random(unpredictableSeed);
    auto rv = BernoulliVariable!double(0.7);
    int[2] hist;
    foreach(_; 0..1000)
        hist[rv(gen)]++;
    //import std.stdio;
    //writeln(hist);
}

/++
$(WIKI_D Bernoulli). A fast specialization for `p := 1/2`.
+/
struct Bernoulli2Variable
{
    ///
    enum isRadomVariable = true;
   private size_t payload;
    private size_t mask;

    this(this)
    {
        payload = mask = 0;
    }

    ///
    bool opCall(RNG)(ref RNG gen)
        if (isSaturatedRandomEngine!RNG)
    {
        if(mask == 0)
        {
            mask = sizediff_t.min;
            payload = gen.rand!size_t;
        }
        bool ret = (payload & mask) != 0;
        mask >>>= 1;
        return ret;
    }

    ///
    enum bool min = 0;
    ///
    enum bool max = 1;
}

///
unittest
{
    auto gen = Random(unpredictableSeed);
    auto rv = Bernoulli2Variable.init;
    int[2] hist;
    foreach(_; 0..1000)
        hist[rv(gen)]++;
    //import std.stdio;
    //writeln(hist);
}

/++
$(WIKI_D Geometric).
+/
struct GeometricVariable(T)
    if (isFloatingPoint!T)
{
    ///
    enum isRandomVariable = true;

    private T scale = 1;

    /++
    Params:
        p = probability
        reverse = p is success probability if `true` and failure probability otherwise.
    +/
    this(T p, bool success = true)
    {
        assert(0 <= p && p <= 1);
        scale = -1 / log2(success ? 1 - p : p);
    }

    ///
    ulong opCall(RNG)(ref RNG gen)
        if (isSaturatedRandomEngine!RNG)
    {
        auto ret = gen.randExponential2!T * scale;
        return ret < ulong.max ? cast(ulong)ret : ulong.max;
    }

    ///
    enum ulong min = 0;
    ///
    enum ulong max = ulong.max;
}

///
unittest
{
    auto gen = Random(unpredictableSeed);
    auto rv = GeometricVariable!double(0.1);
    size_t[ulong] hist;
    foreach(_; 0..1000)
        hist[rv(gen)]++;
    //import std.stdio;
    //foreach(i; 0..100)
    //    if(auto count = i in hist)
    //        write(*count, ", ");
    //    else
    //        write("0, ");
    //writeln();
}

private T _mLogFactorial(T)(ulong k)
{
    ulong r = 1;
    foreach(i; 2 .. k + 1)
        r *= k;
    return -log(T(k));
}

private enum mLogFactorial(T) = [
    _mLogFactorial!T(0),
    _mLogFactorial!T(1),
    _mLogFactorial!T(2),
    _mLogFactorial!T(3),
    _mLogFactorial!T(4),
    _mLogFactorial!T(5),
    _mLogFactorial!T(6),
    _mLogFactorial!T(7),
    _mLogFactorial!T(8),
    _mLogFactorial!T(9),
];

/++
$(WIKI_D Poisson).
+/
struct PoissonVariable(T)
    if (isFloatingPoint!T)
{
    ///
    enum isRandomVariable = true;

    import std.math : E;
    private T rate = 1;
    private T temp1 = 1 / E;
    T a = void, b = void;

    /++
    Params:
        p = probability
        reverse = p is success probability if `true` and failure probability otherwise.
    +/
    this(T rate)
    {
        this.rate = rate;
        if (rate >= 10)
        {
            temp1 = rate.log;
            b = fmuladd(sqrt(rate), T(2.53), T(0.931));
            a = fmuladd(b, T(0.02483), T(-0.059));
        }
        else
            temp1 = exp(-rate);
    }

    ///
    ulong opCall(RNG)(ref RNG gen)
        if (isSaturatedRandomEngine!RNG)
    {
        import core.stdc.tgmath: lgamma;
        if (rate >= 10) for (;;)
        {
            T u = gen.rand!T(-1);
            T v = gen.rand!T.fabs;
            T us = 0.5f - fabs(u);
            T kr = fmuladd(2 * a / us + b, u, rate) + T(0.43);
            if (!(kr >= 0))
                continue;
            long k = cast(long)kr;
            if (us >= T(0.07) && v <= T(0.9277) - T(3.6224) / (b - 2))
                return k;
            if (k < 0 || us < T(0.013) && v > us)
                continue;
            if (log(v * (T(1.1239) + T(1.1328) / (b - T(3.4))) / (a / (us * us) + b))
                    <= k * temp1 - rate - lgamma(T(k + 1)))
                return k;
        }
        T prod = 1.0;
        for(size_t x = 0; ; x++)
        {
            prod *= gen.rand!T.fabs;
            if (prod <= temp1)
                return x;
        }
    }

    ///
    enum ulong min = 0;
    ///
    enum ulong max = ulong.max;
}

///
unittest
{
    import mir.random;
    auto gen = Random(unpredictableSeed);
    auto rv = PoissonVariable!double(10);
    size_t[ulong] hist;
    foreach(_; 0..1000)
        hist[rv(gen)]++;
    //import std.stdio;
    //foreach(i; 0..100)
    //    if(auto count = i in hist)
    //        write(*count, ", ");
    //    else
    //        write("0, ");
    //writeln();
}

/++
$(WIKI_D Negative_binomial).
+/
struct NegativeBinomialVariable(T)
    if (isFloatingPoint!T)
{
    ///
    enum isRandomVariable = true;

    size_t r;
    T p;

    /++
    Params:
        r = r > 0; number of failures until the experiment is stopped
        p = p ∈ (0,1); success probability in each experiment
    +/
    this(size_t r, T p)
    {
        this.r = r;
        this.p = p;
    }

    ///
    ulong opCall(RNG)(ref RNG gen)
        if (isSaturatedRandomEngine!RNG)
    {
        if (r <= 21 * p)
        {
            auto bv = BernoulliVariable!T(p);
            size_t s, f;
            do (bv(gen) ? s : f)++;
            while (s < r);
            return f;
        }
        return PoissonVariable!T(GammaVariable!T(r, (1 - p) / p)(gen))(gen);
    }

    ///
    enum ulong min = 0;
    ///
    enum ulong max = ulong.max;
}

///
unittest
{
    import mir.random;
    auto gen = Random(unpredictableSeed);
    auto rv = NegativeBinomialVariable!double(30, 0.3);
    size_t[ulong] hist;
    foreach(_; 0..1000)
        hist[rv(gen)]++;
    //import std.stdio;
    //foreach(i; 0..100)
    //    if(auto count = i in hist)
    //        write(*count, ", ");
    //    else
    //        write("0, ");
    //writeln();
}

/++
$(WIKI_D Binomial).
+/
struct BinomialVariable(T)
    if (isFloatingPoint!T)
{
    ///
    enum isRandomVariable = true;

    import core.stdc.tgmath: lgamma;
    size_t n = void;
    T np = void;
    T q = void;
    T qn = void;
    T r = void;
    T g = void;
    T b = void;
    T a = void;
    T c = void;
    T vr = void;
    T alpha = void;
    T lpq = void;
    T fm = void;
    T h = void;
    bool swap = void;
    @disable this();

    /++
    Params:
        n = n > 0; number of trials
        p = p ∈ [0,1]; success probability in each trial
    +/
    this(size_t n, T p)
    {
        this.n = n;
        if(p <= 0.5f)
        {
            this.q = 1 - p;
            swap = false;
        }
        else
        {
            this.q = p;
            swap = true;
            p = 1 - p;
        }
        np = p * n;
        if (np >= 10)
        {
            auto spq = sqrt(np * q);

            b = fmuladd(spq, 2.53f, 1.15f);
            a = fmuladd(p, 0.01f, fmuladd(b, 0.0248f, -0.0873f));
            c = fmuladd(p, n, 0.5f);
            vr = 0.92f - 4.2f/ b;
            alpha = (2.83f+5.1f / b) * spq;
            lpq = log(p / q);
            fm = floor((n + 1) * p);
            h = lgamma(fm + 1) + lgamma(n - fm - 1);
        }
        else
        {
            qn = pow (q, n);
            r = p / q;
            g = r *  (n + 1);
        }
    }

    ///
    size_t opCall(RNG)(ref RNG gen)
        if (isSaturatedRandomEngine!RNG)
    {
        T kr = void;
        if (np >= 10) for (;;)
        {
            T u = gen.rand!T(-1);
            T us = 0.5 - u.fabs;
            kr = floor (fmuladd(2 * a / us + b, u, c));
            if (kr < 0)
                continue;
            if (kr > n)
                continue;
            T v = gen.rand!T();
            if (us >= 0.07f && v <= vr)
                break;
            v = log (v * alpha / (a / (us * us) + b));
            if (v <= (h - lgamma(kr + 1) - lgamma(n - kr + 1) + (kr - fm) * lpq))
                break;
        }
        else
        {
            enum max_k = 110;

            T f = qn;
            T u = gen.rand!T.fabs;
            T kmax = n > max_k ? max_k : n;
            kr = 0;
            do
            {
                if (u < f)
                    break;
                u -= f;
                kr++;
                f *= (g / kr - r);
            }
            while (kr <= kmax);
        }
        auto ret = cast(typeof(return)) kr;
        return swap ? n - ret : ret;
    }

    ///
    enum size_t min = 0;
    ///
    size_t max() @property { return n; };
}

///
unittest
{
    import mir.random;
    auto gen = Random(unpredictableSeed);
    auto rv = BinomialVariable!double(20, 0.5);
    int[] hist = new int[rv.max + 1];
    auto cnt = 1000;
    foreach(_; 0..cnt)
        hist[rv(gen)]++;
    //import std.stdio;
    //foreach(n, e; hist)
    //    writefln("p(x = %s) = %s", n, double(e) / cnt);
}

/++
_Discrete distribution sampler that draws random values from a _discrete
distribution given an array of the respective probability density points (weights).
+/
struct DiscreteVariable(T)
    if (isNumeric!T)
{
    ///
    enum isRandomVariable = true;

    private T[] cdf;

    /++
    `DiscreteVariable` constructor computes cumulative density points
    in place without memory allocation.

    Params:
        weights = density points
        cumulative = optional flag indiciates if `weights` are already cumulative
    +/
    this(T[] weights, bool cumulative = false)
    {
        if(!cumulative)
        {
            static if (isFloatingPoint!T)
            {
                import mir.math.sum;
                Summator!(T, Summation.kb2) s = 0;
                foreach(ref e; weights)
                {
                    s += e;
                    e = s.sum;
                }
            }
            else
            {
                T s = 0;
                foreach(ref e; weights)
                {
                    s += e;
                    e = s;
                }
            }
        }
        cdf = weights;
    }

    /++
    Samples a value from the discrete distribution using a custom random generator.
    Complexity:
        `O(log n)` where `n` is the number of `weights`.
    +/
    size_t opCall(RNG)(ref RNG gen)
        if (isSaturatedRandomEngine!RNG)
    {
        import std.range : assumeSorted;
        static if (isFloatingPoint!T)
            T v = gen.rand!T.fabs * cdf[$-1];
        else
            T v = gen.randIndex!(Unsigned!T)(cdf[$-1]);
        return cdf.length - cdf.assumeSorted!"a < b".upperBound(v).length;
    }

    ///
    enum size_t min = 0;
    ///
    size_t max() @property { return cdf.length - 1; }
}

///
unittest
{
    auto gen = Random(unpredictableSeed);
    // 10%, 20%, 20%, 40%, 10%
    auto weights = [10.0, 20, 20, 40, 10];
    auto ds = DiscreteVariable!double(weights);

    // weight is changed to cumulative sums
    assert(weights == [10, 30, 50, 90, 100]);

    // sample from the discrete distribution
    auto obs = new uint[weights.length];
    
    foreach (i; 0..1000)
        obs[ds(gen)]++;

    //import std.stdio;
    //writeln(obs);
}

/// Comulative
unittest
{
    auto gen = Random(unpredictableSeed);

    auto cumulative = [10.0, 30, 40, 90, 120];
    auto ds = DiscreteVariable!double(cumulative, true);

    assert(cumulative == [10.0, 30, 40, 90, 120]);

    // sample from the discrete distribution
    auto obs = new uint[cumulative.length];
    foreach (i; 0..1000)
        obs[ds(gen)]++;
}

//
unittest
{
    auto gen = Random(unpredictableSeed);
    // 10%, 20%, 20%, 40%, 10%
    auto weights = [10.0, 20, 20, 40, 10];
    auto ds = DiscreteVariable!double(weights);

    // weight is changed to cumulative sums
    assert(weights == [10, 30, 50, 90, 100]);

    // sample from the discrete distribution
    auto obs = new uint[weights.length];
    foreach (i; 0..1000)
        obs[ds(gen)]++;

    //import std.stdio;
    //writeln(obs);
    //[999, 1956, 2063, 3960, 1022]
}

// test with cumulative probs
unittest
{
    auto gen = Random(unpredictableSeed);

    // 10%, 20%, 20%, 40%, 10%
    auto weights = [0.1, 0.3, 0.5, 0.9, 1];
    auto ds = DiscreteVariable!double(weights, true);

    auto obs = new uint[weights.length];
    foreach (i; 0..1000)
        obs[ds(gen)]++;


    //assert(obs == [1030, 1964, 1968, 4087, 951]);
}

// test with cumulative count
unittest
{
    auto gen = Random(unpredictableSeed);

    // 1, 2, 1
    auto weights = [1, 2, 1];
    auto ds = DiscreteVariable!int(weights);

    auto obs = new uint[weights.length];
    foreach (i; 0..1000)
        obs[ds(gen)]++;

    //assert(obs == [2536, 4963, 2501]);
}

// test with zero probabilities
unittest
{
    auto gen = Random(unpredictableSeed);

    // 0, 1, 2, 0, 1
    auto weights = [0, 1, 3, 3, 4];
    auto ds = DiscreteVariable!int(weights, true);

    auto obs = new uint[weights.length];
    foreach (i; 0..1000)
        obs[ds(gen)]++;

    assert(obs[3] == 0);
}

/++
Piecewise constant variable.
+/
struct PiecewiseConstantVariable(T, W = T)
    if (isNumeric!T && isNumeric!W)
{
    ///
    enum isRandomVariable = true;

    private DiscreteVariable!W dv;
    private T[] intervals;

    /++
    `PiecewiseConstantVariable` constructor computes cumulative density points
    in place without memory allocation.
    Params:
        intervals = strictly increasing sequence of interval bounds.
        weights = density points
        cumulative = optional flag indicates if `weights` are already cumulative
    +/
    this(T[] intervals, W[] weights, bool cumulative = false)
    {
        assert(weights.length);
        assert(intervals.length == weights.length + 1);
        dv = DiscreteVariable!W(weights, cumulative);
        this.intervals = intervals; 
    }

    /++
    Complexity:
        `O(log n)` where `n` is the number of `weights`.
    +/
    T opCall(RNG)(ref RNG gen)
        if (isSaturatedRandomEngine!RNG)
    {
        size_t index = dv(gen);
        return UniformVariable!T(intervals[index], intervals[index + 1])(gen);
    }

    ///
    T min() @property { return intervals[0]; }
    ///
    T max() @property { return intervals[$-1].nextDown; }
}

///
unittest
{
    auto gen = Random(unpredictableSeed);
    // 50% of the time, generate a random number between 0 and 1
    // 50% of the time, generate a random number between 10 and 15
    double[] i = [0,  1, 10, 15];
    double[] w =   [1,  0,  1];
    auto pcv = PiecewiseConstantVariable!(double, double)(i, w);
    assert(w == [1, 1, 2]);

    int[int] hist;
    foreach(_; 0 .. 10000)
        ++hist[cast(int)pcv(gen)];

    //import std.stdio, std.range;
    //foreach(j; 0..cast(int)i[$-1])
    //    if(auto count = j in hist)
    //        writefln("%2s %s", j, '*'.repeat.take(*count / 100));

    //////// output example /////////
    /+
     0 **************************************************
    10 *********
    11 *********
    12 **********
    13 *********
    14 **********
    +/
}

/++
Piecewise constant variable.
+/
struct PiecewiseLinearVariable(T)
    if (isFloatingPoint!T)
{
    ///
    enum isRandomVariable = true;

    private DiscreteVariable!T dv;
    private T[] points;
    private T[] weights;

    /++
    Params:
        intervals = strictly increasing sequence of interval bounds.
        weights = density points
        areas =  user allocated uninitialized array
    Constrains:
        `points.length == weights.length` $(BR)
        `areas.length > 0` $(BR)
        `areas.length + 1 == weights.length`
    +/
    this(T[] points, T[] weights, T[] areas)
    in {
        assert(points.length == weights.length);
        assert(areas.length);
        assert(areas.length + 1 == weights.length);
    }
    body {
        foreach(size_t i; 0 .. areas.length)
            areas[i] = (weights[i + 1] + weights[i]) * (points[i + 1] - points[i]);
        dv = DiscreteVariable!T(areas);
        this.points = points;
        this.weights = weights;
    }

    /++
    Complexity:
        `O(log n)` where `n` is the number of `weights`.
    +/
    T opCall(RNG)(ref RNG gen)
        if (isSaturatedRandomEngine!RNG)
    {
        size_t index = dv(gen);
        T w0 = weights[index + 0];
        T w1 = weights[index + 1];
        T b0 = points [index + 0];
        T b1 = points [index + 1];
        T ret = gen.rand!T.fabs;
        T z = fmin(w0, w1) / fmax(w0, w1);
        if(!(z > gen.rand!T(-1).fabs * (1 + z)))
            ret = ret.sqrt;
        ret *= b1 - b0;
        if(w0 > w1)
            ret = b1 - ret;
        else
            ret = ret + b0;
        if(!(ret < b1))
            ret = b1.nextDown;
        return ret;
    }

    ///
    T min() @property { return points[0]; }
    ///
    T max() @property { return points[$-1].nextDown; }
}

///
unittest
{
    auto gen = Random(unpredictableSeed);
    // increase the probability from 0 to 5
    // remain flat from 5 to 10
    // decrease from 10 to 15 at the same rate
    double[] i = [0, 5, 10, 15];
    double[] w = [0, 1,  1,  0];
    auto pcv = PiecewiseLinearVariable!double(i, w, new double[w.length - 1]);

    int[int] hist;
    foreach(_; 0 .. 10000)
        ++hist[cast(int)pcv(gen)];

    //import std.stdio, std.range;
    //foreach(j; 0..cast(int)i[$-1]+1)
    //    if(auto count = j in hist)
    //        writefln("%2s %s", j, '*'.repeat.take(*count / 100));

    //////// output example /////////
    /+
     0 *
     1 **
     2 *****
     3 *******
     4 ********
     5 **********
     6 *********
     7 *********
     8 **********
     9 *********
    10 *********
    11 *******
    12 ****
    13 **
    14 *
    +/
}
