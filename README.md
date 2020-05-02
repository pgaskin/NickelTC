# NickelTC
A dockerized, deterministic, automated, fixed, and fully-relocatable build of [@NiLuJe](https://github.com/geek1011/NiLuJe)'s [toolchain](http://trac.ak-team.com/trac/log/niluje/Configs/trunk/Kindle/Misc) for Kobo eReaders.

This succeeds the old docker image `docker.io/geek1011/kobo-toolchain` built from [kobo-plugin-experiments](https://github.com/geek1011/kobo-plugin-experiments).

### Features
- [NickelTC-specific](./Dockerfile)
  - Fully relocatable without any additional scripts.
  - Fixed DESTDIR/prefix (NiLuJe needed to include the DESTDIR in the prefix path
  due to limitations in the build scripts of some dependencies, see [geek1011/kobo-plugin-experiments#2](https://github.com/geek1011/kobo-plugin-experiments/issues/2))
  - Docker image (but can still run directly on the host).
  - Fully automated builds without dependencies on NiLuJe's home folder layout.
  - Offline builds (TODO: almost).
  - Versioned dependencies (i.e. you can rebuild old commits) (TODO: almost).
  - Minimal dependencies.
  - Detailed comments.
- [NiLuJe's scripts](./niluje)
  - Output is essentially identical to Kobo's toolchain and sysroot.
  - Includes all kobo-specific patches.
  - Built from scratch.
  - Patches for running ancient build systems on newer distros.

### Usage
Prebuilt docker images are coming soon.

To run it directly
from the docker image, you can create a wrapper like:

```sh
#!/bin/bash
exec /usr/bin/docker run --volume="$PWD:$PWD" --user="$(id --user):$(id --group)" --workdir="$PWD" --env=HOME --entrypoint="$(basename "${BASH_SOURCE[0]}")" --rm -it <image> "$@"
```

Then, you can symlink it to:

```
arm-nickel-linux-gnueabihf-addr2line arm-nickel-linux-gnueabihf-ar arm-nickel-linux-gnueabihf-as arm-nickel-linux-gnueabihf-c++ arm-nickel-linux-gnueabihf-c++filt arm-nickel-linux-gnueabihf-cc arm-nickel-linux-gnueabihf-cpp arm-nickel-linux-gnueabihf-ct-ng.config arm-nickel-linux-gnueabihf-dwp arm-nickel-linux-gnueabihf-elfedit arm-nickel-linux-gnueabihf-g++ arm-nickel-linux-gnueabihf-gcc arm-nickel-linux-gnueabihf-gcc-4.9.4 arm-nickel-linux-gnueabihf-gcc-ar arm-nickel-linux-gnueabihf-gcc-nm arm-nickel-linux-gnueabihf-gcc-ranlib arm-nickel-linux-gnueabihf-gcov arm-nickel-linux-gnueabihf-gprof arm-nickel-linux-gnueabihf-ld arm-nickel-linux-gnueabihf-ld.bfd arm-nickel-linux-gnueabihf-ld.gold arm-nickel-linux-gnueabihf-ldd arm-nickel-linux-gnueabihf-nm arm-nickel-linux-gnueabihf-objcopy arm-nickel-linux-gnueabihf-objdump arm-nickel-linux-gnueabihf-pkg-config arm-nickel-linux-gnueabihf-populate arm-nickel-linux-gnueabihf-ranlib arm-nickel-linux-gnueabihf-readelf arm-nickel-linux-gnueabihf-size arm-nickel-linux-gnueabihf-strings arm-nickel-linux-gnueabihf-strip lconvert lrelease lupdate moc qdbuscpp2xml qdbusxml2cpp qdoc qmake qmlimportscanner qmlmin qt.conf rcc uic
```

If you don't want to use the docker image, you can extract and use the built
toolchain binaries just like any other. The only dependencies are glibc 2.4+,
pkg-config (optional), and the standard utilities.

When using this toolchain, you'll probably want to include the following flags
as a base if you aren't using qmake:

```
LDFLAGS = -Wl,-rpath,/usr/local/Kobo -Wl,-rpath,/usr/local/Qt-5.2.1-arm/lib
CFLAGS  = -march=armv7-a -mtune=cortex-a8 -mfpu=neon -mfloat-abi=hard -mthumb
```

### Building
Simply run `docker build .` in the root of this repository.

For offline builds, you'll need to mount a volume on `/tc/tc-cache` for the
toolchain deps. You'll also need to mount a volume on `TODO` for the sysroot
ones. The dependencies will be cached when you build the image, and then you'll
be able to build it offline.

The build is *(mostly)* deterministic and the docker build cache can be used
*unless updating Kobo's forks*. **TODO: The sysroot build still uses unversioned
checkouts of Kobo's Qt forks, so those won't currently get updated, neither are
they deterministic.**

To extract the built TC from the image to run on a host directly, run
`docker run --rm <image> tar cvf -C /tc arm-nickel-linux-gnueabihf > tc.tar`.

Note that this cross-toolchain has only been tested on x86_64.

### Development
To update @NiLuJe's TC scripts, update the revision in
[update-niluje.sh](./update-niluje.sh) and run it. You will need to ensure the
relocation and DESTDIR/prefixes are up to date.
