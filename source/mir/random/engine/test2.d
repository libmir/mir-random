module mir.random.engine.test2;

import std.conv : text;
import std.digest.sha;
import core.sys.windows.wincrypt;
import std.stdio;
import core.sys.windows.winbase;
import core.sys.windows.winerror;

alias DWORD = uint;

final class SystemRNG {
	version(Windows)
	{
		//cryptographic service provider
		private HCRYPTPROV hCryptProv;
	}
	else version(Posix)
	{
		private import std.stdio;
		private import std.exception;

		//cryptographic file stream
		private File file;
	}
	else
	{
		static assert(0, "OS is not supported");
	}

	/**
		Creates new system random generator
	*/
	this()
	{
		version(Windows)
		{
			//init cryptographic service provider
			if(0 == CryptAcquireContext(&this.hCryptProv, null, null, PROV_RSA_FULL, CRYPT_VERIFYCONTEXT))
			{
				writeln(text("Cannot init SystemRNG: Error id is ", GetLastError()));
			}
		}
		else version(Posix)
		{
			try
			{
				//open file
				this.file = File("/dev/urandom");
				//do not use buffering stream to avoid possible attacks
				this.file.setvbuf(null, _IONBF);
			}
			catch(ErrnoException e)
			{
				writeln(text("Cannot init SystemRNG: Error id is ", e.errno, `, Error message is: "`, e.msg, `"`));
			}
			catch(Exception e)
			{
				writeln(text("Cannot init SystemRNG: ", e.msg));
			}
		}
	}

	~this()
	{
		version(Windows)
		{
			CryptReleaseContext(this.hCryptProv, 0);
		}
	}

	@property bool empty() { return false; }
	@property ulong leastSize() { return ulong.max; }
	@property bool dataAvailableForRead() { return true; }
	const(ubyte)[] peek() { return null; }

	void read(ubyte[] buffer)
	in
	{
		assert(buffer.length, "buffer length must be larger than 0");
		assert(buffer.length <= uint.max, "buffer length must be smaller or equal uint.max");
	}
	body
	{
		version(Windows)
		{
			if(0 == CryptGenRandom(this.hCryptProv, cast(DWORD)buffer.length, buffer.ptr))
			{
				writeln(text("Cannot get next random number: Error id is ", GetLastError()));
			}
		}
		else version(Posix)
		{
			try
			{
				this.file.rawRead(buffer);
			}
			catch(ErrnoException e)
			{
				writeln(text("Cannot get next random number: Error id is ", e.errno, `, Error message is: "`, e.msg, `"`));
			}
			catch(Exception e)
			{
				writeln(text("Cannot get next random number: ", e.msg));
			}
		}
	}
}

//test heap-based arrays
unittest
{
	import std.algorithm;
	import std.range;

	//number random bytes in the buffer
	enum uint bufferSize = 20;

	//number of iteration counts
	enum iterationCount = 10;

	auto rng = new SystemRNG();

	//holds the random number
	ubyte[] rand = new ubyte[bufferSize];

	//holds the previous random number after the creation of the next one
	ubyte[] prevRadn = new ubyte[bufferSize];

	//create the next random number
	rng.read(prevRadn);

	assert(!equal(prevRadn, take(repeat(0), bufferSize)), "it's almost unbelievable - all random bytes is zero");

	//take "iterationCount" arrays with random bytes
	foreach(i; 0..iterationCount)
	{
		//create the next random number
		rng.read(rand);

		assert(!equal(rand, take(repeat(0), bufferSize)), "it's almost unbelievable - all random bytes is zero");

		assert(!equal(rand, prevRadn), "it's almost unbelievable - current and previous random bytes are equal");

		//copy current random bytes for next iteration
		prevRadn[] = rand[];
	}
}
