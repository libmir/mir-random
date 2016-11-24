/**
 * Permuted Congruential Generator (PCG)
 *
 * Implemeted as per the C++ version of PCG. see $(HTTP www.pcg-random.org)
 *
 * Paper available http://www.pcg-random.org/paper.html
 *
 * Author C++: Melissa O'Neill. D translation Nicholas Wilson.
 *
 * PCG Random Number Generation for C++
 *
 * Copyright 2014 Melissa O'Neill <oneill@pcg-random.org>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * For additional information about the PCG random number generation scheme,
 * including its license and other licensing options, visit
 *
 *     http://www.pcg-random.org
 */
module random.engine.pcg;

import random.engine;
import core.bitop;

@safe:
nothrow:
@nogc:

private template default_multiplier(T)
{
    static if (is(T == ubyte))
        enum ubyte default_multiplier = 141u;
    else static if (is(T == ushort))
        enum ushort default_multiplier = 12829u;
    else static if (is(T == uint))
        enum uint default_multiplier = 747796405u;
    else static if (is(T == ulong))
        enum ulong default_multiplier = 6364136223846793005u;
    else static if (is(ucent) && is(T == ucent))
        enum ucent default_multiplier = 0x2360ED051FC65DA44385DF649FCCF645;
    else
        static assert(0);
}

private template default_increment(T)
{
    static if (is(T == ubyte))
        enum ubyte default_increment = 77u;
    else static if (is(T == ushort))
        enum ushort default_increment = 47989u;
    else static if (is(T == uint))
        enum uint default_increment = 2891336453u;
    else static if (is(T == ulong))
        enum ulong default_increment = 1442695040888963407u;
    else static if (is(ucent) && is(T == ucent))
        enum ucent default_increment = 0x5851F42D4C957F2D14057B7EF767814F;
    else
        static assert(0);
}
private template mcg_multiplier(T)
{
    static if (is(T == ubyte))
        enum ubyte mcg_multiplier = 217u;
    else static if (is(T == ushort))
        enum ushort mcg_multiplier = 62169u;
    else static if (is(T == uint))
        enum uint mcg_multiplier = 277803737u;
    else static if (is(T == ulong))
        enum ulong mcg_multiplier = 12605985483714917081u;
    else static if (is(ucent) && is(T == ucent))
        enum ucent mcg_multiplier = 0x6BC8F622C397699CAEF17502108EF2D9;
    else
        static assert(0);
}
private template mcg_unmultiplier(T)
{
    static if (is(T == ubyte))
        enum ubyte mcg_unmultiplier = 105u;
    else static if (is(T == ushort))
        enum ushort mcg_unmultiplier = 28009u;
    else static if (is(T == uint))
        enum uint mcg_unmultiplier = 2897767785u;
    else static if (is(T == ulong))
        enum ulong mcg_unmultiplier = 15009553638781119849u;
    else static if (is(ucent) && is(T == ucent))
        enum ucent mcg_unmultiplier = 0xC827645E182BC965D04CA582ACB86D69;
    else
        static assert(0);
}
mixin template unique_stream(T)
{
    enum is_mcg = false;
    T increment() const
    {
        T this_addr = (() @trusted => cast(T)(*cast(ulong*)&this))();
        return this_addr | 1;
    }
    T stream()
    {
        return increment() >> 1;
    }
    enum can_specify_stream = false;
    enum size_t streams_pow2 = T.sizeof < size_t.sizeof ? T.sizeof :
    size_t.sizeof - 1u;
}
mixin template no_stream(T)
{
    enum is_mcg = true;
    enum increment = 0;
    
    enum can_specify_stream = false;
    enum size_t streams_pow2 = 0;
}
mixin template oneseq_stream(T)
{
    enum is_mcg = false;
    T increment()
    {
        return default_increment!T;
    }
    enum can_specify_stream = false;
    enum size_t streams_pow2 = 0;
}
mixin template specific_stream(T)
{
    enum is_mcg = false;
    T inc_ = default_increment!T;
    T increment() { return inc_; }
    enum can_specify_stream = true;
    void set_stream(T t)
    {
        inc_ = (t << 1) | 1;
    }
    enum size_t streams_pow2 = size_t.sizeof*8 -1u;
}
enum stream_t
{
    unique,
    none,
    oneseq,
    specific
}
/*
 * OUTPUT FUNCTIONS.
 *
 * These are the core of the PCG generation scheme.  They specify how to
 * turn the base LCG's internal state into the output value of the final
 * generator.
 *
 * They're implemented as mixin classes.
 *
 * All of the classes have code that is written to allow it to be applied
 * at *arbitrary* bit sizes, although in practice they'll only be used at
 * standard sizes supported by C++.
 */

