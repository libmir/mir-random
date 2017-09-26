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
    // fallback to old time/thread-based implementation in case of errors
    if (genRandomBlocking(&seed, seed.sizeof) < 0)
    {
        version(Windows)
        {
            import core.sys.windows.winbase : QueryPerformanceCounter;
            ulong ticks = void;
            QueryPerformanceCounter(cast(long*)&ticks);
        }
        else
        version(Darwin)
        {
            import core.time : mach_absolute_time;
            ulong ticks = mach_absolute_time();
        }
        else
        version(Posix)
        {
            import core.sys.posix.time : clock_gettime, CLOCK_MONOTONIC, timespec;
            timespec ts;
            if(clock_gettime(CLOCK_MONOTONIC, &ts) != 0)
            {
                import core.internal.abort : abort;
                abort("Call to clock_gettime failed.");
            }
            ulong ticks = (cast(ulong) ts.tv_sec << 32) ^ ts.tv_nsec;
        }
        version(Posix)
        {
            import core.sys.posix.unistd : getpid;
            import core.sys.posix.pthread : pthread_self;
            auto pid = cast(uint) getpid;
            auto tid = cast(uint) pthread_self();
        }
        else
        version(Windows)
        {
            import core.sys.windows.winbase : GetCurrentProcessId, GetCurrentThreadId;
            auto pid = cast(uint) GetCurrentProcessId;
            auto tid = cast(uint) GetCurrentThreadId;
        }
        ulong k = ((cast(ulong)pid << 32) ^ tid) + ticks;
        k ^= k >> 33;
        k *= 0xff51afd7ed558ccd;
        k ^= k >> 33;
        k *= 0xc4ceb9fe1a85ec53;
        k ^= k >> 33;
        return cast(size_t)k;
    }
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
    alias Random = Mt19937;
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

    // getrandom was introduced in Linux 3.17
    private __gshared GET_RANDOM hasGetRandom = GET_RANDOM.UNINTIALIZED;

    import core.sys.posix.sys.utsname : utsname;

    // druntime isn't properly annotated
    private extern(C) int uname(utsname* __name) @nogc nothrow;

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

    private extern(C) int syscall(size_t ident, size_t n, size_t arg1, size_t arg2) @nogc nothrow;

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
    private ptrdiff_t genRandomImplSysBlocking(void* ptr, size_t len) @nogc @trusted nothrow
    {
        while (len > 0)
        {
            auto res = syscall(GETRANDOM, cast(size_t) ptr, len, 0);
            if (res >= 0)
            {
                len -= res;
                ptr += res;
            }
            else
            {
                return res;
            }
        }
        return 0;
    }

    /*
    *   If the GRND_NONBLOCK flag is set, then
    *   getrandom() does not block in these cases, but instead
    *   immediately returns -1 with errno set to EAGAIN.
    */
    private ptrdiff_t genRandomImplSysNonBlocking(void* ptr, size_t len) @nogc @trusted nothrow
    {
        return syscall(GETRANDOM, cast(size_t) ptr, len, GRND_NONBLOCK);
    }
}

