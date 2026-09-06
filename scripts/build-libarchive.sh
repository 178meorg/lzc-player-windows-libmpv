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

NAME="libarchive"
SRC_DIR="${SRC_ROOT}/${NAME}-${LIBARCHIVE_VERSION#v}"
BUILD_DIR="${WORK_ROOT}/${NAME}-${LIBARCHIVE_VERSION#v}"

if [[ ! -d "${SRC_DIR}/.git" ]]; then
    git clone \
        --depth 1 \
        --branch "${LIBARCHIVE_VERSION}" \
        https://github.com/libarchive/libarchive.git \
        "${SRC_DIR}"
fi

rm -rf "${BUILD_DIR}"

cmake \
    -S "${SRC_DIR}" \
    -B "${BUILD_DIR}" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
    -DCMAKE_FIND_ROOT_PATH="${PREFIX};/mingw64" \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DBUILD_SHARED_LIBS=OFF \
    -DENABLE_ZLIB=ON \
    -DENABLE_ZSTD=ON \
    -DENABLE_OPENSSL=ON \
    -DENABLE_BZip2=ON \
    -DENABLE_ICONV=ON \
    -DENABLE_LIBXML2=ON \
    -DENABLE_EXPAT=OFF \
    -DENABLE_LZO=ON \
    -DENABLE_LZMA=ON \
    -DENABLE_CPIO=OFF \
    -DENABLE_CAT=OFF \
    -DENABLE_TAR=OFF \
    -DENABLE_WERROR=OFF \
    -DBUILD_TESTING=OFF \
    -DENABLE_TEST=OFF \
    -DWINDOWS_VERSION=WIN10 \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5

cmake --build "${BUILD_DIR}"
cmake --install "${BUILD_DIR}"

test -f "${PREFIX}/lib/libarchive.a"
test -f "${PREFIX}/lib/pkgconfig/libarchive.pc"
pkg-config --modversion libarchive
pkg-config --static --libs libarchive

echo "==> libarchive ${LIBARCHIVE_VERSION} installed as static library"