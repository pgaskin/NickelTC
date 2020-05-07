# Dockerfile for building an arm-nickel-linux-gnueabihf toolchain and sysroot
# which closely matches Kobo.

# shared between build and runtime
# note: use the olderst debian version possible to provide the best
#       compatibility when extracting the toolchain for use on an arbitrary host
#       without docker.
# note: we use buster here as it's the minimum debian version with
#       python3-distutils, which is required to build the sysroot.
FROM debian:buster-slim AS base

# ensure the container user is root
USER root

# install deps
RUN apt-get update -qqy && \
    DEBIAN_FRONTEND=noninteractive apt-get install -qqy \
        autoconf autoconf-archive automake bash bison build-essential \
        busybox-static bsdutils bzip2 coreutils curl diffutils file findutils \
        flex gawk git gperf grep gzip jq libtool make nano openssh-client perl \
        rsync sed unzip wget xz-utils zip && \
    DEBIAN_FRONTEND=noninteractive apt-get install -qqy \
        cmake ninja-build python python3 subversion && \
    DEBIAN_FRONTEND=noninteractive apt-get install -qqy \
        help2man libdbus-1-dev libicu-dev libncurses-dev libpng-dev pigz \
        python3-distutils python3-pip tclsh texinfo zlib1g-dev && \
    rm -rf /var/lib/apt/lists

# create the tc dir
RUN mkdir -p /tc/x-tools

# build
FROM base AS build

# set the home dir so ctng and the sysroot script can use it
# note: we don't change the user because some of the build scripts chowns files
#       as root, which makes the build break when another one needs to change it
ENV HOME=/tc

# download crosstool-ng
# note: downloads to /tc/ctng-src
RUN git init /tc/ctng-src && \
    git -C /tc/ctng-src remote add origin https://github.com/NiLuJe/crosstool-ng.git && \
    git -C /tc/ctng-src fetch origin && \
    git -C /tc/ctng-src checkout --recurse-submodules 23ba174c7ebdefc09dc610286c92619c610e4d27 && \
    git -C /tc/ctng-src submodule update --init --recursive

# build crosstool-ng
# note: builds to /tc/ctng-out
RUN cd /tc/ctng-src && \
    ./bootstrap && \
    ./configure --prefix="/tc/ctng-out" && \
    make -j12 && \
    make install && \
    rm -rf /tc/ctng-src

# download deps and setup toolchain
# note: downloads to /tc/tc-cache, mount as a Docker volume for offline builds
#       later (files will only be downloaded if needed)
RUN mkdir /tc/tc-src /tc/tc-cache && \
    /tc/ctng-out/bin/ct-ng -C /tc/tc-src arm-nickel-linux-gnueabihf && \
    echo 'CT_SAVE_TARBALLS=y' >> /tc/tc-src/.config && \
    echo 'CT_LOCAL_TARBALLS_DIR="/tc/tc-cache"' >> /tc/tc-src/.config && \
    echo 'CT_EXPERIMENTAL=y' >> /tc/tc-src/.config && \
    echo 'CT_ALLOW_BUILD_AS_ROOT=y' >> /tc/tc-src/.config && \
    echo 'CT_ALLOW_BUILD_AS_ROOT_SURE=y' >> /tc/tc-src/.config && \
    echo 'CT_LOG_PROGRESS_BAR=n' >> /tc/tc-src/.config && \
    /tc/ctng-out/bin/ct-ng -C /tc/tc-src oldconfig && \
    /tc/ctng-out/bin/ct-ng -C /tc/tc-src updatetools && \
    /tc/ctng-out/bin/ct-ng -C /tc/tc-src build CT_ONLY_DOWNLOAD=y

# build toolchain
# mote: builds to /tc/x-tools/arm-nickel-linux-gnueabihf, should be relocatable
RUN /tc/ctng-out/bin/ct-ng -C /tc/tc-src build CT_FORBID_DOWNLOAD=y && \
    rm -rf /tc/tc-src
# note: image is ~1gb at this point, takes 22 min on i5-4460

