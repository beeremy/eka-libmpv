#!/bin/bash -e
# libmpv pour macOS (arm64), en LGPL, pour la version Mac d'EKA Player.
#
# Mêmes versions que la construction Android (../include/depinfo.sh). mpv est construit avec -Dgpl=false et FFmpeg sans
# --enable-gpl : la construction échoue si un composant GPL est activé. libmpv et les bibliothèques FFmpeg sont des
# .dylib (liaison dynamique, remplaçables) ; les autres dépendances sont liées statiquement dedans.
#
# Usage : buildscripts/macos/build.sh [dossier de travail]   (outils : meson ninja nasm pkg-config cmake)
# Résultat : <travail>/dist/libmpv-macos-arm64.zip (bibliothèques) et <travail>/dist/sources-macos.tar.gz (sources).

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/../include/depinfo.sh"

work="${1:-$here/work}"
src="$work/src"
prefix="$work/prefix"
dist="$work/dist"
mkdir -p "$src" "$prefix" "$dist"

export MACOSX_DEPLOYMENT_TARGET=12.0
export CFLAGS="-O2 -arch arm64 -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET -I$prefix/include"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-arch arm64 -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET -L$prefix/lib"
# Seules nos bibliothèques : jamais celles de Homebrew (certaines y sont construites en GPL).
export PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig"
unset PKG_CONFIG_PATH
jobs=$(sysctl -n hw.ncpu)

fetch() { # nom url
	[ -d "$src/$1" ] && return
	echo "== téléchargement de $1"
	local archive="$src/$1.archive"
	curl -fL --retry 3 -o "$archive" "$2"
	mkdir -p "$src/$1"
	tar -xf "$archive" -C "$src/$1" --strip-components=1
	rm "$archive"
}

meson_static() { # dossier options…
	local dir="$1"; shift
	(cd "$src/$dir" && meson setup build --prefix="$prefix" --libdir=lib --buildtype=release --default-library=static \
		--wipe "$@" && ninja -C build -j"$jobs" && ninja -C build install)
}

fetch mbedtls "https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-$v_mbedtls/mbedtls-$v_mbedtls.tar.bz2"
fetch dav1d "https://code.videolan.org/videolan/dav1d/-/archive/$v_dav1d/dav1d-$v_dav1d.tar.gz"
fetch ffmpeg "https://ffmpeg.org/releases/ffmpeg-$v_ffmpeg.tar.xz"
fetch freetype "https://download.savannah.gnu.org/releases/freetype/freetype-${v_freetype//-/.}.tar.xz"
fetch fribidi "https://github.com/fribidi/fribidi/releases/download/v$v_fribidi/fribidi-$v_fribidi.tar.xz"
fetch harfbuzz "https://github.com/harfbuzz/harfbuzz/releases/download/$v_harfbuzz/harfbuzz-$v_harfbuzz.tar.xz"
fetch libunibreak "https://github.com/adah1972/libunibreak/releases/download/libunibreak_$v_libunibreak/libunibreak-${v_libunibreak//_/.}.tar.gz"
fetch libass "https://github.com/libass/libass/releases/download/$v_libass/libass-$v_libass.tar.xz"
fetch mpv "https://github.com/mpv-player/mpv/archive/v$v_mpv.tar.gz"
if [ ! -d "$src/libplacebo" ]; then
	git clone --depth 1 --recursive -b "v$v_libplacebo" https://code.videolan.org/videolan/libplacebo.git "$src/libplacebo"
fi

echo "== mbedtls"
(cd "$src/mbedtls" && cmake -S . -B build -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_OSX_ARCHITECTURES=arm64 -DENABLE_PROGRAMS=OFF -DENABLE_TESTING=OFF -DUSE_SHARED_MBEDTLS_LIBRARY=OFF \
	&& cmake --build build -j"$jobs" && cmake --install build)

echo "== dav1d"
meson_static dav1d -Denable_tools=false -Denable_tests=false

echo "== FFmpeg (LGPL)"
(cd "$src/ffmpeg" && ./configure --prefix="$prefix" --enable-shared --disable-static --disable-programs --disable-doc \
	--disable-debug --enable-version3 --disable-nonfree --enable-mbedtls --enable-libdav1d --enable-videotoolbox \
	--enable-audiotoolbox --arch=arm64 --extra-cflags="$CFLAGS" --extra-ldflags="$LDFLAGS" --install-name-dir='@rpath' \
	&& make -j"$jobs" && make install)
grep -q "#define CONFIG_GPL 0" "$src/ffmpeg/config.h" || { echo "FFmpeg construit en GPL : refusé"; exit 1; }

