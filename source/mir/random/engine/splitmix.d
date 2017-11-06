/++
SplitMix generator family.

An n-bit splitmix PRNG has an internal n-bit counter and an n-bit increment.
The state is advanced by adding the increment to the counter and output is
the counter's value <a href="#fmix64">mixed</a>. The increment remains constant
for an instance over its lifetime, so each instance of the PRNG needs to
explicitly store its increment only if the `split()` operation is needed.

The first version of splitmix was described in
$(LINK2 http://gee.cs.oswego.edu/dl/papers/oopsla14.pdf, Fast Splittable
Pseudorandom Number Generators) (2014) by Guy L. Steele Jr., Doug Lea, and
Christine H. Flood. A key selling point of the generator was the ability
to $(I split) the sequence:

<blockquote>
"A conventional linear PRNG object provides a generate method that returns
one pseudorandom value and updates the state of the PRNG, but a splittable
PRNG object also has a second operation, split, that replaces the original
PRNG object with two (seemingly) independent PRNG objects, by creating and
returning a new such object and updating the state of the original object.
Splittable PRNG objects make it easy to organize the use of pseudorandom
numbers in multithreaded programs structured using fork-join parallelism."
</blockquote>

However, splitmix $(LINK2 http://xoroshiro.di.unimi.it/splitmix64.c,
is also used) as a non-splittable PRNG with a constant increment that
does not vary from one instance to the next. This cuts the needed space
in half. This module provides predefined fixed-increment $(LREF SplitMix64)
and splittable $(LREF Splittable64).
+/
module mir.random.engine.splitmix;
import std.traits: isUnsigned, TemplateArgsOf, TemplateOf, Unqual;

@nogc:
nothrow:
pure:
@safe:

/++
64-bit $(LINK2 https://en.wikipedia.org/wiki/MurmurHash,
MurmurHash3)-style bit mixer, parameterized.

Pattern is:
---
ulong fmix64(ulong x)
{
    x = (x ^ (x >>> shift1)) * m1;
    x = (x ^ (x >>> shift2)) * m2;
    return x ^ (x >>> shift3);
}
---

As long as m1 and m2 are odd each operation is invertible with the consequence
that `fmix64(a) == fmix64(b)` if and only if `(a == b)`.

Good parameters for fmix64 are found empirically. Several sets of
<a href="#.fmix64.2">suggested parameters</a> are provided.
+/
ulong fmix64(ulong m1, ulong m2, uint shift1, uint shift2, uint shift3)(ulong x) @nogc nothrow pure @safe
{
    enum bits = ulong.sizeof * 8;
    //Sets of parameters for this function are selected empirically rather than
    //on the basis of theory. Nevertheless we can identify minimum reasonable
    //conditions. Meeting these conditions does not imply that a set of
    //parameters is suitable, but any sets of parameters that fail to meet
    //these conditions are obviously unsuitable.
    static assert(m1 != 1 && m1 % 2 == 1, "Multiplier must be odd number other than 1!");
    static assert(m2 != 1 && m2 % 2 == 1, "Multiplier must be odd number other than 1!");
    static assert(shift1 > 0 && shift1 < bits, "Shift out of bounds!");
    static assert(shift2 > 0 && shift2 < bits, "Shift out of bounds!");
    static assert(shift3 > 0 && shift3 < bits, "Shift out of bounds!");
    static assert(shift1 + shift2 + shift3 >= bits - 1,
        "Shifts must be sufficient for most significant bit to affect least significant bit!");
    static assert(ulong.max / m1 <= m2,
        "Multipliers must be sufficient for least significant bit to affect most significant bit!");

    pragma(inline, true);
    x = (x ^ (x >>> shift1)) * m1;
    x = (x ^ (x >>> shift2)) * m2;
    return x ^ (x >>> shift3);
}

/++
Well known sets of parameters for <a href="#fmix64">fmix64</a>. Recognized
names are "murmurHash3", and "staffordMix01" through "staffordMix14".

