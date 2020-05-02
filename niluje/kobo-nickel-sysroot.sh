#!/bin/bash -ex
#
# Quick'n dirty build-script for a minimal Qt 5 Kobo sysroot...
#
# $Id$
#
# kate: syntax bash;
#
##

#
# Fetch distfiles:
#
#	emerge -1 -f expat libpng libjpeg-turbo icu dbus dev-libs/openssl:0 libpcre libxml2 libxslt
#

# NOTE: We assume every *custom* script/patch we depend on live in the same folder as this one
#       (This happens to hold true in my SVN tree, too).
SCRIPT_NAME="${BASH_SOURCE[0]-${(%):-%x}}"
SCRIPT_BASE_DIR="$(readlink -f "${SCRIPT_NAME%/*}")"

# Are we in a live checkout of my SVN tree?
if ! svn info "${SCRIPT_BASE_DIR}" &>/dev/null ; then
	# Build a list of what we need, and get it.
	for svn_dep in $(grep '${SCRIPT_BASE_DIR}/' "${SCRIPT_NAME}" | cut -f2 -d'/' | cut -f1 -d' ') ; do
		if [[ ${#svn_dep} -le 2 ]] ; then
			continue
		fi
		echo "* Checking out ${svn_dep} . . ."
		# NOTE: Prefer svn cat to a wget/curl GET, because it expands svn keywords.
		svn cat https://svn.ak-team.com/svn/Configs/trunk/Kindle/Misc/${svn_dep} > ${svn_dep}
	done
fi

# Are we on Gentoo
if [[ -f "/etc/gentoo-release" ]] ; then
	PORTAGE_DIR="/usr/portage"
else
	PORTAGE_DIR="/tmp/fauxrtage"
	portage_wd="${PORTAGE_DIR}"
	mkdir -p "${portage_wd}/distfiles"

	# NOTE: Feel free to choose something a little closer to home... (https://gentoo.org/downloads/mirrors/)
	GENTOO_MIRROR="http://gentoo.osuosl.org"

	# We'll need a Portage snapshot...
	echo "* Getting a Portage snapshot . . ."
	wget "${GENTOO_MIRROR}/snapshots/portage-latest.tar.xz" -O "${portage_wd}/portage.tar.xz"

	# Pull what we need out of the latest Portage snapshot
	for portage_dep in $(grep '${PORTAGE_DIR}/' "${SCRIPT_NAME}" | tr ' ' '\n' | grep '${PORTAGE_DIR}') ; do
		if [[ ${#portage_dep} -le 17 ]] ; then
			continue
		fi

		if echo "${portage_dep}" | grep -q 'distfiles' ; then
			# Get the sources from our mirror
			echo "* Downloading ${portage_dep##*/} . . ."
			wget "${GENTOO_MIRROR}/distfiles/${portage_dep##*/}" -O "${portage_wd}/distfiles/${portage_dep##*/}"
		else
			# Pull that out of the Portage snapshot
			echo "* Pulling ${portage_dep#*/} out of the Portage tree . . ."
			tar -C "${portage_wd}" -xvJf "${portage_wd}/portage.tar.xz" "portage/${portage_dep#*/}" --show-transformed --transform 's,^portage/,,S'
		fi
	done

	# Cleanup behind us
	rm -f "${portage_wd}/portage.tar.xz"
	unset portage_wd
fi

# Setup the env for the right TC...
source ${SCRIPT_BASE_DIR}/x-compile.sh nickel env

# NOTE: This is *roughly* what TC_BUILD_DIR points to in my other TCs ;).
TC_BUILD_WD="${HOME}/Kobo/CrossTool/Build_${KINDLE_TC}"

# Override that to get rid of the counter
update_title_info()
{
	# Get package name from the current directory, because I'm lazy ;)
	pkgName="${PWD##*/}"

	# Set the panel name to something short & useful
	myPanelTitle="X-TC ${KINDLE_TC}"
	echo -e '\033k'${myPanelTitle}'\033\\'
	# Set the window title to a longer description of what we're doing...
	myWindowTitle="Building ${pkgName} for ${KINDLE_TC}"
	echo -e '\033]2;'${myWindowTitle}'\007'

	# Bye, Felicia!
	prune_la_files
}

## Get to our build dir
mkdir -p "${TC_BUILD_DIR}"
cd "${TC_BUILD_WD}"

## Do we shoot for a recent Qt 5 version and a fairly painless build, or do we opt for the masochistic 5.2 option?
TC_WANT_QT_LTS="false"
## Do we shoot for the Kobo branches, or upstream's old/5.2?
TC_WANT_QT_KOBO="true"

## NOTE: We'll disable LTO, because while it at least appears to build fine (... mostly, I had to disable it in few places),
##       it was still pretty rough around the edges on GCC 4.9, so, let's play it safe... :).
export CFLAGS="${NOLTO_CFLAGS}"
export CXXFLAGS="${NOLTO_CFLAGS}"

## And here we go...
echo "* Building zlib-ng . . ."
echo ""
ZLIB_SOVER="1.2.11.zlib-ng"
rm -rf zlib-ng
until git clone --depth 1 https://github.com/zlib-ng/zlib-ng.git ; do
	rm -rf zlib-ng
	sleep 15
done
cd zlib-ng
update_title_info
# NOTE: We CANNOT support runtime HWCAP checks, because we mostly don't have access to getauxval (c.f., comments around OpenSSL for more details (in x-compile.sh)).
#       On the other hand, we don't need 'em: we know the exact target we're running on.
#       So switch back to compile-time checks.
# NOTE: Technically, with this TC, which moved to glibc 2.19, we do have access to getauxval.
#       The point about not actually needing a runtime check still stands, though ;).
patch -p1 <  ${SCRIPT_BASE_DIR}/zlib-ng-nerf-arm-hwcap.patch
env CHOST="${CROSS_TC}" ./configure --shared --prefix=${TC_BUILD_DIR} --zlib-compat --without-acle
make ${JOBSFLAGS}
make install