/*
 * XSH RS -- high xorshift, followed by a random shift
 *
 * Fast.  A good performer.
 */
O xsh_rs(O,S)(S s)
{
    enum bits        = S.sizeof * 8;
    enum xtypebits   = O.sizeof * 8;
    enum sparebits   = bits - xtypebits;
    enum opbits = sparebits-5 >= 64 ? 5
                : sparebits-4 >= 32 ? 4
                : sparebits-3 >= 16 ? 3
                : sparebits-2 >= 4  ? 2
                : sparebits-1 >= 1  ? 1
                :                     0;
    enum mask           = (1 << opbits) - 1;
    enum maxrandshift   = mask;
    enum topspare       = opbits;
    enum bottomspare    = sparebits - topspare;
    enum xshift         = topspare + (xtypebits+maxrandshift)/2;
    
    auto rshift = opbits ? size_t(s >> (bits - opbits)) & mask : 0;
    s ^= s >> xshift;
    O result = xtype(s >> (bottomspare - maxrandshift + rshift));
    return result;
}
/*
 * XSH RR -- high xorshift, followed by a random rotate
 *
 * Fast.  A good performer.  Slightly better statistically than XSH RS.
 */
O xsh_rr(O,S)(S s)
{
    enum bits        = S.sizeof * 8;
    enum xtypebits   = O.sizeof * 8;
    enum sparebits   = bits - xtypebits;
    enum wantedopbits =   xtypebits >= 128 ? 7
                        : xtypebits >=  64 ? 6
                        : xtypebits >=  32 ? 5
                        : xtypebits >=  16 ? 4
                        :                    3;
    enum opbits = sparebits >= wantedopbits ? wantedopbits : sparebits;
    enum amplifier = wantedopbits - opbits;
    enum mask = (1 << opbits) - 1;
    enum topspare    = opbits;
    enum bottomspare = sparebits - topspare;
    enum xshift      = (topspare + xtypebits)/2;
    
    auto rot = opbits ? size_t(s >> (bits - opbits)) & mask : 0;
    auto amprot = (rot << amplifier) & mask;
    s ^= s >> xshift;
    O result = cast(O)(s >> bottomspare);
    result = ror(result, cast(uint)amprot);
    return result;
}
/*
 * RXS -- random xorshift
 */
O rxs(O,S)(S s)
{
    enum bits        = S.sizeof * 8;
    enum xtypebits   = O.sizeof * 8;
    enum shift       = bits - xtypebits;
    enum extrashift  = (xtypebits - shift)/2;
    size_t rshift = shift > 64+8 ? (s >> (bits - 6)) & 63
                  : shift > 32+4 ? (s >> (bits - 5)) & 31
                  : shift > 16+2 ? (s >> (bits - 4)) & 15
                  : shift >  8+1 ? (s >> (bits - 3)) & 7
                  : shift >  4+1 ? (s >> (bits - 2)) & 3
                  : shift >  2+1 ? (s >> (bits - 1)) & 1
                  : 0;
    s ^= s >> (shift + extrashift - rshift);
    O result = s >> rshift;
    return result;
}
/*
 * RXS M XS -- random xorshift, mcg multiply, fixed xorshift
 *
 * The most statistically powerful generator, but all those steps
 * make it slower than some of the others.  We give it the rottenest jobs.
 *
 * Because it's usually used in contexts where the state type and the
 * result type are the same, it is a permutation and is thus invertable.
 * We thus provide a function to invert it.  This function is used to
 * for the "inside out" generator used by the extended generator.
 */