$(LINK https://zimbry.blogspot.com/2011/09/better-bit-mixing-improving-on.html)
+/
template fmix64(string identifier)
{
    static if (identifier == "murmurHash3")
        alias fmix64 = .fmix64!(0xff51afd7ed558ccdUL, 0xc4ceb9fe1a85ec53UL, 33, 33, 33);
    else static if (identifier == "staffordMix01")
        alias fmix64 = .fmix64!(0x7fb5d329728ea185UL, 0x81dadef4bc2dd44dUL, 31, 27, 33);
    else static if (identifier == "staffordMix02")
        alias fmix64 = .fmix64!(0x64dd81482cbd31d7UL, 0xe36aa5c613612997UL, 33, 31, 31);
    else static if (identifier == "staffordMix03")
        alias fmix64 = .fmix64!(0x99bcf6822b23ca35UL, 0x14020a57acced8b7UL, 31, 30, 33);
    else static if (identifier == "staffordMix04")
        alias fmix64 = .fmix64!(0x62a9d9ed799705f5UL, 0xcb24d0a5c88c35b3UL, 33, 28, 32);
    else static if (identifier == "staffordMix05")
        alias fmix64 = .fmix64!(0x79c135c1674b9addUL, 0x54c77c86f6913e45UL, 31, 29, 30);
    else static if (identifier == "staffordMix06")
        alias fmix64 = .fmix64!(0x69b0bc90bd9a8c49UL, 0x3d5e661a2a77868dUL, 31, 27, 30);
    else static if (identifier == "staffordMix07")
        alias fmix64 = .fmix64!(0x16a6ac37883af045UL, 0xcc9c31a4274686a5UL, 30, 26, 32);
    else static if (identifier == "staffordMix08")
        alias fmix64 = .fmix64!(0x294aa62849912f0bUL, 0x0a9ba9c8a5b15117UL, 30, 28, 31);
    else static if (identifier == "staffordMix09")
        alias fmix64 = .fmix64!(0x4cd6944c5cc20b6dUL, 0xfc12c5b19d3259e9UL, 32, 29, 32);
    else static if (identifier == "staffordMix10")
        alias fmix64 = .fmix64!(0xe4c7e495f4c683f5UL, 0xfda871baea35a293UL, 30, 32, 33);
    else static if (identifier == "staffordMix11")
        alias fmix64 = .fmix64!(0x97d461a8b11570d9UL, 0x02271eb7c6c4cd6bUL, 27, 28, 32);
    else static if (identifier == "staffordMix12")
        alias fmix64 = .fmix64!(0x3cd0eb9d47532dfbUL, 0x63660277528772bbUL, 29, 26, 33);
    else static if (identifier == "staffordMix13")
        alias fmix64 = .fmix64!(0xbf58476d1ce4e5b9UL, 0x94d049bb133111ebUL, 30, 27, 31);
    else static if (identifier == "staffordMix14")
        alias fmix64 = .fmix64!(0x4be98134a5976fd3UL, 0x3bc0993a5ad19a13UL, 30, 29, 31);
    else
    {
        private enum e = 0;
        static assert(0, __traits(e, parent).stringof~": no such known fmix64 variant!");
    }
}
///
@nogc nothrow pure @safe version(mir_random_test) unittest
{
    enum ulong x1 = fmix64!"murmurHash3"(0x1234_5678_9abc_defeUL);//Mix some number at compile time.
    static assert(x1 == 0xb194_3cfe_a4f7_8f08UL);

    immutable ulong x2 = fmix64!"murmurHash3"(0x1234_5678_9abc_defeUL);//Mix some number at run time.
    assert(x1 == x2);//Same result.
}
///
@nogc nothrow pure @safe version(mir_random_test) unittest
{
    //Verify all sets of predefined parameters are valid
    //and no two are identical.
    ulong[15] array;
    array[0] = fmix64!"murmurHash3"(1);
    array[1] = fmix64!"staffordMix01"(1);
    array[2] = fmix64!"staffordMix02"(1);
    array[3] = fmix64!"staffordMix03"(1);
    array[4] = fmix64!"staffordMix04"(1);
    array[5] = fmix64!"staffordMix05"(1);
    array[6] = fmix64!"staffordMix06"(1);
    array[7] = fmix64!"staffordMix07"(1);
    array[8] = fmix64!"staffordMix08"(1);
    array[9] = fmix64!"staffordMix09"(1);
    array[10] = fmix64!"staffordMix10"(1);
    array[11] = fmix64!"staffordMix11"(1);
    array[12] = fmix64!"staffordMix12"(1);
    array[13] = fmix64!"staffordMix13"(1);
    array[14] = fmix64!"staffordMix14"(1);
    foreach (i; 1 .. array.length - 1)
        foreach (e; array[0 .. i])
            if (e == array[i])
                assert(0, "fmix64 predefines are not all distinct!");
}

/++
 Canonical fixed increment (non-splittable) SplitMix64 engine.

 64 bits of state, period of `2 ^^ 64`.
 +/
alias SplitMix64 = SplitMixEngine!"staffordMix13";
///
@nogc nothrow pure @safe version(mir_random_test) unittest
{
    import mir.random;
    static assert(isSaturatedRandomEngine!SplitMix64);
    auto rng = SplitMix64(1u);
    ulong x = rng.rand!ulong;
    assert(x == 10451216379200822465UL);
}

/++
 Canonical splittable (specifiable-increment) SplitMix64 engine.

 128 bits of state, period of `2 ^^ 64`.
 +/
alias Splittable64 = SplitMixEngine!("staffordMix13", SPLIT_MIX_SPECIFIABLE_INCREMENT);
///
@nogc nothrow pure @safe version(mir_random_test) unittest
{
    import mir.random;
    static assert(isSaturatedRandomEngine!Splittable64);
    auto rng = Splittable64(1u);
    ulong x = rng.rand!ulong;
    assert(x == 10451216379200822465UL);

    //Split example:
    auto rng1 = Splittable64(1u);
    auto rng2 = rng1.split();

    assert(rng1.rand!ulong == 17911839290282890590UL);
    assert(rng2.rand!ulong == 14201552918486545593UL);
    assert(rng1.increment != rng2.increment);
}


/// Flags used in optional argument of $(LREF SplitMixEngine).
enum SPLIT_MIX_SPECIFIABLE_INCREMENT = 1;
/// ditto
enum SPLIT_MIX_OUTPUT_PREVIOUS = 2;

/++
Default increment used by $(LREF SplitMixEngine).
Defined in $(LINK2 http://gee.cs.oswego.edu/dl/papers/oopsla14.pdf,
Fast Splittable Pseudorandom Number Generators) as "the odd integer
closest to (2 ^^ 64)/φ, where φ = (1 + √5)/2 is the
$(LINK2 https://en.wikipedia.org/wiki/Golden_ratio, golden ratio)."
+/
enum ulong DEFAULT_SPLITMIX_INCREMENT = 0x9e3779b97f4a7c15UL;

/++
Generic SplitMixEngine.

The first argument mixer can be a name like "murmurHash3" or "staffordMix13"
that <a href="#.fmix64.2">fmix64!(string)</a> accepts as a template parameter,
or it can be an explicitly instantiated <a href="#fmix64">fmix64!(ulong, ulong,
uint, uint, uint)</a>. The ability to specify the name directly is so the
string will appear in the engine's human-readable name.

The first optional argument is an optional `flags` bitfield. Accepted flags are:

$(TABLE
    $(TR $(TH Flag) $(TH Description))

    $(TR $(TD $(LREF SPLIT_MIX_SPECIFIABLE_INCREMENT))
    $(TD Allows each instance to have a distinct increment, enabling the
    `split()` operation at the cost of increasing the size from 64 bits
    to 128 bits.))

    $(TR $(TD $(LREF SPLIT_MIX_OUTPUT_PREVIOUS))
    $(TD Aakes this engine also a
    $(LINK2 https://dlang.org/phobos/std_random.html#.isUniformRNG,
    Phobos-style uniform RNG) at no additional size cost but possibly
    making `opCall()` slightly less efficient.))
)

The second optional argument is a `default_increment` to be used as an
alternative to $(LREF DEFAULT_SPLITMIX_INCREMENT). For a SplitMixEngine with
a fixed seed the default increment is used by all instances.
+/
struct SplitMixEngine(alias mixer, OptionalArgs...)
    if ((is(typeof(mixer == "staffordMix13"))
            || __traits(compiles, {static assert(__traits(isSame, TemplateOf!mixer, fmix64));}))
        && OptionalArgs.length <= 2
        && (OptionalArgs.length < 1 || (is(typeof(OptionalArgs[0]) : ulong) && OptionalArgs[0] <= (SPLIT_MIX_SPECIFIABLE_INCREMENT | SPLIT_MIX_OUTPUT_PREVIOUS)))
        && (OptionalArgs.length < 2 || (is(typeof(OptionalArgs[1]) == ulong) && OptionalArgs[1] != DEFAULT_SPLITMIX_INCREMENT))
        && (OptionalArgs.length != 1 || OptionalArgs[0] != 0))
{
    @nogc:
    nothrow:
    pure:
    @safe:

    static if (is(typeof(mixer == "staffordMix13")))
        alias fmix64 = .fmix64!mixer;
    else
        alias fmix64 = .fmix64!(TemplateArgsOf!mixer);

    static if (OptionalArgs.length >= 2)
        enum ulong default_increment = OptionalArgs[1];
    else
        enum ulong default_increment = DEFAULT_SPLITMIX_INCREMENT;

    static if (OptionalArgs.length >= 1)
        private enum flags = OptionalArgs[0];
    else
        private enum flags = 0;

    static assert(default_increment % 2 != 0, "Increment must be an odd number!");

    /// Marks as a Mir random engine.
    enum bool isRandomEngine = true;
    /// Largest generated value.
    enum ulong max = ulong.max;

    /// Full period (2 ^^ 64).
    enum uint period_pow2 = 64;

    /// True when `0 != (SPLIT_MIX_OUTPUT_PREVIOUS & flags)`
    enum bool output_previous = 0 != (SPLIT_MIX_OUTPUT_PREVIOUS & flags);

    /// True when `0 != (SPLIT_MIX_SPECIFIABLE_INCREMENT & flags)`
    enum bool increment_specifiable = 0 != (SPLIT_MIX_SPECIFIABLE_INCREMENT & flags);

    /// Current internal state of the generator.
    public ulong state;

    static if (increment_specifiable)
    {
        /++
        Either an enum or a settable value depending on whether `output_previous == true`.
        gamma should always be odd.
        +/
        ulong increment = default_increment;
    }
    else
    {
        /// ditto
        enum ulong increment = default_increment;
    }

    @disable this();
    @disable this(this);

    /++
     +Constructs a $(D XorshiftEngine) generator seeded with $(D_PARAM x0).
     +/
    this()(ulong x0)
    {
        static if (increment_specifiable)
            increment = default_increment;
        static if (output_previous)
            this.state = x0 + increment;
        else
            this.state = x0;
    }

    /// ditto
    this()(ulong x0, ulong increment) if (increment_specifiable)
    {
        this.increment = increment | 1UL;
        static if (output_previous)
            this.state = x0 + increment;
        else
            this.state = x0;
    }

    /// Advances the random sequence.
    ulong opCall()()
    {
        static if (output_previous)
        {
            auto result = fmix64(state);
            state += increment;
            return result;
        }
        else
        {
            return fmix64(state += increment);
        }
    }

    static if (increment_specifiable)
    {
        /++
        Produces a splitmix generator with a different counter-value
        and increment-value than the current generator. Only available
        when <a href="#.SplitMixEngine.increment_specifiable">
        `increment_specifiable == true`</a>.
        +/
        typeof(this) split()()
        {
            immutable state1 = opCall();
            static if (output_previous)
            {
                auto gamma1 = state;
                state += increment;
            }
            else
                auto gamma1 = state += increment;
            //Use a different mix function for the increment.
            static if (fmix64(1) == .fmix64!"staffordMix13"(1))
                gamma1 = fmix64!"murmurHash3"(gamma1);
            else
                gamma1 = fmix64!"staffordMix13"(gamma);
            gamma1 |= 1UL;//Ensure increment is odd.
            import core.bitop: popcnt;
            if (popcnt(gamma1 ^ (gamma1 >>> 1)) < 24)
                gamma1 ^= 0xaaaa_aaaa_aaaa_aaaaUL;
            return typeof(this)(state1, gamma1);
        }
    }

    /++
    Skip forward in the random sequence in $(BIGOH 1) time.
    +/
    void skip()(size_t n)
    {
        state += n * increment;
    }

    static if (output_previous)
    {
        /++
        Compatibility with $(LINK2 https://dlang.org/phobos/std_random.html#.isUniformRNG,
        Phobos library methods). Presents this RNG as an InputRange.
        Only available if `output_previous == true`.

        The reason that this is enabled when <a href="#.SplitMixEngine.output_previous">
        `output_previous == true`</a> is because
        `front` can be implemented without additional cost.
        +/
        enum bool isUniformRandom = true;
        /// ditto
        enum ulong min = ulong.min;
        /// ditto
        enum bool empty = false;
        /// ditto
        @property ulong front()() const { return fmix64(state); }
        /// ditto
        void popFront()() { state += increment; }
        /// ditto
        void seed()(ulong x0)
        {
            this.__ctor(x0);
        }
        /// ditto
        void seed()(ulong x0, ulong increment) if (increment_specifiable)
        {
            this.__ctor(x0, increment);
        }
        /// ditto
        @property typeof(this) save()() const
        {
            static if (increment_specifiable)
                return typeof(this)(state - increment, increment);
            else
                return typeof(this)(state - increment);
        }
        /// ditto
        ulong opIndex()(size_t n) const
        {
            return fmix64(state + n * increment);
        }
        /// ditto
        size_t popFrontN()(size_t n)
        {
            skip(n);
            return n;
        }
        /// ditto
        alias popFrontExactly() = skip;
    }
}
///
@nogc nothrow pure @safe version(mir_random_test) unittest
{
    //Can specify engine like this:
    alias RNG1 = SplitMixEngine!"staffordMix13";
    alias RNG2 = SplitMixEngine!(fmix64!("staffordMix13"));
    alias RNG3 = SplitMixEngine!(fmix64!(0xbf58476d1ce4e5b9UL, 0x94d049bb133111ebUL, 30, 27, 31));

    //Each way of writing it results in the same sequence.
    assert(RNG1(1).opCall() == RNG2(1).opCall());
    assert(RNG2(1).opCall() == RNG3(1).opCall());

    //However not each result's name is equally informative.
    static assert(RNG1.stringof == `SplitMixEngine!"staffordMix13"`);
    static assert(RNG2.stringof == `SplitMixEngine!(fmix64)`);//Doesn't include parameters!
    static assert(RNG2.stringof == `SplitMixEngine!(fmix64)`);//Doesn't include parameters!
}
///
@nogc nothrow pure @safe version(mir_random_test) unittest
{
    import mir.random;
    import std.range.primitives: isRandomAccessRange;
    // With `output_previous == true`, should be both a Mir-style saturated
    // random engine and a Phobos-style uniform RNG.
    alias RNG = SplitMixEngine!("staffordMix13", SPLIT_MIX_OUTPUT_PREVIOUS);
    static assert(RNG.output_previous);
    static assert(isPhobosUniformRNG!RNG);
    static assert(isSaturatedRandomEngine!RNG);
    static assert(isRandomAccessRange!RNG);

    auto a = RNG(1);
    immutable ulong x = a.front;
    auto b = a.save;
    assert (x == a.front);
    assert (x == b.front);
    assert (x == a[0]);

    immutable ulong y = a[1];
    assert(x == a());
    assert(x == b());
    assert(a.front == y);
}

@nogc nothrow pure @safe version(mir_random_test) unittest
{
    alias RNG = SplitMixEngine!("staffordMix13", SPLIT_MIX_OUTPUT_PREVIOUS);
    auto a = RNG(1);
    a.popFrontExactly(1);
}