echo "* Building expat . . ."
echo ""
cd ..
EXPAT_SOVER="1.6.11"
tar -xvJf ${PORTAGE_DIR}/distfiles/expat-2.2.9.tar.xz
cd expat-2.2.9
update_title_info
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-static --enable-shared --without-docbook
make ${JOBSFLAGS}
make install

echo "* Building libpng . . ."
echo ""
cd ..
LIBPNG_SOVER="16.37.0"
tar xvJf ${PORTAGE_DIR}/distfiles/libpng-1.6.37.tar.xz
cd libpng-1.6.37
update_title_info
# LTO makefile compat...
patch -p1 < ${SCRIPT_BASE_DIR}/libpng-fix-Makefile-for-lto.patch
autoreconf -fi
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-static --enable-shared --enable-arm-neon=yes
make ${JOBSFLAGS}
make install

echo "* Building libjpeg-turbo . . ."
echo ""
cd ..
LIBJPG_SOVER="62.3.0"
LIBTJP_SOVER="0.2.0"
tar -I pigz -xvf ${PORTAGE_DIR}/distfiles/libjpeg-turbo-2.0.4.tar.gz
cd libjpeg-turbo-2.0.4
update_title_info
# Oh, CMake (https://gitlab.kitware.com/cmake/cmake/issues/12928) ...
export CFLAGS="${BASE_CPPFLAGS} ${NOLTO_CFLAGS}"
mkdir -p build
cd build
${CMAKE} .. -DENABLE_STATIC=OFF -DENABLE_SHARED=ON -DWITH_MEM_SRCDST=ON -DWITH_JAVA=OFF
make ${JOBSFLAGS} VERBOSE=1
make install
cd ..
export CFLAGS="${NOLTO_CFLAGS}"

# NOTE: ICU used to/still has a very weird way of handling a versioned API:
#       instead of relying on ELF symbol versioning, like everybody else, it actually *renames* the symbol names themselves.
#       Gentoo defaults to unsuffixed symbols, because that's the only sane approach to this mess (via --disable-renaming and the matching define tweak, c.f., x-compile.sh),
#       but the version shipped by Kobo features such suffixes...
#       Sooo, build the Kobo version, with the suffix, just to be safe...
if [[ "${TC_WANT_QT_LTS}" == "true" ]] ; then
	echo "* Building ICU 67.1 . . ."
	echo ""
	ICU_SOVER="67.1"
	cd ..
	tar -I pigz -xvf ${PORTAGE_DIR}/distfiles/icu4c-67_1-src.tgz
	cd icu/source
	update_title_info
	patch -p1 < ${PORTAGE_DIR}/dev-libs/icu/files/icu-65.1-remove-bashisms.patch
	patch -p1 < ${PORTAGE_DIR}/dev-libs/icu/files/icu-64.2-darwin.patch
	sed -i -e "s:LDFLAGSICUDT=-nodefaultlibs -nostdlib:LDFLAGSICUDT=:" config/mh-linux
	sed -i -e 's:icudefs.mk:icudefs.mk Doxyfile:' configure.ac
	autoreconf -fi
	# Cross-Compile fun...
	mkdir ../../icu-host
	cd ../../icu-host
	env CFLAGS="" CXXFLAGS="" ASFLAGS="" LDFLAGS="" CC="gcc" CXX="g++" AR="ar" RANLIB="ranlib" NM="nm" LD="ld" ../icu/source/configure --enable-renaming --disable-debug --disable-samples --disable-layoutex --enable-static
	# NOTE: Don't care about verbose output for the host build ;).
	make ${JOBSFLAGS}
	cd -
	# ICU tries to use clang by default
	export CC="${CROSS_TC}-gcc"
	export CXX="${CROSS_TC}-g++"
	export LD="${CROSS_TC}-ld"
	# ICU 64.x requires C++11
	if [[ "${TC_WANT_QT_LTS}" == "true" ]] ; then
		# Match the Qt std level, just in case...
		export CXXFLAGS="${NOLTO_CFLAGS} -std=c++14"
	else
		export CXXFLAGS="${NOLTO_CFLAGS} -std=c++11"
	fi
	# Huh. Why this only shows up w/ LTO is a mystery...
	export ac_cv_c_bigendian=no
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-static --enable-shared --enable-renaming --disable-samples --disable-layoutex --disable-debug --with-cross-build="${TC_BUILD_WD}/icu-host"
	make ${JOBSFLAGS} VERBOSE=1
	make install
	unset ac_cv_c_bigendian
	export CXXFLAGS="${NOLTO_CFLAGS}"
	unset LD
	unset CXX
	unset CC
	cd ..
else
	# NOTE: Kobo updated from 4.6.1 to 64.2 with FW 4.18
	echo "* Building ICU 64.2 . . ."
	echo ""
	ICU_SOVER="64.2"
	cd ..
	rm -rf icu
	until git clone -b kobo --single-branch --depth 1 https://github.com/kobolabs/icu.git ; do
		rm -rf icu
		sleep 15
	done
	cd icu/icu4c/source
	update_title_info
	patch -p1 < ${PORTAGE_DIR}/dev-libs/icu/files/icu-64.2-darwin.patch
	patch -p1 < ${PORTAGE_DIR}/dev-libs/icu/files/icu-64.1-data_archive_generation.patch
	sed -i -e "s:LDFLAGSICUDT=-nodefaultlibs -nostdlib:LDFLAGSICUDT=:" config/mh-linux
	sed -i -e 's:icudefs.mk:icudefs.mk Doxyfile:' configure.ac
	autoreconf -fi
	# Cross-Compile fun...
	mkdir ../../../icu-host
	cd ../../../icu-host
	env CFLAGS="" CXXFLAGS="" ASFLAGS="" LDFLAGS="" CC="gcc" CXX="g++" AR="ar" RANLIB="ranlib" NM="nm" LD="ld" ../icu/icu4c/source/configure --enable-renaming --disable-debug --disable-samples --disable-layoutex --enable-static
	# NOTE: Don't care about verbose output for the host build ;).
	make ${JOBSFLAGS}
	cd -
	# ICU tries to use clang by default
	export CC="${CROSS_TC}-gcc"
	export CXX="${CROSS_TC}-g++"
	export LD="${CROSS_TC}-ld"
	# ICU 64.x requires C++11
	if [[ "${TC_WANT_QT_LTS}" == "true" ]] ; then
		# Match the Qt std level, just in case...
		export CXXFLAGS="${NOLTO_CFLAGS} -std=c++14"
	else
		export CXXFLAGS="${NOLTO_CFLAGS} -std=c++11"
	fi
	# Use Kobo's config to tone down the size of the ICU Data lib (c.f., https://github.com/unicode-org/icu/blob/master/docs/userguide/icu_data/buildtool.md)
	export ICU_DATA_FILTER_FILE="${PWD}/kobo.json"
	# Huh. Why this only shows up w/ LTO is a mystery...
	export ac_cv_c_bigendian=no
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-static --enable-shared --enable-renaming --disable-samples --disable-layoutex --disable-debug --with-cross-build="${TC_BUILD_WD}/icu-host"
	make ${JOBSFLAGS} VERBOSE=1
	make install
	unset ac_cv_c_bigendian
	unset ICU_DATA_FILTER_FILE
	export CXXFLAGS="${NOLTO_CFLAGS}"
	unset LD
	unset CXX
	unset CC
	cd ../..