O rxs_m_xs_foward(O,S)(S s) if(is(O == S))
{
    enum bits        = S.sizeof * 8;
    enum xtypebits   = O.sizeof * 8;
    enum opbits = xtypebits >= 128 ? 6
                : xtypebits >=  64 ? 5
                : xtypebits >=  32 ? 4
                : xtypebits >=  16 ? 3
                :                    2;
    enum shift = bits - xtypebits;
    enum mask = (1 << opbits) - 1;
    size_t rshift = opbits ? bitcount_t(s >> (bits - opbits)) & mask : 0;
    s ^= s >> (opbits + rshift);
    s *= mcg_multiplier!S;
    O result = s >> shift;
    result ^= result >> ((2U*xtypebits+2U)/3U);
    return result;
}
O rxs_m_xs_reverse(O,S)(S s) if(is(O == S))
{
    enum bits        = S.sizeof * 8;
    enum opbits = bits >= 128 ? 6
                : bits >=  64 ? 5
                : bits >=  32 ? 4
                : bits >=  16 ? 3
                :               2;
    enum mask = (1 << opbits) - 1;
    
    s = unxorshift(s, bits, (2U*bits+2U)/3U);
    
    s *= mcg_unmultiplier!S;
    
    auto rshift = opbits ? (s >> (bits - opbits)) & mask : 0;
    s = unxorshift(s, bits, opbits + rshift);
    
    return s;
}
/*
 * XSL RR -- fixed xorshift (to low bits), random rotate
 *
 * Useful for 128-bit types that are split across two CPU registers.
 */