version(Posix)
{
    import core.stdc.stdio : fclose, feof, ferror, fopen, fread;
    alias IOType = typeof(fopen("a", "b"));
    private __gshared IOType fdRandom;
    private __gshared IOType fdURandom;

    ///
    extern(C) shared static ~this()
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
    private ptrdiff_t genRandomImplFileBlocking(void* ptr, size_t len) @nogc @trusted nothrow
    {
        if (fdRandom is null)
        {
            fdRandom = fopen("/dev/random", "r");
            if (fdRandom is null)
                return -1;
        }

        while (len > 0)
        {
            auto res = fread(ptr, 1, len, fdRandom);
            len -= res;
            ptr += res;
            // check for possible permanent errors
            if (len != 0)
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
    private ptrdiff_t genRandomImplFileNonBlocking(void* ptr, size_t len) @nogc @trusted nothrow
    {
        if (fdURandom is null)
        {
            fdURandom = fopen("/dev/urandom", "r");
            if (fdURandom is null)
                return -1;
        }

        auto res = fread(ptr, 1, len, fdURandom);
        // check for possible errors
        if (res != len)
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

    private extern(Windows) BOOL CryptGenRandom(HCRYPTPROV, DWORD, PBYTE) @nogc @safe nothrow;
    private extern(Windows) BOOL CryptAcquireContextA(HCRYPTPROV*, LPCSTR, LPCSTR, DWORD, DWORD) @nogc nothrow;
    private extern(Windows) BOOL CryptAcquireContextW(HCRYPTPROV*, LPCWSTR, LPCWSTR, DWORD, DWORD) @nogc nothrow;
    private extern(Windows) BOOL CryptReleaseContext(HCRYPTPROV, ULONG_PTR) @nogc nothrow;

    private __gshared ULONG_PTR hProvider;

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

    ///
    extern(C) shared static ~this()
    {
        if (hProvider > 0)
            CryptReleaseContext(hProvider, 0);
    }
}

/**
Initialize the mir random engines.
This constructor needs to be called once $(I before)
other calls in `mir.random.engine`.
*/
extern(C) void mir_random_engine_ctor()
{
    version(Windows)
    {
        if (hProvider == 0)
            initGetRandom;
    }

    version(linux)
    with(GET_RANDOM)
    {
        if (hasGetRandom == UNINTIALIZED)
            hasGetRandom = initHasGetRandom ? AVAILABLE : NOT_AVAILABLE;
    }

}

// automatically calls the extern(C) module initializer
extern(C) shared static this()
{
    mir_random_engine_ctor();
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
extern(C) ptrdiff_t mir_random_genRandomBlocking(void* ptr , size_t len) @nogc @trusted nothrow
{
    version(Windows)
    {
        while(!CryptGenRandom(hProvider, len, cast(PBYTE) ptr)) {}
        return 0;
    }
    else
    {
        version(linux)
        with(GET_RANDOM)
        {
            // Linux >= 3.17 has getRandom
            if (hasGetRandom == AVAILABLE)
                return genRandomImplSysBlocking(ptr, len);
            else
                return genRandomImplFileBlocking(ptr, len);
        }
        else
        {
            return genRandomImplFileBlocking(ptr, len);
        }
    }
}

/// ditto
alias genRandomBlocking = mir_random_genRandomBlocking;

///
@safe nothrow unittest
{
    ubyte[] buf = new ubyte[10];
    genRandomBlocking(&buf[0], buf.length);

    import std.algorithm.iteration : sum;
    assert(buf.sum > 0, "Only zero points generated");
}

@nogc nothrow unittest
{
    ubyte[10] buf;
    genRandomBlocking(buf.ptr, buf.length);

    int sum;
    foreach (b; buf)
        sum += b;

    assert(sum > 0, "Only zero points generated");
}

/**
Fills a buffer with random data.
If not enough entropy has been gathered, it won't block.
Hence the error code should be inspected.

On Linux >= 3.17 genRandomNonBlocking is guaranteed to succeed for 256 bytes and
less.

Params:
    buffer = the buffer to fill
    len = length of the buffer (in bytes)

Returns:
    The number of bytes filled - a negative number of an error occurred
*/
extern(C) size_t mir_random_genRandomNonBlocking(void* ptr, size_t len) @nogc @trusted nothrow
{
    version(Windows)
    {
        if (!CryptGenRandom(hProvider, len, cast(PBYTE) ptr))
            return -1;
        return len;
    }
    else
    {
        version(linux)
        with(GET_RANDOM)
        {
            // Linux >= 3.17 has getRandom
            if (hasGetRandom == AVAILABLE)
                return genRandomImplSysNonBlocking(ptr, len);
            else
                return genRandomImplFileNonBlocking(ptr, len);
        }
        else
        {
            return genRandomImplFileNonBlocking(ptr, len);
        }
    }
}
/// ditto
alias genRandomNonBlocking = mir_random_genRandomNonBlocking;

///
@safe nothrow unittest
{
    ubyte[] buf = new ubyte[10];
    genRandomNonBlocking(&buf[0], buf.length);

    import std.algorithm.iteration : sum;
    assert(buf.sum > 0, "Only zero points generated");
}

@nogc nothrow
unittest
{
    ubyte[10] buf;
    genRandomNonBlocking(buf.ptr, buf.length);

    int sum;
    foreach (b; buf)
        sum += b;

    assert(sum > 0, "Only zero points generated");
}