# add NiLuJe's scripts
# note: x-compile.sh is only used for setting the env vars (which is also why
#       the TC must remain in ~/x-tools for now)
COPY ./niluje /tc/sysroot-src
RUN chmod +x /tc/sysroot-src/*.sh

# patch the env script with our paths (I don't understand NiLuJe's home folder
# layout...)
# note: if we don't do this, the first obvious sign is when the sysroot fails
#       with something about zlib being missing (because the zlib-ng which gets
#       built and installed into the sysroot isn't found due to the LDFLAGS lib
#       dir being incorrect)
# note: the replacement for kobo-nickel-sysroot isn't strictly necessary, but it
#       prevents us from having to manually merge the sysroot afterwards (and
#       fix paths in config files for qmake and libtool)
# note: the bottom replacement is meant to make it easy to spot if any of
#       NiLuJe's paths were missed
RUN grep '${HOME}/Kobo/CrossTool/Build_${KINDLE_TC}' /tc/sysroot-src/kobo-nickel-sysroot.sh && \
    sed -i 's:${HOME}/Kobo/CrossTool/Build_${KINDLE_TC}:/tc/x-tools:g' /tc/sysroot-src/kobo-nickel-sysroot.sh && \
    grep '/tc/x-tools' /tc/sysroot-src/kobo-nickel-sysroot.sh && \
    grep '${HOME}/Kobo/CrossTool/Build_${KINDLE_TC}' /tc/sysroot-src/x-compile.sh && \
    sed -i 's:${HOME}/Kobo/CrossTool/Build_${KINDLE_TC}:/tc/x-tools:g' /tc/sysroot-src/x-compile.sh && \
    grep '/tc/x-tools' /tc/sysroot-src/x-compile.sh && \
    sed -i 's:CrossTool/Build_:BAD_PATH_WHY_DO_THESE_HAVE_TO_BE_HARDCODED:g' /tc/sysroot-src/kobo-nickel-sysroot.sh && \
    sed -i 's:CrossTool/Build_:BAD_PATH_WHY_DO_THESE_HAVE_TO_BE_HARDCODED:g' /tc/sysroot-src/x-compile.sh

# force the sysroot to use our copy of the svn deps
RUN grep 'if ! svn info' /tc/sysroot-src/kobo-nickel-sysroot.sh && \
    sed -i 's:if ! svn info:if false:g' /tc/sysroot-src/kobo-nickel-sysroot.sh && \
    sed -i 's:svn :NOOOOO :g' /tc/sysroot-src/kobo-nickel-sysroot.sh

# use a fixed date for the portage tree
RUN grep 'wget "${GENTOO_MIRROR}/snapshots/portage-latest.tar.xz" -O "${portage_wd}/portage.tar.xz"' /tc/sysroot-src/kobo-nickel-sysroot.sh && \
    sed -i 's,${GENTOO_MIRROR}/snapshots/portage-latest.tar.xz,http://distfiles.gentoo.org/snapshots/portage-20200501.tar.xz,g' /tc/sysroot-src/kobo-nickel-sysroot.sh

# dirty hack to fix intermittent pull issues
RUN grep 'git fetch kobo' /tc/sysroot-src/kobo-nickel-sysroot.sh && \
    sed -i 's:git fetch kobo:git fetch kobo || git fetch kobo || git fetch kobo:g' /tc/sysroot-src/kobo-nickel-sysroot.sh

# download deps and build sysroot
# note: this is where things start becoming nondeterministic
#       - ~~the unversioned patches and x-compile.sh script is downloaded from
#         NiLuJe's SVN~~
#       - ~~the latest portage tree is downloaded (the versions are fixed so
#         it's deterministic, but versions may disappear over time)~~
#       - tarballs are downloaded and not cached (they might disappear one day)
#       - Kobo's latest Qt forks are downloaded (the versions and other stuff
#         may change at any moment)
# note: to fix the above:
#       - DONE: ~~include specific revision of SVN stuff in repo or download it~~
#       - DONE: ~~download specific portage revision with wget~~
#       - TODO: wrap wget to cache by filename
#       - TODO: download specific Kobo git revisions as tarballs with wget
# note: the built sysroot has an incorrect prefix (it includes the host path,
#       rather than using DESTDIR), but luckily this doesn't matter too much
#       when using it as a TC rather than a real sysroot
# note: TC_WANT_QT_LTS=false
# note: TC_WANT_QT_KOBO=true
RUN cd /tc/sysroot-src && ./kobo-nickel-sysroot.sh

# fix permissions
RUN chmod -R u=rwX,go=rX /tc/x-tools/arm-nickel-linux-gnueabihf

# relocate qt (based on experiments repo)
RUN echo '[Paths]' >> /tc/x-tools/arm-nickel-linux-gnueabihf/bin/qt.conf && \
    echo 'Prefix = ../arm-nickel-linux-gnueabihf/sysroot/usr' >> /tc/x-tools/arm-nickel-linux-gnueabihf/bin/qt.conf

# remove libtool la files, which are useless after the initial tc compilation
# and are impossible to relocate properly
RUN find /tc/x-tools/arm-nickel-linux-gnueabihf -name '*.la' -delete

# clean up qmake spec to remove unnecessary flags which reference non-relocated
# paths
# note: the sqlite ones are only used when building qt itself
RUN sed -i '0,/^QMAKE_CFLAGS/{//d;}' /tc/x-tools/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot/usr/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf && \
    sed -i '0,/^QMAKE_CXXFLAGS/{//d;}' /tc/x-tools/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot/usr/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf && \
    sed -i '0,/^QMAKE_LFLAGS/{//d;}' /tc/x-tools/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot/usr/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf && \
    sed -i '0,/^QT_CFLAGS_SQLITE/{//d;}' /tc/x-tools/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot/usr/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf && \
    sed -i '0,/^QT_LFLAGS_SQLITE/{//d;}' /tc/x-tools/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot/usr/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf

# fix pkg-config prefixes (i.e. remove what should have been a DESTDIR, but was
# included in the prefix by NiLuJe's script)
# note: this makes the pc files have flags like -L/usr/lib, which is what we
#       want, as it means we don't need to work around pkg-config's automatic
#       relocation stuff.
RUN find /tc/x-tools/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot/ -name '*.pc' -exec sed -i 's:tc/x-tools/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot/::g' {} +

# fix dbus conf paths (same thing about the DESTDIR)
# note: this is actually pointless, since that config is only used at runtime,
#       but we might as well fix it anyways for completeness.
RUN find /tc/x-tools/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot/usr/share/dbus-1/ -name '*.conf' -exec sed -i 's:tc/x-tools/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot/::g' {} + && \
    find /tc/x-tools/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot/usr/share/doc/dbus/ -name '*.conf' -exec sed -i 's:tc/x-tools/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot/::g' {} + && \
    find /tc/x-tools/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot/usr/etc/dbus-1/ -name '*.conf' -exec sed -i 's:tc/x-tools/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot/::g' {} +

# create pkg-config wrapper
# note: https://autotools.io/pkgconfig/cross-compiling.html has some useful info
# note: we can either use PKG_CONFIG_SYSROOT_DIR with a relocated prefix, or we
#       can use --define-prefix to let pkg-config discover it (but not both, or
#       it will have a double-prefix)
# note: since we need to find the sysroot anyways, we'll use 
#       PKG_CONFIG_SYSROOT_DIR (it's also what's usually used for this kind of
#       thing)
# note: there is also one other negative implication of --define-prefix: it will
#       define -L and -I for the system include path, which is redundant if GCC
#       was compiled properly (which it should be)
RUN echo '#!/bin/bash' > /tc/x-tools/arm-nickel-linux-gnueabihf/bin/arm-nickel-linux-gnueabihf-pkg-config && \
    echo 'set -euo pipefail' >> /tc/x-tools/arm-nickel-linux-gnueabihf/bin/arm-nickel-linux-gnueabihf-pkg-config && \
    echo 'SYSROOT="$(realpath "$(dirname "${BASH_SOURCE[0]}")/../arm-nickel-linux-gnueabihf/sysroot")"' >> /tc/x-tools/arm-nickel-linux-gnueabihf/bin/arm-nickel-linux-gnueabihf-pkg-config && \
    echo 'export PKG_CONFIG_PATH=' >> /tc/x-tools/arm-nickel-linux-gnueabihf/bin/arm-nickel-linux-gnueabihf-pkg-config && \
    echo 'export PKG_CONFIG_LIBDIR="${SYSROOT}/usr/lib/pkgconfig:${SYSROOT}/usr/share/pkgconfig"' >> /tc/x-tools/arm-nickel-linux-gnueabihf/bin/arm-nickel-linux-gnueabihf-pkg-config && \
    echo 'export PKG_CONFIG_SYSROOT_DIR="${SYSROOT}"' >> /tc/x-tools/arm-nickel-linux-gnueabihf/bin/arm-nickel-linux-gnueabihf-pkg-config && \
    echo 'exec pkg-config "$@"' >> /tc/x-tools/arm-nickel-linux-gnueabihf/bin/arm-nickel-linux-gnueabihf-pkg-config && \
    echo '#exec pkg-config --define-prefix "$@"' >> /tc/x-tools/arm-nickel-linux-gnueabihf/bin/arm-nickel-linux-gnueabihf-pkg-config && \
    chmod +x /tc/x-tools/arm-nickel-linux-gnueabihf/bin/arm-nickel-linux-gnueabihf-pkg-config

# fix ldscripts search dir prefixes (also messed up by the fact that DESTDIR was
# included in the prefix)
# note: the '=' is replaced by the sysroot, which is
#       tc_path/arm-nickel-linux-gnueabihf/sysroot (see the tests below)
RUN find /tc/x-tools/arm-nickel-linux-gnueabihf/lib/ldscripts -name '*.x*' -exec sed -i 's:=/tc/x-tools/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/lib:=/../lib:g' {} + && \
    find /tc/x-tools/arm-nickel-linux-gnueabihf/lib/ldscripts -name '*.x*' -exec sed -i 's:=/tc/x-tools/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot:=:g' {} +

# remove absolute paths from Qt PRLs
# note: QMAKE_PRL_BUILD_DIR is only used during building Qt itself, so it can be
#       safely removed.
# note: the -L/tc/x-tools/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot/usr/lib
#       appears in QMAKE_PRL_LIBS due to the DESTDIR/prefix stuff explained
#       above, and is unnecessary since it's already part of GCC's default
#       linker flags.
RUN find /tc/x-tools/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot/usr/lib/ -name '*.prl' -exec sed -i '/^QMAKE_PRL_BUILD_DIR/d' {} \; && \
    find /tc/x-tools/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot/usr/lib/ -name '*.prl' -exec sed -i 's: -L/tc/x-tools/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot/usr/lib::g' {} \;

# remove unnecessary QMAKE_DEFAULT_LIBDIRS, QMAKE_DEFAULT_INCDIRS, and
# QT.*.rpath vars from default qmake spec
# note: these currently match the default GCC ones, and were only added because
#       of the DESTDIR/prefix stuff explained above (usually they aren't even
#       included, try looking at /usr/lib/x86_64-linux-gnu/qt5/mkspecs/qconfig.pri
#       on your host machine for an example of this).
RUN sed -i '/QMAKE_DEFAULT_LIBDIRS =/d' /tc/x-tools/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot/usr/mkspecs/qconfig.pri && \
    sed -i '/QMAKE_DEFAULT_INCDIRS =/d' /tc/x-tools/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot/usr/mkspecs/qconfig.pri && \
    find /tc/x-tools/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot/usr/mkspecs/modules -name '*.pri' -exec sed -i '/.rpath = \/tc\/x-tools\/arm-nickel-linux-gnueabihf\/arm-nickel-linux-gnueabihf\/sysroot/d' {} \;

# more Qt DESTDIR/prefix cleanup
# note: all of these are unnecessary and were only added due to the messed up
#       prefix (and QT_QMAKE_LOCATION is only used during the qt build)
RUN sed -i '/PKG_CONFIG_LIBDIR =/d' /tc/x-tools/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot/usr/mkspecs/qconfig.pri && \
    sed -i 's: -L/tc/x-tools/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot/usr/lib::g' /tc/x-tools/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot/usr/mkspecs/qmodule.pri && \
    sed -i '/QT_CFLAGS_DBUS =/d' /tc/x-tools/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot/usr/mkspecs/qmodule.pri && \
    sed -i 's: QT_QMAKE_LOCATION=\\"/tc/x-tools/qt5/qtbase/bin/qmake\\"::g' /tc/x-tools/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot/usr/mkspecs/modules/qt_lib_bootstrap_private.pri

# fix runtime ENGINESDIR and OPENSSLDIR defines
RUN sed -i 's:tc/x-tools/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot/::g' /tc/x-tools/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot/usr/include/openssl/opensslconf.h

FROM base AS relocate-sanity-check

# note: also manually check 'grep -r /tc/x-tools /tc' (note that the matches in
# binaries and libs themselves are usually fine, as they're just the build path
# in logs and etc...)

# copy the toolchain
COPY --from=build /tc/x-tools/arm-nickel-linux-gnueabihf/ /relocated/arm-nickel-linux-gnueabihf/
ENV PATH="/relocated/arm-nickel-linux-gnueabihf/bin:${PATH}"

# run some tests
RUN bash -euxo pipefail -c ' \
    echo -e "\nTesting sysroot"; \
    echo -n "$(realpath "$(arm-nickel-linux-gnueabihf-gcc -print-sysroot)")" | grep -qe "/relocated/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot"; \
    echo -e "\nTesting pkg-config"; \
    ! arm-nickel-linux-gnueabihf-pkg-config --cflags --libs Qt5Core | grep -qe "/tc/x-tools" -e "-L/usr" -e "-I/usr"; \
    arm-nickel-linux-gnueabihf-pkg-config --cflags --libs Qt5Core | grep -qe "/relocated/arm-nickel-linux-gnueabihf"; \
    echo -e "\nTesting cross-compilation"; \
    echo -e "int main() { return 0; }" | arm-nickel-linux-gnueabihf-gcc -xc - -o/dev/null; \
    echo -e "int main() { return 0; }" | arm-nickel-linux-gnueabihf-gcc -xc -v - -o/dev/null |& grep -qe "-L/relocated/arm-nickel-linux-gnueabihf/bin/.."; \
    echo -e "\nTesting include and lib paths"; \
    echo -e "#include <zlib.h> \n int main() { deflateResetKeep(NULL); return 0; }" | arm-nickel-linux-gnueabihf-gcc -xc - -o/dev/null -lz; \
    echo -e "\nTesting qmake"; \
    mkdir /tmp/q; \
    echo -e "#include <QString> \n #include <stdio.h> \n int main() { QString s(\"test\"); printf(\"%s\", qPrintable(s)); }" > /tmp/q/main.cc; \
    cd /tmp/q && qmake -project && qmake . && make; \
    arm-nickel-linux-gnueabihf-ldd --root /tmp/q /tmp/q/q | grep -e "/usr/lib/libQt5Core.so" >/dev/null; \
    echo -e "\nChecking PRLs"; \
    find /relocated/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot/usr/lib/ -name "*.prl" -exec sh -ec "! grep /tc/x-tools \"\$@\"" {} +; \
    echo -e "\nChecking mkspecs"; \
    find /relocated/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot/usr/mkspecs -name "*.pr*" -exec sh -ec "! grep /tc/x-tools \"\$@\"" {} +; \
    '

# just the toolchain and sysroot
FROM base AS toolchain

# copy the toolchain
COPY --from=build /tc/x-tools/arm-nickel-linux-gnueabihf/ /tc/arm-nickel-linux-gnueabihf/
ENV PATH="/tc/arm-nickel-linux-gnueabihf/bin:${PATH}"

CMD ["/bin/bash"]
