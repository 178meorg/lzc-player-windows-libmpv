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

build_cmake() {
    local name="$1" url="$2" ref="$3" source_subdir="$4" cmake_args="$5"
    local source build
    source="$(clone_git "${name}" "${url}" "${ref}")"
    build="${WORK_ROOT}/${name}"
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

build_autotools_tar() {
    local name="$1" url="$2" archive_name="$3" source_dir="$4" configure_args="$5"
    local archive="${SRC_ROOT}/${archive_name}"
    local source="${SRC_ROOT}/${source_dir}"
    if [[ ! -f "${archive}" ]]; then
        curl -fsSL --retry 5 -o "${archive}" "${url}"
    fi
    [[ -d "${source}" ]] || tar -xf "${archive}" -C "${SRC_ROOT}"
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

build_autotools_git() {
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

build_cmake expat https://github.com/libexpat/libexpat.git "R_${EXPAT_VERSION//./_}" expat "-DEXPAT_BUILD_EXAMPLES=OFF -DEXPAT_BUILD_TESTS=OFF -DEXPAT_BUILD_TOOLS=OFF"
build_cmake libpng https://github.com/pnggroup/libpng.git "v${LIBPNG_VERSION}" . "-DPNG_TESTS=OFF"
build_cmake libssh https://git.libssh.org/projects/libssh.git "libssh-${LIBSSH_VERSION}" . "-DWITH_EXAMPLES=OFF -DWITH_TESTING=OFF -DWITH_GSSAPI=OFF -DWITH_SERVER=OFF"
build_cmake srt https://github.com/Haivision/srt.git "v${SRT_VERSION}" . "-DENABLE_APPS=OFF -DENABLE_TESTING=OFF -DENABLE_SHARED=OFF"
build_cmake zimg https://github.com/sekrit-twc/zimg.git "release-${LIBZIMG_VERSION}" . "-DZIMG_BUILD_TESTS=OFF -DZIMG_BUILD_TOOLS=OFF"
build_cmake mysofa https://github.com/hoene/libmysofa.git "v${LIBMYSOFA_VERSION}" . "-DBUILD_TESTS=OFF -DBUILD_SHARED_LIBS=OFF"
build_cmake libvpl https://github.com/oneapi-src/oneVPL.git "v${LIBVPL_VERSION}" . "-DBUILD_DISPATCHER=ON -DBUILD_TOOLS=OFF -DBUILD_EXAMPLES=OFF -DBUILD_TESTS=OFF"
build_cmake openal-soft https://github.com/kcat/openal-soft.git "${OPENAL_VERSION}" . "-DALSOFT_EXAMPLES=OFF -DALSOFT_TESTS=OFF -DALSOFT_UTILS=OFF"
build_autotools_git modplug https://github.com/Konstanty/libmodplug.git "${LIBMODPLUG_VERSION}" ""

build_autotools_tar \
    fontconfig \
    "https://www.freedesktop.org/software/fontconfig/release/fontconfig-${FONTCONFIG_VERSION}.tar.xz" \
    "fontconfig-${FONTCONFIG_VERSION}.tar.xz" \
    "fontconfig-${FONTCONFIG_VERSION}" \
    "--disable-docs --disable-libxml2"

build_autotools_tar \
    libbluray \
    "https://download.videolan.org/pub/videolan/libbluray/${LIBBLURAY_VERSION}/libbluray-${LIBBLURAY_VERSION}.tar.bz2" \
    "libbluray-${LIBBLURAY_VERSION}.tar.bz2" \
    "libbluray-${LIBBLURAY_VERSION}" \
    "--disable-bdjava --disable-doxygen"

build_autotools_tar \
    libdvdread \
    "https://download.videolan.org/pub/videolan/libdvdread/${LIBDVDREAD_VERSION}/libdvdread-${LIBDVDREAD_VERSION}.tar.bz2" \
    "libdvdread-${LIBDVDREAD_VERSION}.tar.bz2" \
    "libdvdread-${LIBDVDREAD_VERSION}" \
    ""

build_autotools_tar \
    libdvdnav \
    "https://download.videolan.org/pub/videolan/libdvdnav/${LIBDVDNAV_VERSION}/libdvdnav-${LIBDVDNAV_VERSION}.tar.bz2" \
    "libdvdnav-${LIBDVDNAV_VERSION}.tar.bz2" \
    "libdvdnav-${LIBDVDNAV_VERSION}" \
    ""

for library in expat libpng libssh srt-1 libzimg libmysofa vpl openal fontconfig libbluray dvdread dvdnav libmodplug; do
    pkg-config --exists "${library}" || {
        echo "Missing pkg-config package: ${library}" >&2
        exit 1
    }
done

echo "==> FFmpeg extra dependencies installed"