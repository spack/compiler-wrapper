#!/bin/sh

export SPACK_COMPILER_WRAPPER_PATH="$PWD"
export SPACK_DEBUG_LOG_DIR="/tmp"
export SPACK_DEBUG_LOG_ID="bench"
export SPACK_SHORT_SPEC="py-torch@2.11.0%gcc@14.2.0 arch=linux-ubuntu24.04-aarch64"
export SPACK_SYSTEM_DIRS="/usr/*|/lib/*"
export SPACK_CXX="true"
export SPACK_CC="true"
export SPACK_FC="true"
export SPACK_F77="true"
export SPACK_CC_LINKER_ARG="-Wl,"
export SPACK_CC_RPATH_ARG="-Wl,-rpath,"
export SPACK_CXX_LINKER_ARG="-Wl,"
export SPACK_CXX_RPATH_ARG="-Wl,-rpath,"
export SPACK_FC_LINKER_ARG="-Wl,"
export SPACK_FC_RPATH_ARG="-Wl,-rpath,"
export SPACK_F77_LINKER_ARG="-Wl,"
export SPACK_F77_RPATH_ARG="-Wl,-rpath,"
export SPACK_CXX_HAS_FRANDOM_SEED=true
export SPACK_DTAGS_TO_ADD="--enable-new-dtags"
export SPACK_DTAGS_TO_STRIP="--disable-new-dtags"

_P="/home/software/spack/__spack_path_placeholder__/__spack_path_placeholder__/__spack_path_placeholder__/__spack_path_placeholder__/__spack_path_placeholder__/__spack_path_placeholder__/__spack_path_placeholder__/__spack_path_placeholder__/__spack_path_placeh/linux-aarch64"

export SPACK_MANAGED_DIRS="$_P/*"

# Hash generator: produces a fake 32-char hex from an index.
_h() {
    printf '%032x' "$1"
}

# Build large dependency lists to stress the wrapper.
_store_pkgs="python-3.13.2 py-numpy-2.4.1 py-setuptools-80.7.1 py-pyyaml-6.0.2 openblas-0.3.33 cuda-12.9.1 py-pip-24.2 py-wheel-0.43.0 py-cython-3.0.11 py-pybind11-2.13.6 py-typing-extensions-4.12.2 py-sympy-1.13.3 py-mpmath-1.3.0 py-filelock-3.16.1 py-jinja2-3.1.4 py-markupsafe-2.1.5 py-networkx-3.4.2 py-fsspec-2024.10.0 py-packaging-24.1 py-six-1.16.0 zlib-ng-2.2.2 bzip2-1.0.8 xz-5.4.6 zstd-1.5.6 openssl-3.3.2 sqlite-3.46.1 ncurses-6.5 readline-8.2 libffi-3.4.6 expat-2.6.4 gdbm-1.24 util-linux-uuid-2.40.2 tar-1.35 gettext-0.22.5 libiconv-1.17 pcre2-10.44 ca-certificates-2024 cmake-3.31.0 ninja-1.12.1"

_dep_pkgs="libxfixes-6.0.1 libxdamage-1.1.6 libxshmfence-1.3.2 libxxf86vm-1.1.5 libxcursor-1.2.3 libxcomposite-0.4.6 libxinerama-1.1.5 libxrandr-1.5.4 libxrender-0.9.11 libxext-1.3.6 libxi-1.8.2 libxtst-1.2.5 libxkbcommon-1.7.0 libxkbfile-1.1.3 libxmu-1.2.1 libxt-1.3.0 libxaw-1.0.16 libxpm-3.5.17 libxft-2.3.8 libxss-1.2.4 libx11-1.8.10 libxcb-1.17.0 libxau-1.0.11 libxdmcp-1.1.5 libxres-1.2.2 libxv-1.0.12 libxvmc-1.0.14 libpciaccess-0.18.1 libdrm-2.4.123 mesa-24.2.5 libglvnd-1.7.0 libglx-1.7.0 libegl-1.7.0 libgles-1.7.0 wayland-1.23.1 xorgproto-2024.1 xtrans-1.5.1 fontconfig-2.15.0 freetype-2.13.3 harfbuzz-10.0.1 libpng-1.6.44 libjpeg-turbo-3.0.4 libtiff-4.7.0 libwebp-1.4.0 giflib-5.2.2 librsvg-2.59.0 cairo-1.18.2 pixman-0.43.4 pango-1.54.0 fribidi-1.0.16 graphite2-1.3.14"

_idx=0
_store_include=""
_store_link=""
for _pkg in $_store_pkgs; do
    _hash=$(_h $_idx)
    _store_include="$_store_include$_P/$_pkg-$_hash/include:"
    _store_link="$_store_link$_P/$_pkg-$_hash/lib:"
    _idx=$((_idx + 1))
done

_dep_include=""
_dep_link=""
for _pkg in $_dep_pkgs; do
    _hash=$(_h $_idx)
    _dep_include="$_dep_include$_P/$_pkg-$_hash/include:"
    _dep_link="$_dep_link$_P/$_pkg-$_hash/lib:"
    _idx=$((_idx + 1))
done

export SPACK_STORE_INCLUDE_DIRS="${_store_include%:}"
export SPACK_STORE_LINK_DIRS="${_store_link%:}"
export SPACK_STORE_RPATH_DIRS="$SPACK_STORE_LINK_DIRS"

export SPACK_INCLUDE_DIRS="${_dep_include%:}"
export SPACK_LINK_DIRS="${_dep_link%:}"
export SPACK_RPATH_DIRS="$SPACK_LINK_DIRS"

export SPACK_COMPILER_IMPLICIT_RPATHS="\
$_P/gcc-16.1.0-a30491defb3c2a8a14f43c8c93ec2ef2/lib"

export SPACK_COMPILER_EXTRA_RPATHS="\
$_P/gcc-runtime-stuff-16.1.0-6bce6552b41bbeed94e4faee72dcbe96/lib"

export SPACK_CFLAGS=""
export SPACK_CXXFLAGS=""
export SPACK_FFLAGS=""
export SPACK_CPPFLAGS=""
export SPACK_LDFLAGS=""
export SPACK_LDLIBS=""
export SPACK_ALWAYS_CFLAGS=""
export SPACK_ALWAYS_CXXFLAGS=""
export SPACK_ALWAYS_CPPFLAGS=""
export SPACK_ALWAYS_FFLAGS=""
export SPACK_TARGET_ARGS_CC=""
export SPACK_TARGET_ARGS_CXX=""
export SPACK_TARGET_ARGS_FORTRAN=""
export SPACK_COMPILER_FLAGS_KEEP=""
export SPACK_COMPILER_FLAGS_REPLACE=""

# Warmup
./g++ -c foo.c -o foo.o

# Do a 1000 runs
N=1000
_start=$(date +%s)
_i=0
while [ $_i -lt $N ]; do
    ./g++ -c foo.c -o foo.o
    _i=$((_i + 1))
done
_end=$(date +%s)
_elapsed=$((_end - _start))
printf '%s runs in %ss (avg %sms)\n' "$N" "$_elapsed" "$((_elapsed * 1000 / N))"
