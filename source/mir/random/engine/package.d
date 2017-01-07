/++
Uniform random engines.

Copyright: Ilya Yaroshenko 2016-.
License:  $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Ilya Yaroshenko
+/
module mir.random.engine;

version (OSX)
    version = Darwin;
else version (iOS)
    version = Darwin;
else version (TVOS)
    version = Darwin;
else version (WatchOS)
    version = Darwin;

import std.traits;

import mir.random.engine.mersenne_twister;

/++
Test if T is a random engine.
A type should define `enum isRandomEngine = true;` to be a random engine.
+/
template isRandomEngine(T)
{
    static if (is(typeof(T.isRandomEngine) : bool) && is(typeof(T.init())))
    {
        private alias R = typeof(T.init());
        static if (T.isRandomEngine && isUnsigned!R)
            enum isRandomEngine = is(typeof({
                enum max = T.max;
                static assert(is(typeof(T.max) == R));
                }));
        else enum isRandomEngine = false;
    }
    else enum isRandomEngine = false;
}

/++
Test if T is a saturated random-bit generator.
A random number generator is saturated if `T.max == ReturnType!T.max`.
A type should define `enum isRandomEngine = true;` to be a random engine.
+/
template isSaturatedRandomEngine(T)
{
    static if (isRandomEngine!T)
        enum isSaturatedRandomEngine = T.max == ReturnType!T.max;
    else
        enum isSaturatedRandomEngine = false;
}

version(Darwin)
private
extern(C) nothrow @nogc
ulong mach_absolute_time();

/**
A "good" seed for initializing random number engines. Initializing
with $(D_PARAM unpredictableSeed) makes engines generate different
random number sequences every run.

Returns:
A single unsigned integer seed value, different on each successive call
*/
pragma(inline, true)
@property size_t unpredictableSeed() @trusted nothrow @nogc
{
    size_t seed;
    //getRandomBlocking(&seed, seed.sizeof);
    seed = 1;
    return seed;
}

///
@safe unittest
{
    auto rnd = Random(unpredictableSeed);
    auto n = rnd();
    static assert(is(typeof(n) == size_t));
}

/++
The "default", "favorite", "suggested" random number generator type on
the current platform. It is an alias for one of the
generators. You may want to use it if (1) you need to generate some
nice random numbers, and (2) you don't care for the minutiae of the
method being used.
+/
static if (is(size_t == uint))
    alias Random = Mt19937_32;
else
    alias Random = Mt19937_64;

///
unittest
{
    import std.traits;
    static assert(isSaturatedRandomEngine!Random);
    static assert(is(ReturnType!Random == size_t));
}

version(linux)
{
    private enum GET_RANDOM {
        UNINTIALIZED,
        NOT_AVAILABLE,
        AVAILABLE,
    }

    // getrandom was introduced in 3.17
    private static GET_RANDOM hasGetRandom = GET_RANDOM.UNINTIALIZED;

    import core.sys.posix.sys.utsname : utsname;

    // druntime isn't properly annotated
    extern(C) int uname(utsname* __name) @nogc nothrow;

    // checks whether the Linux kernel supports getRandom by looking at the
    // reported version
    private auto initHasGetRandom() @nogc @trusted nothrow
    {
        import core.stdc.string : strtok;
        import core.stdc.stdlib : atoi;

        utsname uts;
        uname(&uts);
        char* p = uts.release.ptr;

        // poor man's version check
        auto token = strtok(p, ".");
        int major = atoi(token);
        if (major  > 3)
            return true;

        if (major == 3)
        {
            token = strtok(p, ".");
            if (atoi(token) >= 17)
                return true;
        }

        return false;
    }

    extern(C) int syscall(size_t ident, size_t n, size_t arg1, size_t arg2) @nogc nothrow;

    /*
     * Flags for getrandom(2)
     *
     * GRND_NONBLOCK    Don't block and return EAGAIN instead
     * GRND_RANDOM      Use the /dev/random pool instead of /dev/urandom
     */
    private enum GRND_NONBLOCK = 0x0001;
    private enum GRND_RANDOM = 0x0002;

    version (X86_64)
        private enum GETRANDOM = 318;
    version (X86)
        private enum GETRANDOM = 355;

    /*
        http://man7.org/linux/man-pages/man2/getrandom.2.html
        If the urandom source has been initialized, reads of up to 256 bytes
        will always return as many bytes as requested and will not be
        interrupted by signals.  No such guarantees apply for larger buffer
        sizes.
    */
    private ptrdiff_t getRandomImplSysBlocking(void* ptr, size_t len) @nogc @trusted nothrow
    {
        auto genBytes = 0;
        while (genBytes < len)
        {
            auto res = syscall(GETRANDOM, cast(size_t) ptr + genBytes, len - genBytes, 0);
            if (res >= 0)
                genBytes -= res;
            else
                return res;
        }
        return 0;
    }

    /*
    *   If the GRND_NONBLOCK flag is set, then
    *   getrandom() does not block in these cases, but instead
    *   immediately returns -1 with errno set to EAGAIN.
    */
    private ptrdiff_t getRandomImplSysNonBlocking(void* ptr, size_t len) @nogc @trusted nothrow
    {
        return syscall(GETRANDOM, cast(size_t) ptr, len, GRND_NONBLOCK);
    }
}

