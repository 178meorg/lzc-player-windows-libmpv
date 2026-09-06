#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BUILD_ROOT="${BUILD_ROOT:-${ROOT_DIR}/build}"
SRC_ROOT="${SRC_ROOT:-${BUILD_ROOT}/src}"
WORK_ROOT="${WORK_ROOT:-${BUILD_ROOT}/work}"
PREFIX="${PREFIX:-${BUILD_ROOT}/install}"

mkdir -p "${SRC_ROOT}" "${WORK_ROOT}" "${PREFIX}"

export ROOT_DIR BUILD_ROOT SRC_ROOT WORK_ROOT PREFIX
export PATH="${PREFIX}/bin:/mingw64/bin:${PATH}"
export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PREFIX}/share/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"
export CMAKE_PREFIX_PATH="${PREFIX}${CMAKE_PREFIX_PATH:+;${CMAKE_PREFIX_PATH}}"
export CPPFLAGS="-I${PREFIX}/include ${CPPFLAGS:-}"
export LDFLAGS="-L${PREFIX}/lib ${LDFLAGS:-}"

source "${ROOT_DIR}/config/versions.env"

JOBS="${JOBS:-$(nproc)}"

clone_git() {
    local name="$1" url="$2" ref="$3"
    local source="${SRC_ROOT}/${name}"
    if [[ ! -d "${source}/.git" ]]; then
        rm -rf "${source}"
        git clone --depth 1 --branch "${ref}" "${url}" "${source}"
    fi
    printf '%s\n' "${source}"
}

build_autotools() {
    local name="$1" url="$2" ref="$3" configure_args="$4"
    local source
    source="$(clone_git "${name}" "${url}" "${ref}")"
    cd "${source}"
    make distclean >/dev/null 2>&1 || true
    ./autogen.sh >/dev/null 2>&1 || true
    ./configure \
        --prefix="${PREFIX}" \
        --libdir="${PREFIX}/lib" \
        --enable-static \
        --disable-shared \
        ${configure_args}
    make -j"${JOBS}"
    make install
}

build_cmake() {
    local name="$1" url="$2" ref="$3" source_subdir="$4" cmake_args="$5"
    local source="${SRC_ROOT}/${name}"
    local build="${WORK_ROOT}/${name}"
    source="$(clone_git "${name}" "${url}" "${ref}")"
    rm -rf "${build}"
    cmake -S "${source}/${source_subdir}" -B "${build}" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DBUILD_SHARED_LIBS=OFF \
        ${cmake_args}
    cmake --build "${build}" -j"${JOBS}"
    cmake --install "${build}"
}

build_configure() {
    local name="$1" url="$2" ref="$3" configure_args="$4"
    local source
    source="$(clone_git "${name}" "${url}" "${ref}")"
    cd "${source}"
    make distclean >/dev/null 2>&1 || true
    ./configure \
        --prefix="${PREFIX}" \
        --libdir="${PREFIX}/lib" \
        --enable-static \
        --disable-shared \
        ${configure_args}
    make -j"${JOBS}"
    make install
}

build_meson() {
    local name="$1" url="$2" ref="$3" meson_args="$4"
    local source="${SRC_ROOT}/${name}"
    local build="${WORK_ROOT}/${name}"
    source="$(clone_git "${name}" "${url}" "${ref}")"
    rm -rf "${build}"
    meson setup "${build}" "${source}" \
        --prefix="${PREFIX}" \
        --libdir=lib \
        --buildtype=release \
        --default-library=static \
        ${meson_args}
    meson compile -C "${build}"
    meson install -C "${build}"
}

build_lame() {
    local archive="${SRC_ROOT}/lame-${LAME_VERSION}.tar.gz"
    local source="${SRC_ROOT}/lame-${LAME_VERSION}"
    if [[ ! -f "${archive}" ]]; then
        curl -fsSL --retry 5 -o "${archive}" "https://downloads.sourceforge.net/lame/lame-${LAME_VERSION}.tar.gz"
    fi
    [[ -d "${source}" ]] || tar -xf "${archive}" -C "${SRC_ROOT}"
    cd "${source}"
    make distclean >/dev/null 2>&1 || true
    ./configure --prefix="${PREFIX}" --libdir="${PREFIX}/lib" --enable-static --disable-shared --disable-frontend
    make -j"${JOBS}"
    make install
}

build_lame
build_autotools opus https://github.com/xiph/opus.git "v${OPUS_VERSION}" "--disable-extra-programs"
build_autotools ogg https://github.com/xiph/ogg.git "v${OGG_VERSION}" ""
build_autotools vorbis https://github.com/xiph/vorbis.git "v${VORBIS_VERSION}" ""
build_autotools speex https://github.com/xiph/speexdsp.git "SpeexDSP-${SPEEX_VERSION}" ""
build_autotools soxr https://git.code.sf.net/p/soxr/code master ""
build_configure vpx https://chromium.googlesource.com/webm/libvpx "v${LIBVPX_VERSION}" "--disable-examples --disable-tools --disable-unit-tests --enable-vp9-highbitdepth --as=yasm"
build_meson dav1d https://code.videolan.org/videolan/dav1d "${DAV1D_VERSION}" "-Dbuild_tests=false -Dbuild_tools=false -Denable_tools=false"
build_cmake aom https://aomedia.googlesource.com/aom "v${AOM_VERSION}" . "-DAOM_BUILD_APPS=OFF -DENABLE_TESTS=OFF -DENABLE_TOOLS=OFF -DENABLE_EXAMPLES=OFF -DENABLE_DOCS=OFF -DENABLE_NASM=ON"
build_cmake SVT-AV1 https://gitlab.com/AOMediaCodec/SVT-AV1 "v${SVTAV1_VERSION}" . "-DBUILD_APPS=OFF -DBUILD_TESTING=OFF"
build_cmake webp https://github.com/webmproject/libwebp "v${LIBWEBP_VERSION}" . "-DWEBP_BUILD_ANIM_UTILS=OFF -DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_DWEBP=OFF -DWEBP_BUILD_EXTRAS=OFF -DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF -DWEBP_BUILD_WEBPMUX=OFF -DWEBP_BUILD_TESTS=OFF"
build_configure x264 https://code.videolan.org/videolan/x264.git stable "--host=x86_64-w64-mingw32 --cross-prefix=x86_64-w64-mingw32- --disable-cli"
build_cmake x265 https://bitbucket.org/multicoreware/x265_git "${X265_VERSION}" source "-DENABLE_CLI=OFF"

for library in libmp3lame opus ogg vorbis speexdsp soxr vpx dav1d aom SvtAv1Enc libwebp x264 x265; do
    pkg-config --exists "${library}" || {
        echo "Missing pkg-config package: ${library}" >&2
        exit 1
    }
done

test -f "${PREFIX}/lib/pkgconfig/aom.pc" || {
    echo "AOM did not install ${PREFIX}/lib/pkgconfig/aom.pc" >&2
    find "${PREFIX}" -type f -iname '*aom*.pc' -print >&2
    exit 1
}

echo "==> FFmpeg codec dependencies installed"