fi

echo "* Building dbus . . ."
echo ""
cd ..
tar -I pigz -xvf ${PORTAGE_DIR}/distfiles/dbus-1.12.16.tar.gz
cd dbus-1.12.16
update_title_info
patch -p1 < ${PORTAGE_DIR}/sys-apps/dbus/files/dbus-enable-elogind.patch
patch -p1 < ${PORTAGE_DIR}/sys-apps/dbus/files/dbus-daemon-optional.patch
autoreconf -fi
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-static --enable-shared --disable-verbose-mode --disable-asserts --disable-checks --disable-selinux --disable-libaudit --disable-apparmor --enable-inotify --disable-kqueue --disable-elogind --disable-systemd --disable-embedded-tests --disable-modular-tests --disable-stats --without-x --disable-xml-docs --disable-doxygen-docs
make ${JOBSFLAGS}
make install

if [[ "${TC_WANT_QT_LTS}" == "true" ]] ; then
	echo "* Building OpenSSL 1.1.1 . . ."
	echo ""
	cd ..
	tar -I pigz -xvf ${PORTAGE_DIR}/distfiles/openssl-1.1.1g.tar.gz
	cd openssl-1.1.1g
	update_title_info
	export CROSS_COMPILE="${CROSS_TC}-"
	OPENSSL_SOVER="1.1"
	export CPPFLAGS="${BASE_CPPFLAGS} -DOPENSSL_NO_BUF_FREELISTS"
	#export CFLAGS="${CPPFLAGS} ${NOLTO_CFLAGS} -fno-strict-aliasing"
	export CFLAGS="${CPPFLAGS} ${NOLTO_CFLAGS}"
	#export CXXFLAGS="${NOLTO_CFLAGS} -fno-strict-aliasing"
	export LDFLAGS="${BASE_LDFLAGS} -Wa,--noexecstack"
	rm -f Makefile
	patch -p1 < ${PORTAGE_DIR}/dev-libs/openssl/files/openssl-1.1.0j-parallel_install_fix.patch
	sed -i -e '/^MANSUFFIX/s:=.*:=ssl:' -e "/^MAKEDEPPROG/s:=.*:=${CROSS_TC}-gcc:" -e '/^install:/s:install_docs::' Configurations/unix-Makefile.tmpl
	cp ${PORTAGE_DIR}/dev-libs/openssl/files/gentoo.config-1.0.2 gentoo.config
	chmod a+rx gentoo.config
	sed -e '/^$config{dirs}/s@ "test",@@' -i Configure
	sed -i '/stty -icanon min 0 time 50; read waste/d' config
	env CFLAGS= LDFLAGS= ./Configure linux-armv4 -DL_ENDIAN enable-camellia enable-ec enable-srp enable-idea enable-mdc2 enable-rc5 enable-asm enable-heartbeats enable-zlib --prefix=${TC_BUILD_DIR} --openssldir=${TC_BUILD_DIR}/etc/ssl shared threads
	grep '^CFLAGS=' Makefile | LC_ALL=C sed -e 's:^CFLAGS=::' -e 's:\(^\| \)-fomit-frame-pointer::g' -e 's:\(^\| \)-O[^ ]*::g' -e 's:\(^\| \)-march=[^ ]*::g' -e 's:\(^\| \)-mcpu=[^ ]*::g' -e 's:\(^\| \)-m[^ ]*::g' -e 's:^ *::' -e 's: *$::' -e 's: \+: :g' -e 's:\\:\\\\:g' > x-compile-tmp
	DEFAULT_CFLAGS="$(< x-compile-tmp)"
	sed -i -e "/^CFLAGS=/s|=.*|=${DEFAULT_CFLAGS} ${CFLAGS}|" -e "/^LDFLAGS=/s|=[[:space:]]*$|=${LDFLAGS}|" Makefile
	make -j1 AR="${CROSS_TC}-gcc-ar" RANLIB="${CROSS_TC}-gcc-ranlib" NM="${CROSS_TC}-gcc-nm" V=1 depend
	make AR="${CROSS_TC}-gcc-ar" RANLIB="${CROSS_TC}-gcc-ranlib" NM="${CROSS_TC}-gcc-nm" V=1 all
	make AR="${CROSS_TC}-gcc-ar" RANLIB="${CROSS_TC}-gcc-ranlib" NM="${CROSS_TC}-gcc-nm" V=1 install
	export CPPFLAGS="${BASE_CPPFLAGS}"
	export CFLAGS="${NOLTO_CFLAGS}"
	export LDFLAGS="${BASE_LDFLAGS}"
	unset DEFAULT_CFLAGS
	unset CROSS_COMPILE
