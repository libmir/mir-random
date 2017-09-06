/++
$(SCRIPT inhibitQuickIndex = 1;)

$(BOOKTABLE $(H2 Utilities),

    $(TR $(TH Name), $(TH Description))
    $(T2 RandomVariable, Attribute)
    $(T2 isRandomVariable, Trait)
)

$(BOOKTABLE $(H2 Multidimensional Random Variables),

    $(TR $(TH Generator name) $(TH Description))
    $(RVAR Sphere, Uniform distribution on a unit-sphere)
    $(RVAR Simplex, Uniform distribution on a standard-simplex)
    $(RVAR Dirichlet, $(WIKI_D Dirichlet))
)

Authors: Simon Bürger
Copyright: Copyright, Simon Bürger, 2017-.
License:    $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).

Macros:
    WIKI_D = $(HTTP en.wikipedia.org/wiki/$1_distribution, $1 random variable)
    WIKI_D2 = $(HTTP en.wikipedia.org/wiki/$1_distribution, $2 random variable)
    T2=$(TR $(TDNW $(LREF $1)) $(TD $+))
    RVAR = $(TR $(TDNW $(LREF $1Variable)) $(TD $+))
+/
module mir.random.ndvariable;

import mir.random;
import mir.random.variable;
import std.traits;

import mir.math.common;
import mir.math.sum;
import mir.ndslice;

/++
$(Uniform distribution on a sphere).
Returns: `X ~ 1` with `X[0]^^2 + .. + X[$-1]^^2 = 1`
+/
struct SphereVariable(T)
    if (isFloatingPoint!T)
{
    ///
    enum isRandomVariable = true;

    private size_t dim;
    private NormalVariable!T norm;

    /++
    Params:
        dim = dimension of the sphere
    +/
    this(size_t dim)
    {
        this.dim = dim;
    }

    ///
    void opCall(G)(ref G gen, T[] result)
    {
        assert(result.length == dim + 1);
        opCall(gen, result.sliced);
    }

    ///
    void opCall(G, SliceKind kind, Iterator)(ref G gen, Slice!(kind, [1], Iterator) result)
        if (isSaturatedRandomEngine!G)
    {
        assert(result.length == dim + 1);
        for(size_t i = 0; i <= dim; ++i)
            result[i] = norm(gen);
        result[] /= result.map!"a*a".sum!"kbn".sqrt;
    }
}

/// Generate random points on a circle
unittest
{
    auto gen = Random(unpredictableSeed);
    auto rv = SphereVariable!double(1); // dimension of circle is 1
    double[2] x; // even though a point is described by 2 numbers
    rv(gen, x);
    assert(fabs(x[0]*x[0] + x[1]*x[1] - 1) < 1e-10);
}

/++
$(Uniform distribution on a sphere).
Returns: `X ~ 1` with `X[i] >= 0` and `X[0] + .. + X[$-1] = 1`
+/
struct SimplexVariable(T)
    if (isFloatingPoint!T)
{
    ///
    enum isRandomVariable = true;

    import mir.ndslice.sorting;
    private size_t dim;

    /++
    Params:
        dim = dimension of the simplex
    +/
    this(size_t dim)
    {
        this.dim = dim;
    }

    ///
    void opCall(G)(ref G gen, T[] result)
    {
        assert(result.length == dim + 1);
        opCall(gen, result.sliced);
    }

    ///
    void opCall(G, SliceKind kind, Iterator)(ref G gen, Slice!(kind, [1], Iterator) result)
        if (isSaturatedRandomEngine!G)
    {
        assert(result.length == dim + 1);

        for(size_t i = 0; i < dim; ++i)
            result[i] = gen.rand!T.fabs;
        result[dim] = T(1);

        sort(result[]);
        for(size_t i = dim; i > 0; --i)
            result[i] = result[i] - result[i-1];
    }
}

///
unittest
{
    auto gen = Random(unpredictableSeed);
    auto rv = SimplexVariable!double(2);
    double[3] x;
    rv(gen, x);
    assert(x[0] >= 0 && x[1] >= 0 && x[2] >= 0);
    assert(fabs(x[0] + x[1] + x[2] - 1) < 1e-10);
}

/++
$(Dirichlet distribution).
+/
struct DirichletVariable(T, AlphaParams = const(T)[])
    if (isFloatingPoint!T)
{
    ///
    enum isRandomVariable = true;

    private size_t dim;
    private AlphaParams alpha;

    /++
    Params:
        alpha = (array of) concentration parameters
    Constraints: `alpha[i] > 0`
    +/
    this(AlphaParams alpha)
    {
        assert(alpha.length >= 1);
        for(size_t i = 0; i < alpha.length; ++i)
            assert(alpha[i] > T(0));

        this.dim = alpha.length - 1;
        this.alpha = alpha;
    }

    ///
    void opCall(G)(ref G gen, T[] result)
    {
        assert(result.length == dim + 1);
        opCall(gen, result.sliced);
    }

    ///
    void opCall(G, SliceKind kind, Iterator)(ref G gen, Slice!(kind, [1], Iterator) result)
        if (isSaturatedRandomEngine!G)
    {
        assert(result.length == dim + 1);
        for(size_t i = 0; i < result.length; ++i)
            result[i] = GammaVariable!T(alpha[i])(gen);
        result[] /= result.sum!"kbn";
    }
}

///
unittest
{
    auto gen = Random(unpredictableSeed);
    auto rv = DirichletVariable!double([1.0, 5.7, 0.3]);
    double[3] x;
    rv(gen, x);
    assert(x[0] >= 0 && x[1] >= 0 && x[2] >= 0);
    assert(fabs(x[0] + x[1] + x[2] - 1) < 1e-10);
}
