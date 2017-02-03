/++
Authors: Ilya Yaroshenko, documentation is partially based on Phobos.
Copyright: Copyright, Ilya Yaroshenko 2016-.
License:  $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
+/
module mir.random.algorithm;

import std.range.primitives;
import std.traits;
import mir.math.internal;

import mir.random;
public import mir.random.engine;

/++
Range interface for uniform random bit generators.

Note:
    The structure holds a pointer to a generator.
    The structure must not be copied (explicitly or implicitly) outside from a function.
+/
struct RandomRange(G)
    if (isSaturatedRandomEngine!G)
{
    private G* _gen;
    private ReturnType!G _val;
    /// Largest generated value.
    enum ReturnType!G max = G.max;
    /// Constructor. Stores the pointer to the `gen` engine.
    this(ref G gen) { _gen = &gen; popFront(); }
    /// Infinity Input Range primitives
    enum empty = false;
    /// ditto
    ReturnType!G front() @property { return _val; }
    /// ditto
    void popFront() { _val = (*_gen)(); }
}

/// ditto
RandomRange!G range(G)(ref G gen)
    if (isSaturatedRandomEngine!G)
{
    return typeof(return)(gen);
}

///
unittest
{
    import std.range, std.algorithm;
    import mir.random.engine.xorshift;
    auto rng = Xorshift(1);
    auto bitSample = rng // by reference
        .range
        .filter!(val => val % 2 == 0)
        .map!(val => val % 100)
        .take(5)
        .array;
    assert(bitSample == [58, 30, 86, 16, 76]);
}

/++
Range interface for random variables.

Note:
    The structure hold a pointer to a generator.
    The structure must not be copied (explicitly or implicitly) outside from a function.
+/
struct RandomRange(G, D)
    if (isSaturatedRandomEngine!G)
{
    private D _var;
    private G* _gen;
    private Unqual!(typeof(_var(*_gen))) _val;
    /// Constructor. Stores the pointer to the `gen` engine.
    this(ref G gen, D var) { _gen = &gen; _var = var; popFront(); }
    /// Infinity Input Range primitives
    enum empty = false;
    /// ditto
    auto front() @property { return _val; }
    /// ditto
    void popFront() { _val = _var(*_gen); }
}

/// ditto
RandomRange!(G, D) range(G, D)(ref G gen, D var)
    if (isSaturatedRandomEngine!G)
{
    return typeof(return)(gen, var);
}

///
unittest
{
    import std.range : take, array;

    import mir.random;
    import mir.random.variable: NormalVariable;

    auto rng = Random(unpredictableSeed);
    auto sample = rng // by reference
        .range(NormalVariable!double(0, 1))
        .take(1000)
        .array;

    //import std.stdio;
    //writeln(sample);
}

/++
Random sampling utility.
Complexity:
    O(n)
References:
    Jeffrey Scott Vitter, An efficient algorithm for sequential random sampling
+/
struct VitterStrides
{
    private enum alphainv = 16;
    private double vprime;
    private size_t N;
    private size_t n;
    private bool hot;

    this(this)
    {
        hot = false;
    }

    /++
    Params:
        N = range length
        n = sample length
    +/
    this(size_t N, size_t n)
    {
        assert(N >= n);
        this.N = N;
        this.n = n;
    }

    /// Returns: `true` if sample length equals to 0.
    bool empty() @property { return n == 0; }
    /// Returns: `N` (remaining sample length)
    size_t length() @property { return n; }
    /// Returns: `n` (remaining range length)
    size_t tail() @property { return N; }

    /++
    Returns: random stride step (`S`).
        After each call `N` decreases by `S + 1` and `n` decreases by `1`.
    Params:
        gen = random number engine to use
    +/
    sizediff_t opCall(G)(ref G gen)
    {
        pragma(inline, false);
        import std.math: LN2;
        import mir.random;
        size_t S;
        switch(n)
        {
        default:
            double Nr = N;
            if(alphainv * n > N)
            {
                hot = false;
                double top = N - n;
                double v = gen.rand!double.fabs;
                double quot = top / Nr;
                while(quot > v)
                {
                    top--;
                    Nr--;
                    S++;
                    quot *= top / Nr;
                }
                goto R;
            }
            double nr = n;
            if(hot)
            {
                hot = false;
                goto L;
            }
        M:
            vprime = exp2(-gen.randExponential2!double / nr);
        L:
            double X = Nr * (1 - vprime);
            S = cast(size_t) X;
            if (S + n > N)
                goto M;
            size_t qu1 = N - n + 1;
            double qu1r = qu1;
            double y1 = exp2(gen.randExponential2!double / (1 - nr) + double(1 / LN2) / qu1r);
            vprime = y1 * (1 - X / Nr) * (qu1r / (qu1r - S));
            if (vprime <= 1)
            {
                hot = true;
                goto R;
            }
            double y2 = 1;
            double top = Nr - 1;
            double bottom = void;
            size_t limit = void;
            if(n > S + 1)
            {
                bottom = N - n;
                limit = N - S;
            }
            else
            {
                bottom = N - (S + 1);
                limit = qu1;
            }
            foreach_reverse(size_t t; limit .. N)
            {
                y2 *= top / bottom;
                top--;
                bottom--;
            }
            if(Nr / (Nr - X) >= y1 * exp2(log2(y2) / (nr - 1)))
                goto R;
            goto M;
        case 1:
            S = gen.randIndex(N);
        R:
            N -= S + 1;
            n--;
            return S;
        case 0:
            S = -1;
            goto R;
        }
    }
}