else
	echo "* Building OpenSSL 1.0.1 . . ."
	echo ""
	cd ..
	rm -rf openssl
	until git clone -b OpenSSL_1_0_1-stable --single-branch --depth 1 https://github.com/openssl/openssl.git ; do
		rm -rf openssl
		sleep 15
	done
	cd openssl
	update_title_info
	export CROSS_COMPILE="${CROSS_TC}-"
	OPENSSL_SOVER="1.0.0"
	export CPPFLAGS="${BASE_CPPFLAGS} -DOPENSSL_NO_BUF_FREELISTS"
	#export CFLAGS="${CPPFLAGS} ${NOLTO_CFLAGS} -fno-strict-aliasing"
	export CFLAGS="${CPPFLAGS} ${NOLTO_CFLAGS}"
	#export CXXFLAGS="${NOLTO_CFLAGS} -fno-strict-aliasing"
	export LDFLAGS="${BASE_LDFLAGS} -Wa,--noexecstack"
	sed -i -e '/DIRS/s: fips : :g' -e '/^MANSUFFIX/s:=.*:=ssl:' -e "/^MAKEDEPPROG/s:=.*:=${CROSS_TC}-gcc:" -e '/^install:/s:install_docs::' Makefile.org
	sed -i '/^SET_X/s:=.*:=set -x:' Makefile.shared
	# OpenSSL 1.0.1 was dropped on 2016-02-26 in Portage... -_-"
	wget "https://gitweb.gentoo.org/repo/gentoo.git/plain/dev-libs/openssl/files/gentoo.config-1.0.1?id=47f53172d2f6e2beaddb1c072d62e51de3884111" -O gentoo.config
	chmod a+rx gentoo.config
	sed -e '/^$config{dirs}/s@ "test",@@' -i Configure
	sed -i '/stty -icanon min 0 time 50; read waste/d' config
	env CFLAGS= LDFLAGS= ./Configure linux-armv4 -DL_ENDIAN enable-camellia enable-ec enable-idea enable-mdc2 enable-rc5 enable-tlsext enable-asm enable-ssl3 enable-heartbeats enable-zlib --prefix=${TC_BUILD_DIR} --openssldir=${TC_BUILD_DIR}/etc/ssl shared threads
	grep '^CFLAG=' Makefile | LC_ALL=C sed -e 's:^CFLAG=::' -e 's:\(^\| \)-ffast-math::g' -e 's:\(^\| \)-fomit-frame-pointer::g' -e 's:\(^\| \)-O[^ ]*::g' -e 's:\(^\| \)-march=[^ ]*::g' -e 's:\(^\| \)-mcpu=[^ ]*::g' -e 's:\(^\| \)-m[^ ]*::g' -e 's:^ *::' -e 's: *$::' -e 's: \+: :g' -e 's:\\:\\\\:g' > x-compile-tmp
	DEFAULT_CFLAGS="$(< x-compile-tmp)"
	sed -i -e "/^CFLAG/s:=.*:=${DEFAULT_CFLAGS} ${CFLAGS}:" -e "/^SHARED_LDFLAGS=/s:$: ${LDFLAGS}:" Makefile
	# Make sure our own LDFLAGS won't get dropped at link time, because we need 'em to properly pickup zlib...
	sed -e 's/SHAREDFLAGS="$(CFLAGS) $(SHARED_LDFLAGS)/SHAREDFLAGS="$(CFLAGS) $(LDFLAGS) $(SHARED_LDFLAGS)/g' -i Makefile.shared
	sed -e 's/SHAREDFLAGS="$${SHAREDFLAGS:-$(CFLAGS) $(SHARED_LDFLAGS)}";/SHAREDFLAGS="$${SHAREDFLAGS:-$(CFLAGS) $(LDFLAGS) $(SHARED_LDFLAGS)}";/g' -i Makefile.shared
	sed -e 's/LDCMD="$${LDCMD:-$(CC)}"; LDFLAGS="$${LDFLAGS:-$(CFLAGS)}";/LDCMD="$${LDCMD:-$(CC)}"; LDFLAGS="$${LDFLAGS:-$(CFLAGS) $(LDFLAGS) $(SHARED_LDFLAGS)}";/g' -i Makefile.shared
	sed -e 's/DO_GNU_APP=LDFLAGS="$(CFLAGS) -Wl,-rpath,$(LIBRPATH)"/DO_GNU_APP=LDFLAGS="$(CFLAGS) $(LDFLAGS) $(SHARED_LDFLAGS) -Wl,-rpath,$(LIBRPATH)"/g' -i Makefile.shared
	make -j1 AR="${CROSS_TC}-gcc-ar r" RANLIB="${CROSS_TC}-gcc-ranlib" NM="${CROSS_TC}-gcc-nm" V=1 depend
	make AR="${CROSS_TC}-gcc-ar r" RANLIB="${CROSS_TC}-gcc-ranlib" NM="${CROSS_TC}-gcc-nm" V=1 all
	make AR="${CROSS_TC}-gcc-ar r" RANLIB="${CROSS_TC}-gcc-ranlib" NM="${CROSS_TC}-gcc-nm" V=1 rehash
	make AR="${CROSS_TC}-gcc-ar r" RANLIB="${CROSS_TC}-gcc-ranlib" NM="${CROSS_TC}-gcc-nm" V=1 install
	export CPPFLAGS="${BASE_CPPFLAGS}"
	export CFLAGS="${NOLTO_CFLAGS}"
	export LDFLAGS="${BASE_LDFLAGS}"
	unset DEFAULT_CFLAGS
	unset CROSS_COMPILE
fi

# NOTE: Introduced in FW 4.19
echo "* Building SQLCipher . . ."
echo ""
cd ..
rm -rf sqlcipher
until git clone -b kobo --single-branch --depth 1 https://github.com/kobolabs/sqlcipher.git ; do
	rm -rf sqlcipher
	sleep 15
