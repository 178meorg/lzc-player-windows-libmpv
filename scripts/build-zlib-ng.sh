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

NAME="zlib-ng"
SRC_DIR="${SRC_ROOT}/${NAME}"
BUILD_DIR="${WORK_ROOT}/${NAME}"

if [[ ! -d "${SRC_DIR}/.git" ]]; then
    git clone \
        --depth 1 \
        --branch "${ZLIB_NG_VERSION}" \
        https://github.com/zlib-ng/zlib-ng.git \
        "${SRC_DIR}"
fi

rm -rf "${BUILD_DIR}"

cmake \
    -S "${SRC_DIR}" \
    -B "${BUILD_DIR}" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
    -DCMAKE_FIND_ROOT_PATH="${PREFIX}" \
    -DBUILD_SHARED_LIBS=OFF \
    -DINSTALL_PKGCONFIG_DIR="${PREFIX}/lib/pkgconfig" \
    -DSKIP_INSTALL_LIBRARIES=OFF \
    -DZLIB_COMPAT=ON \
    -DZLIB_ENABLE_TESTS=OFF \
    -DZLIBNG_ENABLE_TESTS=OFF \
    -DFNO_LTO_AVAILABLE=OFF

cmake --build "${BUILD_DIR}"
cmake --install "${BUILD_DIR}"

test -f "${PREFIX}/lib/libz.a"
test -f "${PREFIX}/lib/pkgconfig/zlib.pc"
pkg-config --modversion zlib
pkg-config --static --libs zlib

echo "==> zlib-ng ${ZLIB_NG_VERSION} installed as static zlib"