///
unittest
{
    import mir.random.engine.xorshift;
    auto gen = Xorshift(112);
    auto strides = VitterStrides(20, 3);
    size_t s;
    foreach(_; 0..3)
    {
        s += strides(gen) + 1;
        assert(s + strides.tail == 20);
    }
}

/++
Selects a random subsample out of `range`, containing exactly `n` elements.
The order of elements is the same as in the original range.
Returns: $(LREF RandomSample) over the `range`.
Params:
    range = range to sample from
    gen = random number engine to use
    n = number of elements to include in the sample; must be less than or equal to the `range.length`
Complexity: O(n)
+/
auto sample(Range, G)(Range range, ref G gen, size_t n)
    if(isInputRange!Range && hasLength!Range && isSaturatedRandomEngine!G)
{
    return RandomSample!(Range, G)(range, gen, n);
}

///
unittest
{
    import std.range;
    import mir.random.engine.xorshift;
    auto gen = Xorshift(112);
    auto sample = iota(100).sample(gen, 7);
    foreach(elem; sample)
    {
        //import std.stdio;
        //writeln(elem);
    }
}

unittest
{
    import std.algorithm.comparison;
    import std.range;
    import mir.random.engine.xorshift;
    auto gen = Xorshift(232);
    assert(iota(0).equal(iota(0).sample(gen, 0)));
    assert(iota(1).equal(iota(1).sample(gen, 1)));
    assert(iota(2).equal(iota(2).sample(gen, 2)));
    assert(iota(3).equal(iota(3).sample(gen, 3)));
    assert(iota(8).equal(iota(8).sample(gen, 8)));
    assert(iota(1000).equal(iota(1000).sample(gen, 1000)));
}

/++
Lazy input or forward range containing a random sample.
$(LREF VitterStrides) is used to skip elements.
Complexity: O(n)
Note:
    The structure holds a pointer to a generator.
    The structure must not be copied (explicitly or implicitly) outside from a function.
+/
struct RandomSample(Range, G)
{
    private VitterStrides strides;
    private G* gen;
    private Range range;
    ///
    this(Range range, ref G gen, size_t n)
    {
        this.range = range;
        this.gen = &gen;
        strides = VitterStrides(range.length, n);
        auto s = strides(*this.gen);
        if(s > 0)
            this.range.popFrontExactly(s);
    }

    /// Range primitives
    size_t length() @property { return strides.length + 1; }
    /// ditto
    bool empty() @property { return length == 0; }
    /// ditto
    auto ref front() @property { return range.front; }
    /// ditto
    void popFront() { range.popFrontExactly(strides(*gen) + 1); }
    /// ditto
    static if (isForwardRange!Range)
    auto save() @property { return RandomSample(range.save, *gen, length); }
}

/++
Shuffles elements of `range`.
Params:
    gen = random number engine to use
    range = random-access range whose elements are to be shuffled
Complexity: O(range.length)
+/
void shuffle(Range, G)(ref G gen, Range range)
    if (isSaturatedRandomEngine!G && isRandomAccessRange!Range && hasLength!Range)
{
    import std.algorithm.mutation : swapAt;
    for (; !range.empty; range.popFront)
        range.swapAt(0, gen.randIndex(range.length));
}

///
static if (__VERSION__ >= 2072)
unittest
{
    import std.experimental.ndslice;
    import std.algorithm.sorting;

    auto gen = Random(unpredictableSeed);
    auto a = iotaSlice(10).slice;

    gen.shuffle(a);

    sort(a);
    assert(a == iotaSlice(10));
}

/++
Partially shuffles the elements of `range` such that upon returning `range[0..n]`
is a random subset of `range` and is randomly ordered. 
`range[n..r.length]` will contain the elements not in `range[0..n]`.
These will be in an undefined order, but will not be random in the sense that their order after
`shuffle` returns will not be independent of their order before
`shuffle` was called.
Params:
    gen = random number engine to use
    range = random-access range with length whose elements are to be shuffled
    n = number of elements of `r` to shuffle (counting from the beginning);
        must be less than `r.length`
Complexity: O(n)
+/
void shuffle(Range, G)(ref G gen, Range range, size_t n)
    if (isSaturatedRandomEngine!G && isRandomAccessRange!Range && hasLength!Range)
{
    import std.algorithm.mutation : swapAt;
    assert(n <= range.length, "n must be <= range.length for shuffle.");
    for (; n; n--, range.popFront)
        range.swapAt(0, gen.randIndex(range.length));
}

///
static if (__VERSION__ >= 2072)
unittest
{
    import std.experimental.ndslice;
    import std.algorithm.sorting;

    auto gen = Random(unpredictableSeed);
    auto a = iotaSlice(10).slice;

    gen.shuffle(a, 4);

    sort(a);
    assert(a == iotaSlice(10));
}