done
cd sqlcipher
update_title_info
# NOTE: The shell actually requires the COMPLETE API...
export CPPFLAGS="${BASE_CPPFLAGS} -DSQLITE_HAS_CODEC -DSQLITE_ENABLE_FTS3_PARENTHESIS"
# SQLite doesn't want to be built w/ -ffast-math...
export CFLAGS="${NOLTO_CFLAGS/-ffast-math /}"
# Needs a little push to link against OpenSSL properly...
export LIBS="-lz"
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-releasemode --disable-load-extension --enable-fts3 --enable-rtree --enable-tempstore=yes --disable-static --enable-shared --disable-tcl
make ${JOBSFLAGS}
make install
unset LIBS
export CFLAGS="${NOLTO_CFLAGS}"
export CPPFLAGS="${BASE_CPPFLAGS}"

# Here comes the pain...
if [[ "${TC_WANT_QT_LTS}" == "false" ]] ; then
	echo "* Building Qt 5.2. . ."
	echo ""
	cd ..
	rm -rf qt5
	until git clone -b v5.2.1 --single-branch --depth 1 https://github.com/qt/qt5.git ; do
		rm -rf qt5
		sleep 15
	done
	cd qt5
	update_title_info
	./init-repository

	# Switch to the tip of the 5.2 branch
	if [[ "${TC_WANT_QT_KOBO}" == "false" ]] ; then
		# DIY, because using qtrepotools went nowhere real quick.
		git submodule foreach '[[ "${name}" != "qtqa" ]] && [[ "${name}" != "qtrepotools" ]] && git checkout old/5.2 || exit 0'
	fi

	# Then, switch to the Kobo branches...
	# NOTE: Get the list of repos via PyGitHub:
	#	import os
	#	from github import Github
	#	gh = Github(os.getenv("GH_API_ACCESS_TOK"))
	#	for repo in gh.get_user("kobolabs").get_repos():
	#		print(repo.name)
	if [[ "${TC_WANT_QT_KOBO}" == "true" ]] ; then
		KOBO_REPOS=("qtactiveqt" "qtandroidextras" "qtbase" "qtconnectivity" "qtdeclarative" "qtdoc" "qtgraphicaleffects" "qtimageformats" "qtlocation" "qtmacextras" "qtmultimedia" "qtqa" "qtquick1" "qtquickcontrols" "qtrepotools" "qtscript" "qtsensors" "qtserialport" "qtsvg" "qttools" "qttranslations" "qtwebdriver" "qtwebkit" "qtwebkit-examples" "qtwinextras" "qtx11extras" "qtxmlpatterns")
		for module in "${KOBO_REPOS[@]}" ; do
			# No qtwebdriver in 5.2
			if [[ "${module}" != "qtwebdriver" ]] ; then
				cd ${module}
				git remote add kobo https://github.com/kobolabs/${module}.git
				git fetch kobo
				git checkout kobo
				cd -
			fi
		done
	fi


	# NOTE: Disable LTO, because GCC 4.9 (c.f., the few NOTE on the subject)
	export CFLAGS="${NOLTO_CFLAGS}"
	export CXXFLAGS="${NOLTO_CFLAGS}"

	# We'll need a dedicated qmake specs... (.c.f, https://github.com/kobolabs/qtbase/blob/kobo/mkspecs/linux-armv7-kobo-g%2B%2B/qmake.conf)
	# Or, as it's most likely less hackish, https://github.com/qt/qtbase/blob/5.12/mkspecs/devices/linux-imx6-g%2B%2B/qmake.conf
	# We'll be liberally taking inspiration from both.
	# We use linux-arm-gnueabi-g++ as a base
	cp -av qtbase/mkspecs/linux-arm-gnueabi-g++ qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++
	sed -e "s/arm-linux-gnueabi-/${CROSS_TC}-/g" -i qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	sed -e '/load(qt_config)/d' -i qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo "" >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo '# modifications to gcc-base.conf' >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo "QMAKE_AR_LTCG           = ${CROSS_TC}-gcc-ar cqs" >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo "QMAKE_NM_LTCG           = ${CROSS_TC}-gcc-nm -P" >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo "" >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo "QMAKE_CFLAGS           += -isystem${TC_BUILD_DIR}/include" >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo "QMAKE_CXXFLAGS         += -isystem${TC_BUILD_DIR}/include" >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo "QMAKE_LFLAGS           += -L${TC_BUILD_DIR}/lib" >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo "" >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo "KOBO_CFLAGS             = -march=armv7-a -mtune=cortex-a8 -mfpu=neon -mfloat-abi=hard -mthumb" >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo 'QMAKE_CFLAGS           += $$KOBO_CFLAGS' >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo 'QMAKE_CXXFLAGS         += $$KOBO_CFLAGS' >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo 'QMAKE_LFLAGS           += -Wl,--as-needed' >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	# NOTE: -c++11 doesn't apply during configure's tests, which is a fatal mistake for proper ICU handling (as it requires C++11)...
	echo 'QMAKE_CXXFLAGS         += -std=c++11' >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo 'QMAKE_LFLAGS           += -std=c++11' >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	#echo 'QMAKE_OBJCXXFLAGS_PRECOMPILE += -std=c++11' >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo "" >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo 'QMAKE_CFLAGS_RELEASE   += -O3 -fomit-frame-pointer -frename-registers -fweb' >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo "" >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo 'QMAKE_CXXFLAGS_RELEASE += -O3 -fomit-frame-pointer -frename-registers -fweb' >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo "" >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	# For SQLCipher (https://github.com/kobolabs/qtbase/commit/c6113d551d9a09f69ddda66381dce2e85c01c37e)
	echo "QT_CFLAGS_SQLITE        = -I${TC_BUILD_DIR}/include/sqlcipher" >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo 'QT_LFLAGS_SQLITE        = -lsqlcipher -lcrypto -lz' >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo "" >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo "load(qt_config)" >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf

	# pkg-config shenanigans... Qt *wants* PKG_CONFIG_SYSROOT_DIR to be set or it refuses using pkg-config when cross-compiling...
	# So, cobble something together while actually relying on pkg-config's --define-prefix to do the right thing automagically.
	export PKG_CONFIG_SYSROOT_DIR="/."
	export PKG_CONFIG="pkg-config --define-prefix"

	# That one's just because the configure test drops bits of pkg-config's include folders, somehow...
	ln -sf ../../../lib/dbus-1.0/include/dbus/dbus-arch-deps.h ${TC_BUILD_DIR}/include/dbus-1.0/dbus/dbus-arch-deps.h

	# Merge (most) of the changes from qtbase/config.tests/unix/compile.test up to Qt 5.7 to get a slightly less broken configure (i.e., it actually honors pkg-config)
	cd qtbase
	if [[ "${TC_WANT_QT_KOBO}" == "false" ]] ; then
		patch -p1 < ${SCRIPT_BASE_DIR}/qtbase-5.2-configure-fix.patch
		# Because I keep seeing awk warnings, try switching to nawk, and merge a few awk-adjacent commits...
		patch -p1 < ${SCRIPT_BASE_DIR}/qtbase-5.2-configure-fix-2.patch
		# NOTE: And a round of applause for git bisect, which pinpointed *this* as the commit that actually fixed the buildsystem.
		#       Yeah. Pretty much never was going to catch that one on my own...
		#       https://github.com/qt/qtbase/commit/c35a3f519007af44c3b364b9af86f6a336f6411b
		#       FWIW, the first working release was v5.4.0...
		patch -p1 < ${SCRIPT_BASE_DIR}/qtbase-c35a3f519007af44c3b364b9af86f6a336f6411b.patch
	else
		# And all three of those rolled into one, and rebased against the Kobo branch
		patch -p1 < ${SCRIPT_BASE_DIR}/qtbase-Kobo-configure-fixes.patch
		# As of 4cc8c5e1be7702078509ad8bad2a7eaec8da346c (Sep 20, 2018), Kobo's qtwebkit branch doesn't build without a little help...
		cd ../qtwebkit
		patch -p1 < ${SCRIPT_BASE_DIR}/qtwebkit-kobo-buildfix.patch
	fi
	cd ..

	# NOTE: Apparently shit happens if the env isn't clear...
	unset CPPFLAGS CFLAGS CXXFLAGS LDFLAGS CROSS_PREFIX AR RANLIB NM XC_LINKTOOL_CFLAGS
	# We do want to keep --as-needed in there, otherwise some host tools get linked against useless crap (namely, the extra libs we enforce via configure's -l flag)...
	# We also apparently need to keep the right -L in here (essentially duplicating our target qmake specs' QMAKE_LFLAGS), or Qt libs fail to link because everything is terrible...
	export LDFLAGS="-std=c++11 -L${TC_BUILD_DIR}/lib -Wl,--as-needed"

	./configure -prefix ${TC_BUILD_DIR} -release -nomake tests -nomake examples -no-compile-examples -confirm-license -opensource -c++11 -shared -accessibility -pkg-config -system-zlib -mtdev -system-libpng -system-libjpeg -openssl -qt-pcre -no-xinput2 -no-xcb-xlib -no-glib -gui -widgets -no-rpath -optimized-qmake -no-nis -no-cups -no-iconv -icu -no-fontconfig -strip -no-pch -dbus-linked -no-xcb -no-eglfs -no-directfb -linuxfb -no-kms -platform linux-g++ -xplatform linux-arm-nickel-gnueabihf-g++ -no-opengl -no-system-proxies -no-warnings-are-errors -qt-freetype -qt-harfbuzz -R /usr/local/Qt-5.2.1-arm/lib -l z -l png -l icui18n -l icuuc -l icudata -l dbus-1 -v
	make ${JOBSFLAGS}
	make install

	export PKG_CONFIG="${BASE_PKG_CONFIG}"
	unset PKG_CONFIG_SYSROOT_DIR
	export CFLAGS="${NOLTO_CFLAGS}"
	export CXXFLAGS="${NOLTO_CFLAGS}"
	export LDFLAGS="${BASE_LDFLAGS}"
	# NOTE: We're done building stuff here, but, if we weren't, we'd need to re-set all the stuff we've unset to avoid breaking Qt's configure script...

	# NOTE: qmake & friends (moc, uic, etc.) get installed in the target's sysroot, but they're actually for the host (i.e., x86_64).
	#       We'll symlink them somewhere where they won't be mixed w/ ARM binaries.
	# NOTE: We can't actually move them, as qmake appears to hardcode the path to moc & co to ${prefix}/bin despite qt.conf shenanigans...
	mkdir -p "${TC_BUILD_WD}/${CROSS_TC}/bin"
	native_arch="$(uname -m)"
	# x86_64 -> x86-64 to match file's output
	native_arch="${native_arch/_/-}"
	for my_bin in ${TC_BUILD_DIR}/bin/* ; do
		file "${my_bin}" | grep -q "${native_arch}" && ln -sf "../${CROSS_TC}/sysroot/usr/bin/${my_bin##*/}" "${TC_BUILD_WD}/${CROSS_TC}/bin/"
	done
	unset native_arch
