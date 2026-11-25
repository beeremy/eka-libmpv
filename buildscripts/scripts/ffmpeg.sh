#!/bin/bash -e

. ../../include/depinfo.sh
. ../../include/path.sh

if [ "$1" == "build" ]; then
	true
elif [ "$1" == "clean" ]; then
	rm -rf _build$ndk_suffix
	exit 0
else
	exit 255
fi

mkdir -p _build$ndk_suffix
cd _build$ndk_suffix

cpu=armv7-a
[[ "$ndk_triple" == "aarch64"* ]] && cpu=armv8-a
[[ "$ndk_triple" == "x86_64"* ]] && cpu=generic
[[ "$ndk_triple" == "i686"* ]] && cpu="i686 --disable-asm"

cpuflags=
[[ "$ndk_triple" == "arm"* ]] && cpuflags="$cpuflags -mfpu=neon -mcpu=cortex-a8"

# EKA : FFmpeg en LGPL (pas de --enable-gpl). --enable-version3 est requis par mbedtls (Apache-2.0) :
# FFmpeg est alors sous LGPL-3.0-or-later. libpostproc (GPL uniquement) n'est pas construite.
../configure \
	--target-os=android --enable-cross-compile --cross-prefix=$ndk_triple- --cc=$CC \
	--arch=${ndk_triple%%-*} --cpu=$cpu --pkg-config=pkg-config --nm=llvm-nm \
	--extra-cflags="-I$prefix_dir/include $cpuflags" --extra-ldflags="-L$prefix_dir/lib" \
	--enable-{jni,mediacodec,mbedtls,libdav1d,libxml2} --disable-vulkan \
	--disable-static --enable-shared --enable-version3 \
	--disable-{stripping,doc,programs} \
	--disable-{muxers,encoders,devices,filters} \
	--disable-v4l2-m2m

make -j$cores

# Garde-fou : la compilation échoue si un composant GPL a été activé.
grep -q '^#define CONFIG_GPL 0' config.h || { echo 'FFmpeg construit avec du code GPL : refusé'; exit 1; }
make DESTDIR="$prefix_dir" install

ln -sf "$prefix_dir"/lib/libswresample.so "$native_dir"
ln -sf "$prefix_dir"/lib/libavutil.so "$native_dir"
ln -sf "$prefix_dir"/lib/libavcodec.so "$native_dir"
ln -sf "$prefix_dir"/lib/libavformat.so "$native_dir"
ln -sf "$prefix_dir"/lib/libswscale.so "$native_dir"
ln -sf "$prefix_dir"/lib/libavfilter.so "$native_dir"
ln -sf "$prefix_dir"/lib/libavdevice.so "$native_dir"
