#!/bin/bash -e

. ../../include/depinfo.sh
. ../../include/path.sh

build=_build$ndk_suffix

if [ "$1" == "build" ]; then
	true
elif [ "$1" == "clean" ]; then
	rm -rf $build
	exit 0
else
	exit 255
fi

unset CC CXX # meson wants these unset

# EKA : mpv en LGPL-2.1-or-later (-Dgpl=false).
meson setup $build --cross-file "$prefix_dir"/crossfile.txt \
	--default-library shared \
	-Diconv=disabled -D{lua,libcurl}=enabled \
	-Dlibmpv=true -Dcplayer=false \
	-Dgpl=false \
	-Dmanpage-build=disabled

ninja -C $build -j$cores

# Garde-fou EKA : mpv doit être construit en LGPL.
grep -Eq "^#define HAVE_GPL 0" $build/config.h || { echo 'mpv construit en GPL : refusé'; exit 1; }
DESTDIR="$prefix_dir" ninja -C $build install

ln -sf "$prefix_dir"/lib/libmpv.so "$native_dir"