fi

####
####
# NOTE: Everything below targets a recent Qt 5 version, which is nice, but not what we wanted :D.
#       On the upside, it actually works without having to backport anything, so, that's a plus.
####
####

if [[ "${TC_WANT_QT_LTS}" == "true" ]] ; then
	# And now for an up-to-date Qt...
	echo "* Building Qt 5.14. . ."
	echo ""
	cd ..
	rm -rf qt5
	until git clone -b 5.14 --single-branch --depth 1 https://github.com/qt/qt5.git ; do
		rm -rf qt5
		sleep 15
	done
	cd qt5
	update_title_info
	./init-repository

	# We'll need a dedicated qmake specs... (.c.f, https://github.com/kobolabs/qtbase/blob/kobo/mkspecs/linux-armv7-kobo-g%2B%2B/qmake.conf)
	# Or, as it's most likely less hackish, https://github.com/qt/qtbase/blob/5.12/mkspecs/devices/linux-imx6-g%2B%2B/qmake.conf
	# We'll be liberally taking inspiration from both.
	# We use linux-arm-gnueabi-g++ as a base
	cp -av qtbase/mkspecs/linux-arm-gnueabi-g++ qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++
	sed -e "s/arm-linux-gnueabi-/${CROSS_TC}-/g" -i qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	sed -e '/load(qt_config)/d' -i qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo "" >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo '# modifications to gcc-base.conf' >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo "QMAKE_AR_LTCG           = ${CROSS_TC}-gcc-ar cqs" >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo "QMAKE_NM_LTCG           = ${CROSS_TC}-gcc-nm -P" >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo "" >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo "QMAKE_CFLAGS           += -isystem${TC_BUILD_DIR}/include" >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo "QMAKE_CXXFLAGS         += -isystem${TC_BUILD_DIR}/include" >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo "QMAKE_LFLAGS           += -L${TC_BUILD_DIR}/lib" >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo "" >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo "KOBO_CFLAGS             = -march=armv7-a -mtune=cortex-a8 -mfpu=neon -mfloat-abi=hard -mthumb" >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo 'QMAKE_CFLAGS           += $$KOBO_CFLAGS' >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo 'QMAKE_CXXFLAGS         += $$KOBO_CFLAGS' >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo 'QMAKE_LFLAGS           += -Wl,--as-needed' >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo "" >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo 'QMAKE_CFLAGS_RELEASE   += -O3 -fomit-frame-pointer -frename-registers -fweb' >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo "" >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo 'QMAKE_CXXFLAGS_RELEASE += -O3 -fomit-frame-pointer -frename-registers -fweb' >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo "" >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf
	echo "load(qt_config)" >> qtbase/mkspecs/linux-arm-nickel-gnueabihf-g++/qmake.conf

	# c.f., b.g.o/703306
	patch -p1 < ${PORTAGE_DIR}/dev-qt/qtcore/files/qtcore-5.14.1-cmake-macro-backward-compat.patch

	# pkg-config shenanigans... Qt *wants* PKG_CONFIG_SYSROOT_DIR to be set or it refuses using pkg-config when cross-compiling...
	# So, cobble something together while actually relying on pkg-config's --define-prefix to do the right thing automagically.
	export PKG_CONFIG_SYSROOT_DIR="/."
	export PKG_CONFIG="pkg-config --define-prefix"

	./configure -prefix "${TC_BUILD_DIR}" -release -nomake tests -nomake examples -no-compile-examples -confirm-license -opensource -c++std c++14 -shared -accessibility -pkg-config -system-zlib -no-mtdev -system-libpng -system-libjpeg -openssl -qt-pcre -no-xcb-xlib -no-glib -gui -widgets -no-rpath -optimized-qmake -no-cups -no-iconv -icu -no-fontconfig -strip -no-pch -dbus-linked -no-vulkan -no-xcb -no-eglfs -no-directfb -linuxfb -no-kms -platform linux-g++ -xplatform linux-arm-nickel-gnueabihf-g++ -no-mng -no-opengl -no-system-proxies -no-warnings-are-errors -qt-freetype -qt-harfbuzz -no-use-gold-linker -no-ltcg -no-feature-statx -recheck-all -I ${TC_BUILD_DIR}/include -L ${TC_BUILD_DIR}/lib -v
	make ${JOBSFLAGS}
	make install

	export PKG_CONFIG="${BASE_PKG_CONFIG}"
	unset PKG_CONFIG_SYSROOT_DIR

	# NOTE: qmake & friends (moc, uic, etc.) get installed in the target's sysroot, but they're actually for the host (i.e., x86_64).
	#       We'll symlink them somewhere where they won't be mixed w/ ARM binaries.
	# NOTE: We can't actually move them, as qmake appears to hardcode the path to moc & co to ${prefix}/bin despite qt.conf shenanigans...
	mkdir -p "${TC_BUILD_WD}/${CROSS_TC}/bin"
	native_arch="$(uname -m)"
	# x86_64 -> x86-64 to match file's output
	native_arch="${native_arch/_/-}"
	for my_bin in ${TC_BUILD_DIR}/bin/* ; do
		file "${my_bin}" | grep -q "${native_arch}" && ln -sf "../${CROSS_TC}/sysroot/usr/bin/${my_bin##*/}" "${TC_BUILD_WD}/${CROSS_TC}/bin/"
	done
	unset native_arch

	# NOTE: Let's try to bother w/ the up-to-date out-of-tree QtWebKit, which requires a bunch of extra deps...
	#      c.f., https://github.com/qtwebkit/qtwebkit/wiki/Building-QtWebKit-on-Linux
	#            We're basically missing SQLite, libxml2 & libxslt here.

	echo "* Building libxml2 . . ."
	echo ""
	LIBXML2_VERSION="2.9.9"
	cd ..
	tar -I pigz -xvf ${PORTAGE_DIR}/distfiles/libxml2-2.9.9.tar.gz
	cd libxml2-${LIBXML2_VERSION}
	update_title_info
	tar -xvJf ${PORTAGE_DIR}/distfiles/libxml2-2.9.9-patchset.tar.xz
	# Gentoo Patches...
	for patchfile in patches/* ; do
		# Try to detect if we need p0 or p1...
		if grep -q 'diff --git' "${patchfile}" ; then
			echo "Applying ${patchfile} w/ p1 . . ."
			patch -p1 < ${patchfile}
		else
			echo "Applying ${patchfile} w/ p0 . . ."
			patch -p0 < ${patchfile}
		fi
	done
	patch -p1 < ${PORTAGE_DIR}/dev-libs/libxml2/files/libxml2-2.7.1-catalog_path.patch
	patch -p1 < ${PORTAGE_DIR}/dev-libs/libxml2/files/libxml2-2.9.2-python-ABIFLAG.patch
	patch -p1 < ${PORTAGE_DIR}/dev-libs/libxml2/files/libxml2-2.9.8-out-of-tree-test.patch
	patch -p1 < ${PORTAGE_DIR}/dev-libs/libxml2/files/2.9.9-python3-unicode-errors.patch
	autoreconf -fi
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-static --enable-shared --without-run-debug --without-mem-debug --without-lzma --disable-ipv6 --without-readline --without-history --without-python --with-icu
	make ${JOBSFLAGS} V=1
	make install

	echo "* Building libxslt . . ."
	echo ""
	LIBXSLT_VERSION="1.1.33"
	LIBEXSLT_SOVER="0.8.20"
	cd ..
	tar -I pigz -xvf ${PORTAGE_DIR}/distfiles/libxslt-1.1.33.tar.gz
	cd libxslt-${LIBXSLT_VERSION}
	update_title_info
	# Gentoo Patches...
	patch -p1 < ${PORTAGE_DIR}/dev-libs/libxslt/files/1.1.32-simplify-python.patch
	patch -p1 < ${PORTAGE_DIR}/dev-libs/libxslt/files/libxslt-1.1.28-disable-static-modules.patch
	patch -p1 < ${PORTAGE_DIR}/distfiles/libxslt-1.1.33-CVE-2019-11068.patch
	autoreconf -fi
	env ac_cv_path_ac_pt_XML_CONFIG=${TC_BUILD_DIR}/bin/xml2-config PKG_CONFIG="pkg-config --static" ./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-static --enable-shared --without-crypto --without-debug --without-mem-debug --without-python
	make ${JOBSFLAGS} V=1
	make install

	echo "* Building SQLite3 . . ."
	echo ""
	SQLITE_SOVER="0.8.6"
	SQLITE_VER="3310100"
	cd ..
	wget https://sqlite.org/2020/sqlite-src-${SQLITE_VER}.zip -O sqlite-src-${SQLITE_VER}.zip
	unzip sqlite-src-${SQLITE_VER}.zip
	cd sqlite-src-${SQLITE_VER}
	update_title_info
	# LTO makefile compat...
	patch -p1 < ${SCRIPT_BASE_DIR}/sqlite-fix-Makefile-for-lto.patch
	autoreconf -fi
	# Enable some extra features...
	export CPPFLAGS="${BASE_CPPFLAGS} -DNDEBUG -D_REENTRANT=1 -D_GNU_SOURCE"
	export CPPFLAGS="${CPPFLAGS} -DSQLITE_ENABLE_COLUMN_METADATA -DSQLITE_ENABLE_RTREE -DSQLITE_SOUNDEX -DSQLITE_ENABLE_UNLOCK_NOTIFY"
	# And a few of the recommended build options from https://sqlite.org/compile.html (we only leave shared cache enabled, just in case...)
	# NOTE: We can't use SQLITE_OMIT_DECLTYPE with SQLITE_ENABLE_COLUMN_METADATA
	# NOTE: The Python SQLite module also prevents us from using SQLITE_OMIT_PROGRESS_CALLBACK as well as SQLITE_OMIT_DEPRECATED
	export CPPFLAGS="${CPPFLAGS} -DSQLITE_DEFAULT_MEMSTATUS=0 -DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1 -DSQLITE_LIKE_DOESNT_MATCH_BLOBS -DSQLITE_MAX_EXPR_DEPTH=0 -DSQLITE_USE_ALLOCA"
	export CPPFLAGS="${CPPFLAGS} -DSQLITE_ENABLE_ICU"
	# Need to tweak that a bit to link properly against ICU...
	sed -e "s/LIBS = @LIBS@/& -licui18n -licuuc -licudata/" -i Makefile.in
	# Setup our Python rpath.
	# SQLite doesn't want to be built w/ -ffast-math...
	export CFLAGS="${NOLTO_CFLAGS/-ffast-math /}"
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-static --disable-static-shell --enable-shared --disable-amalgamation --enable-threadsafe --enable-dynamic-extensions --disable-readline --enable-fts5 --enable-json1 --disable-tcl --disable-releasemode
	# NOTE: We apparently need to make sure the header is generated first, or parallel compilation goes kablooey...
	make -j1 sqlite3.h
	make ${JOBSFLAGS}
	make install
	export CFLAGS="${NOLTO_CFLAGS}"
	export CPPFLAGS="${BASE_CPPFLAGS}"

	echo "* Building QtWebKit. . ."
	echo ""
	cd ..
	rm -rf qtwebkit
	# We're also going to need a bucketload of free space...
	rm -rf dbus-* expat-* icu icu-host libjpeg-turbo-* libpng-* libxml2-* libxslt-* openssl-* sqlite-src-* qt5 zlib-ng
	# NOTE: LTO is iffy w/ GCC 4.9, let's kill it, see if that fixes a few undef ref errors
	#       To no-one's surprise, it does. Oh, how I haven't missed you, GCC 4.9...
	export CFLAGS="${NOLTO_CFLAGS}"
	export CXXFLAGS="${NOLTO_CFLAGS}"
	until git clone -b 5.212 --single-branch --depth 1 https://github.com/qt/qtwebkit.git ; do
		rm -rf qtwebkit
		sleep 15
	done
	cd qtwebkit
	update_title_info
	mkdir build
	cd build
	# NOTE: Might need -fno-strict-aliasing, according to the Gentoo ebuild (b.g.o/547224)
	${CMAKE} -G Ninja -DPORT=Qt -DENABLE_API_TESTS=OFF -DENABLE_TOOLS=OFF -DENABLE_GEOLOCATION=OFF -DUSE_GSTREAMER=OFF -DUSE_LIBHYPHEN=OFF -DENABLE_JIT=ON -DUSE_QT_MULTIMEDIA=ON -DENABLE_NETSCAPE_PLUGIN_API=OFF -DENABLE_OPENGL=OFF -DENABLE_PRINT_SUPPORT=OFF -DENABLE_DEVICE_ORIENTATION=ON -DENABLE_WEBKIT2=OFF -DENABLE_X11_TARGET=OFF -DCMAKE_BUILD_TYPE=Release ..
	ninja -v
	ninja -v install
	export CFLAGS="${NOLTO_CFLAGS}"
	export CXXFLAGS="${NOLTO_CFLAGS}"
fi

# If we're not on Gentoo, clean up our faux Portage tree
if [[ ! -f "/etc/gentoo-release" ]] ; then
	rm -rf "${PORTAGE_DIR}"
fi
