#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

rm -rf niluje
mkdir niluje
cd niluje

rev=17194
files=(
    CMakeCross.txt
    kobo-nickel-sysroot.sh
    x-compile.sh
    zlib-ng-nerf-arm-hwcap.patch
    libpng-fix-Makefile-for-lto.patch
    qtbase-5.2-configure-fix.patch
    qtbase-5.2-configure-fix-2.patch
    qtbase-c35a3f519007af44c3b364b9af86f6a336f6411b.patch
    qtbase-Kobo-configure-fixes.patch
    qtwebkit-kobo-buildfix.patch
    sqlite-fix-Makefile-for-lto.patch
)

for fn in "${files[@]}"; do
    wget -O "${fn}" "https://svn.ak-team.com/svn/Configs/trunk/Kindle/Misc/${fn}?p=${rev}"
done