version(Posix)
{
    import core.stdc.stdio : fclose, feof, ferror, fopen, fread;
    alias IOType = typeof(fopen("a", "b"));
    static private IOType fdRandom;
    static private IOType fdURandom;

    shared static ~this()
    {
        if (fdRandom !is null)
            fdRandom.fclose;

        if (fdURandom !is null)
            fdURandom.fclose;
    }

    /* The /dev/random device is a legacy interface which dates back to a
       time where the cryptographic primitives used in the implementation of
       /dev/urandom were not widely trusted.  It will return random bytes
       only within the estimated number of bits of fresh noise in the
       entropy pool, blocking if necessary.  /dev/random is suitable for
       applications that need high quality randomness, and can afford
       indeterminate delays.

       When the entropy pool is empty, reads from /dev/random will block
       until additional environmental noise is gathered.
    */
    private ptrdiff_t getRandomImplFileBlocking(void* ptr, size_t len) @nogc @trusted nothrow
    {
        if (fdRandom is null)
        {
            fdRandom = fopen("/dev/random", "r");
            if (fdRandom is null)
                return -1;
        }

        auto genBytes = 0;
        while (genBytes < len)
        {
            genBytes -= fread(ptr + genBytes, 1, len - genBytes, fdRandom);
            // check for possible permanent errors
            if (genBytes > 0)
            {
                if (fdRandom.ferror)
                    return -1;

                if (fdRandom.feof)
                    return -1;
            }
        }

        return 0;
    }

    /**
       When read, the /dev/urandom device returns random bytes using a
       pseudorandom number generator seeded from the entropy pool.  Reads
       from this device do not block (i.e., the CPU is not yielded), but can
       incur an appreciable delay when requesting large amounts of data.
       When read during early boot time, /dev/urandom may return data prior
       to the entropy pool being initialized.
    */
    private ptrdiff_t getRandomImplFileNonBlocking(void* ptr, size_t len) @nogc @trusted nothrow
    {
        if (fdURandom is null)
        {
            fdURandom = fopen("/dev/urandom", "r");
            if (fdURandom is null)
                return -1;
        }

        auto res = fread(ptr, 1, len, fdURandom);
        // check for possible errors
        if (res == 0)
        {
            if (fdURandom.ferror)
                return -1;

            if (fdURandom.feof)
                return -1;
        }
        return res;
    }
}

version(Windows)
{
    // the wincrypt headers in druntime are broken for x64!
    private alias ULONG_PTR = size_t; // uint in druntime
    private alias BOOL = bool;
    private alias DWORD = size_t; // uint in druntime
    private alias LPCWSTR = wchar*;
    private alias PBYTE = ubyte*;
    private alias HCRYPTPROV = ULONG_PTR;
    private alias LPCSTR = const(char)*;

    extern(Windows) BOOL CryptGenRandom(HCRYPTPROV, DWORD, PBYTE) @nogc @safe nothrow;
    extern(Windows) BOOL CryptAcquireContextA(HCRYPTPROV*, LPCSTR, LPCSTR, DWORD, DWORD) @nogc nothrow;
    extern(Windows) BOOL CryptAcquireContextW(HCRYPTPROV*, LPCWSTR, LPCWSTR, DWORD, DWORD) @nogc nothrow;
    extern(Windows) BOOL CryptReleaseContext(HCRYPTPROV, ULONG_PTR) @nogc nothrow;

    private static ULONG_PTR hProvider;

    private auto initGetRandom() @nogc @trusted nothrow
    {
        import core.sys.windows.winbase : GetLastError;
        import core.sys.windows.winerror : NTE_BAD_KEYSET;
        import core.sys.windows.wincrypt : PROV_RSA_FULL, CRYPT_NEWKEYSET, CRYPT_VERIFYCONTEXT, CRYPT_SILENT;

        // https://msdn.microsoft.com/en-us/library/windows/desktop/aa379886(v=vs.85).aspx
        // For performance reasons, we recommend that you set the pszContainer
        // parameter to NULL and the dwFlags parameter to CRYPT_VERIFYCONTEXT
        // in all situations where you do not require a persisted key.
        // CRYPT_SILENT is intended for use with applications for which the UI cannot be displayed by the CSP.
        if (!CryptAcquireContextW(&hProvider, null, null, PROV_RSA_FULL, CRYPT_VERIFYCONTEXT | CRYPT_SILENT))
        {
            if (GetLastError() == NTE_BAD_KEYSET)
            {
                // Attempt to create default container
                if (!CryptAcquireContextA(&hProvider, null, null, PROV_RSA_FULL, CRYPT_NEWKEYSET | CRYPT_SILENT))
                    return 1;
            }
            else
            {
                return 1;
            }
        }

        return 0;
    }

    shared static ~this()
    {
        if (hProvider > 0)
            CryptReleaseContext(hProvider, 0);
    }
}

