module mir.random.engine.test;

import std.typecons;
import std.stdio;

version(linux) version(X86_64)
{
    shared static this()
    {
        hasGetRandom = initHasGetRandom;
    }

    private static bool hasGetRandom;

    auto initHasGetRandom()
    {
        import core.sys.posix.sys.utsname;
        utsname uts;
        uname(&uts);

        import std.algorithm.iteration : splitter;
        import std.conv : to;

        auto release = uts.release[].splitter(".");
        if (release.front.to!int > 3)
            return true;
        release.popFront;
        if (release.front.to!int > 17)
            return true;
        return false;
    }

    /*
     * Flags for getrandom(2)
     *
     * GRND_NONBLOCK	Don't block and return EAGAIN instead
     * GRND_RANDOM		Use the /dev/random pool instead of /dev/urandom
     */
    enum GRND_NONBLOCK = 0x0001;
    enum GRND_RANDOM = 0x0002;
    enum GETRANDOM = 318;

    size_t syscall(size_t ident, size_t n, size_t arg1, size_t arg2)
    {
        size_t ret;

        synchronized asm
        {
            mov RAX, ident;
            mov RDI, n[RBP];
            mov RSI, arg1[RBP];
            mov RDX, arg2[RBP];
            syscall;
            mov ret, RAX;
        }
        return ret;
    }

    bool getRandomImplSys(Flag!"blocking" blocking)(ubyte[] buffer)
    {
        import core.stdc.errno : EAGAIN;
        static if (blocking)
        {
            syscall(GETRANDOM, cast(size_t) &buffer[0], r.sizeof, 0);
            return 0;
        }
        else
        {
            if (syscall(GETRANDOM, cast(size_t) &buffer[0], buffer.length, 0) != EAGAIN)
                return 0;
            else
                return 1;
        }
    }
}

version(Posix)
{
    import core.stdc.stdio : fopen;
    alias IOType = typeof(fopen("a", "b"));
    static private IOType randFd;

    shared static ~this()
    {
        if (randFd !is null)
            fclose(randFd);
    }

    // TODO: use syscalls here as well?
    private bool getRandomImplFile(Flag!"blocking" blocking)(ubyte[] buffer)
    {
        if (randFd !is null)
        {
            static if (blocking)
                randFd = fopen("/dev/random", "r");
            else
                randFd = fopen("/dev/urandom", "r");
        }

        auto genBytes = 0;
        while (genBytes < buffer.length)
        {
            size_t res = fread(buffer.ptr + genBytes, buffer.length - genBytes, 1, randFd);
            genBytes -= res;
        }
        return 0;
    }

    version(linux)
    {
        version(X86_64)
        {
            private void getRandomImpl(Flag!"blocking" blocking)(ubyte[] buffer)
            {
                if (hasGetRandom)
                    getRandomImplSys!(blocking)(buffer);
                else
                    // fallback for older Linux versions
                    getRandomImplFile!(blocking)(buffer);
            }
        } else {
            private alias getRandomImpl = getRandomImplFile;
        }
    } else {
        private alias getRandomImpl = getRandomImplFile;
    }
}

version(Windows)
{
    // the windows header in core.runtime are broken for x64!
    alias ULONG_PTR = size_t;
    alias BOOL = bool;
    alias DWORD = uint;
    alias LPCWSTR = wchar*;
    alias PBYTE = ubyte*;
    alias HCRYPTPROV = ULONG_PTR;
    alias LPCSTR = const(char)*;

    import core.sys.windows.wincrypt : PROV_RSA_FULL, CRYPT_NEWKEYSET, CRYPT_VERIFYCONTEXT, CRYPT_SILENT;

    extern(Windows) BOOL CryptGenRandom(HCRYPTPROV, DWORD, PBYTE);
    extern(Windows) BOOL CryptAcquireContextA(HCRYPTPROV*, LPCSTR, LPCSTR, DWORD, DWORD);
    extern(Windows) BOOL CryptAcquireContextW(HCRYPTPROV*, LPCWSTR, LPCWSTR, DWORD, DWORD);
    extern(Windows) BOOL CryptReleaseContext(HCRYPTPROV, ULONG_PTR);

    private static ULONG_PTR hProvider;

    auto initGetRandom()
    {
        import core.sys.windows.winbase : GetLastError;
        import core.sys.windows.winerror : NTE_BAD_KEYSET;

        // https://msdn.microsoft.com/en-us/library/windows/desktop/aa379886(v=vs.85).aspx
        // For performance reasons, we recommend that you set the pszContainer
        // parameter to NULL and the dwFlags parameter to CRYPT_VERIFYCONTEXT
        // in all situations where you do not require a persisted key.
        // CRYPT_SILENT is intended for use with applications for which the UI cannot be displayed by the CSP.
	    if (!CryptAcquireContextW(&hProvider, null, null, PROV_RSA_FULL, CRYPT_VERIFYCONTEXT | CRYPT_SILENT))
	    {
            writeln("FAIL");
            if (GetLastError() == NTE_BAD_KEYSET)
            {
                // No default container was found. Attempt to create it.
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

    private bool getRandomImpl(Flag!"blocking" blocking)(ubyte[] buffer)
    {
        import core.sys.windows.winbase : GetLastError;
        import core.sys.windows.winerror : ERROR_INVALID_HANDLE, ERROR_INVALID_PARAMETER, NTE_BAD_UID, NTE_FAIL;

        if (hProvider == 0)
            if (initGetRandom != 0)
                return 1;

        writeln("win.getRandom: ", hProvider);

	    if (!CryptGenRandom(hProvider, cast(uint) buffer.length, buffer.ptr))
	    {
	        writeln("buffer", buffer);
	        switch(GetLastError())
	        {
                case ERROR_INVALID_HANDLE:
                    writeln("invalid handle");
                    break;
                case ERROR_INVALID_PARAMETER:
                    writeln("invalid params");
                    break;
                case NTE_BAD_UID:
                    writeln("bad_uid");
                    break;
                case NTE_FAIL:
                    writeln("nte_fail");
                    break;
                default:
                    writeln("fail");
            }

		    return 1;
	    }
		return 0;
	}
}

auto getRandom(Flag!"blocking" blocking = No.blocking, Flag!"raise" raise = No.raise)(ubyte[] buffer)
{
    static if (raise)
    {
        if (getRandomImpl!(blocking)(buffer))
            throw new Exception("Random error");
    }
    else
    {
        return getRandomImpl!(blocking)(buffer);
    }
}

unittest
{
    import std.stdio;
    ubyte[] buf = new ubyte[4];
    getRandom(buf);
    writeln(buf);
}