O xsl_rr(O,S)(S s)
{
    enum bits        = S.sizeof * 8;
    enum xtypebits   = O.sizeof * 8;
    enum sparebits = bits - xtypebits;
    enum wantedopbits =   xtypebits >= 128 ? 7
                        : xtypebits >=  64 ? 6
                        : xtypebits >=  32 ? 5
                        : xtypebits >=  16 ? 4
                        :                    3;
    enum opbits = sparebits >= wantedopbits ? wantedopbits : sparebits;
    enum amplifier = wantedopbits - opbits;
    enum mask = (1 << opbits) - 1;
    enum topspare = sparebits;
    enum bottomspare = sparebits - topspare;
    enum xshift = (topspare + xtypebits) / 2;
    
    auto rot = opbits ? size_t(s >> (bits - opbits)) & mask : 0;
    auto amprot = (rot << amplifier) & mask;
    s ^= s >> xshift;
    O result = s >> bottomspare;
    result = rotr(result, amprot);
    return result;
}
private template half_size(T)
{
    static if (is(T == ucent))
        alias half_size = ulong;
    else static if (is(T == ulong))
        alias half_size = uint;
    else static if (is(T == uint))
        alias half_size = ushort;
    else static if (is(T == ushort))
        alias half_size = ubyte;
    else
        static assert(0);
}
O xsl_rr_rr(O,S)(S s) if(is(O == S))
{
    alias H = half_size!S;
    enum htypebits = H.sizeof * 8;
    enum bits      = S.sizeof * 8;
    enum sparebits = bits - htypebits;
    enum wantedopbits =   htypebits >= 128 ? 7
                        : htypebits >=  64 ? 6
                        : htypebits >=  32 ? 5
                        : htypebits >=  16 ? 4
                        :                    3;
    enum opbits = sparebits >= wantedopbits ? wantedopbits : sparebits;
    enum amplifier = wantedopbits - opbits;
    enum mask = (1 << opbits) - 1;
    enum topspare = sparebits;
    enum xshift = (topspare + htypebits) / 2;
    
    auto rot = opbits ? size_t(s >> (bits - opbits)) & mask : 0;
    auto amprot = (rot << amplifier) & mask;
    s ^= s >> xshift;
    H lowbits = cast(H)s;
    lowbits = rotr(lowbits, amprot);
    H highbits = cast(H)(s >> topspare);
    auto rot2 = lowbits & mask;
    auto amprot2 = (rot2 << amplifier) & mask;
    highbits = rotr(highbits, amprot2);
    return (S(highbits) << topspare) ^ S(lowbits);
    
}
O xsh(O,S)(S s) if(S.sizeof > 8)
{
    enum bits        = S.sizeof * 8;
    enum xtypebits   = O.sizeof * 8;
    enum sparebits = bits - xtypebits;
    enum topspare = 0;
    enum bottomspare = sparebits - topspare;
    enum xshift = (topspare + xtypebits) / 2;
    
    s ^= s >> xshift;
    O result = s >> bottomspare;
    return result;
}
O xsl(O,S)(S s) if(S.sizeof > 8)
{
    enum bits        = S.sizeof * 8;
    enum xtypebits   = O.sizeof * 8;
    enum sparebits = bits - xtypebits;
    enum topspare = sparebits;
    enum bottomspare = sparebits - topspare;
    enum xshift = (topspare + xtypebits) / 2;
    
    s ^= s >> xshift;
    O result = s >> bottomspare;
    return result;
}
@RandomEngine
struct PermutedCongruentialEngine(O,                   // The output type
                                  S,                   // The state type
                                  alias output,        // Output function
                                  stream_t stream,     // The stream type
                                  bool output_previous,
                                  S mult = default_multiplier!S)
{
    @disable this(this);
    static if (stream == stream_t.none)
        mixin no_stream!S;
    else static if (stream == stream_t.unique)
        mixin unique_stream!S;
    else static if (stream == stream_t.specific)
        mixin specific_stream!S;
    else static if (stream == stream_t.oneseq)
        mixin oneseq_stream!S;
    else
        static assert(0);
        
    S state;
    
    enum period_pow2 = S.sizeof*8 - 2*is_mcg;
    enum max = O.max;
    
private:
    S bump(S state_)
    {
        return state_ * mult + increment();
    }
    
    S base_generate()
    {
        return state = bump(state);
    }
    
    S base_generate0()
    {
        S old_state = state;
        state = bump(state);
        return old_state;
    }
public:
    static if (!can_specify_stream)
    this(S seed)
    {
        if (is_mcg)
            state = seed | 3u;
        else
            state = bump(seed + increment());
    }
    else
    {
        this(S seed, S stream_ = default_increment!S)
        {
            state = bump(seed + increment());
            set_stream(stream_);
        }
    }
    O opCall()
    {
        static if(output_previous)
            return output(base_generate0());
        else
            return output(base_generate());
    }
    //opCall(O upperbound)
    void popFrontN(S delta)
    {
        // The method used here is based on Brown, "Random Number Generation
        // with Arbitrary Stride,", Transactions of the American Nuclear
        // Society (Nov. 1994).  The algorithm is very similar to fast
        // exponentiation.
        //
        // Even though delta is an unsigned integer, we can pass a
        // signed integer to go backwards, it just goes "the long way round".
        
        S acc_mult, acc_plus;
        S _inc = increment(), _mult = mult;
        while (delta > 0)
        {
            if (delta & 1)
            {
                acc_mult *= _mult;
                acc_plus = acc_plus * _mult + _inc;
            }
            _inc  *= _mult + 1;
            _mult *= _mult;
            delta >>= 1;
        }
        state = acc_mult*state + acc_plus;
    }
}
alias pcg32_unique = PermutedCongruentialEngine!(uint,ulong,
                                                xsh_rr!(uint,ulong),
                                                stream_t.unique,true);
@safe unittest
{
    pcg32_unique gen;
    gen();
}