echo "== freetype, fribidi, harfbuzz, libunibreak, libass"
meson_static freetype -Dharfbuzz=disabled -Dpng=disabled -Dbrotli=disabled -Dbzip2=disabled -Dzlib=disabled
meson_static fribidi -Ddocs=false -Dtests=false -Dbin=false
meson_static harfbuzz -Dtests=disabled -Ddocs=disabled -Dglib=disabled -Dgobject=disabled -Dcairo=disabled \
	-Dicu=disabled -Dfreetype=enabled -Dutilities=disabled
(cd "$src/libunibreak" && ./configure --prefix="$prefix" --disable-shared --enable-static && make -j"$jobs" && make install)
meson_static libass -Dfontconfig=disabled -Dcoretext=enabled -Dlibunibreak=enabled -Dtest=disabled -Dprofile=disabled

echo "== libplacebo"
meson_static libplacebo -Dvulkan=disabled -Dopengl=enabled -Dd3d11=disabled -Ddemos=false -Dtests=false \
	-Dshaderc=disabled -Dglslang=disabled -Dlcms=disabled -Dxxhash=disabled -Dunwind=disabled

# Sans Cocoa (qui exige Swift depuis mpv 0.42) : l'app dessine l'image elle-même par l'API de rendu OpenGL, et le
# décodage matériel passe par VideoToolbox avec copie en mémoire (hwdec=videotoolbox-copy).
echo "== mpv (LGPL)"
(cd "$src/mpv" && meson setup build --prefix="$prefix" --libdir=lib --buildtype=release --default-library=shared --wipe \
	-Dgpl=false -Dlibmpv=true -Dcplayer=false -Dtests=false -Dlua=disabled -Djavascript=disabled -Dlibarchive=disabled \
	-Dlcms2=disabled -Dmanpage-build=disabled -Dhtml-build=disabled -Dpdf-build=disabled -Dswift-build=disabled \
	-Dmacos-cocoa-cb=disabled -Dcocoa=disabled -Dgl-cocoa=disabled -Dvideotoolbox-gl=disabled -Dcoreaudio=enabled \
	-Djpeg=disabled -Dzimg=disabled -Duchardet=disabled -Drubberband=disabled -Dvapoursynth=disabled \
	&& ninja -C build -j"$jobs" && ninja -C build install)
grep -Eq "#define HAVE_GPL 0" "$src/mpv/build/config.h" || { echo "mpv construit en GPL : refusé"; exit 1; }

echo "== assemblage"
out="$work/out"
rm -rf "$out" && mkdir -p "$out"
cp "$prefix"/lib/libmpv.2.dylib "$out/"
# Une copie par bibliothèque FFmpeg, sous le nom référencé par les autres (version majeure : libavcodec.62.dylib).
for file in "$prefix"/lib/lib*.dylib; do
	name="$(basename "$file")"
	case "$name" in
		libav*|libsw*) [[ "$name" =~ ^lib[a-z]+\.[0-9]+\.dylib$ ]] && cp -L "$file" "$out/" ;;
	esac
done
# Noms d'installation relatifs : les bibliothèques se trouvent les unes les autres à côté de libmpv.
for file in "$out"/*.dylib; do
	install_name_tool -id "@rpath/$(basename "$file")" "$file"
	otool -L "$file" | awk 'NR>1 {print $1}' | while read -r dep; do
		case "$dep" in
			@rpath/*|"$prefix"/*) install_name_tool -change "$dep" "@loader_path/$(basename "$dep")" "$file" ;;
		esac
	done
	codesign --force --sign - "$file"
done
# Aucune dépendance hors du système et de ce dossier (Homebrew en particulier).
for file in "$out"/*.dylib; do
	# Ligne 1 : le fichier ; ligne 2 : son propre nom (@rpath/…) ; ensuite ses dépendances.
	if otool -L "$file" | tail -n +3 | awk '$1 !~ /^(@loader_path|\/usr\/lib|\/System)/ {print; bad=1} END {exit bad}'; then
		:
	else
		echo "dépendance inattendue dans $(basename "$file") : refusé"; exit 1
	fi
done
echo "dépendances vérifiées"

rm -f "$dist"/*
(cd "$out" && zip -q -r "$dist/libmpv-macos-arm64.zip" .)
# Sources exactes (LGPL) : celles téléchargées, sans les dossiers de construction, et les scripts de ce dépôt.
tar -czf "$dist/sources-macos.tar.gz" --exclude='build' --exclude='.git' --exclude='work' -C "$work" src -C "$here/.." macos include
shasum -a 256 "$dist"/*.zip "$dist"/*.tar.gz