/**
Fills a buffer with random data.
If not enough entropy has been gathered, it will block.

Params:
    ptr = pointer to the buffer to fill
    len = length of the buffer (in bytes)

Returns:
    A non-zero integer if an error occurred.
*/
extern(C) ptrdiff_t getRandomBlocking(void* ptr , size_t len) @nogc @safe nothrow
{
    version(Windows)
    {
        if (hProvider == 0)
            if (initGetRandom != 0)
                return -1;

        while(!CryptGenRandom(hProvider, len, cast(PBYTE) ptr)) {}
        return 0;
    }
    else
    {
        version(linux)
        with(GET_RANDOM)
        {
            if (hasGetRandom == UNINTIALIZED)
                hasGetRandom = initHasGetRandom ? AVAILABLE : NOT_AVAILABLE;

            // Linux >= 3.17 has getRandom
            if (hasGetRandom == AVAILABLE)
                return getRandomImplSysBlocking(ptr, len);
            else
                return getRandomImplFileBlocking(ptr, len);
        }
        else
        {
            return getRandomImplFileBlocking(ptr, len);
        }
    }
}

///
@safe nothrow unittest
{
    ubyte[] buf = new ubyte[10];
    getRandomBlocking(&buf[0], buf.length);

    import std.algorithm.iteration : sum;
    assert(buf.sum > 0, "Only zero points generated");
}

@nogc nothrow unittest
{
    ubyte[10] buf;
    getRandomBlocking(buf.ptr, buf.length);

    int sum;
    foreach (b; buf)
        sum += b;

    assert(sum > 0, "Only zero points generated");
}

/**
Fills a buffer with random data.
If not enough entropy has been gathered, it won't block.
Hence the error code should be inspected.

On Linux >= 3.17 getRandomNonBlocking is guaranteed to succeed for 256 bytes and
less.

Params:
    buffer = the buffer to fill
    len = length of the buffer (in bytes)

Returns:
    The number of bytes filled - a negative number of an error occurred
*/
extern(C) size_t getRandomNonBlocking(void* ptr, size_t len) @nogc @safe nothrow
{
    version(Windows)
    {
        if (hProvider == 0)
            if (initGetRandom != 0)
                return -1;

        if (!CryptGenRandom(hProvider, len, cast(PBYTE) ptr))
            return -1;
        return len;
    }
    else
    {
        version(linux)
        with(GET_RANDOM)
        {
            if (hasGetRandom == UNINTIALIZED)
                hasGetRandom = initHasGetRandom ? AVAILABLE : NOT_AVAILABLE;

            // Linux >= 3.17 has getRandom
            if (hasGetRandom == AVAILABLE)
                return getRandomImplSysNonBlocking(ptr, len);
            else
                return getRandomImplFileNonBlocking(ptr, len);
        }
        else
        {
            return getRandomImplFileNonBlocking(ptr, len);
        }
    }
}

///
@safe nothrow unittest
{
    ubyte[] buf = new ubyte[10];
    getRandomNonBlocking(&buf[0], buf.length);

    import std.algorithm.iteration : sum;
    assert(buf.sum > 0, "Only zero points generated");
}

@nogc nothrow unittest
{
    ubyte[10] buf;
    getRandomNonBlocking(buf.ptr, buf.length);

    int sum;
    foreach (b; buf)
        sum += b;

    assert(sum > 0, "Only zero points generated");
}
