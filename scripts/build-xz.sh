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

NAME="xz-${XZ_VERSION}"
SRC_DIR="${SRC_ROOT}/${NAME}"
BUILD_DIR="${WORK_ROOT}/${NAME}"
TARBALL="${SRC_ROOT}/${NAME}.tar.xz"
URL="https://github.com/tukaani-project/xz/releases/download/v${XZ_VERSION}/${NAME}.tar.xz"

if [[ ! -f "${TARBALL}" ]]; then
    curl -fsSL --retry 5 --retry-delay 2 -o "${TARBALL}" "${URL}"
fi
if [[ ! -d "${SRC_DIR}" ]]; then
    tar -xf "${TARBALL}" -C "${SRC_ROOT}"
fi
rm -rf "${BUILD_DIR}"

cmake -S "${SRC_DIR}" -B "${BUILD_DIR}" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_TESTING=OFF \
    -DENABLE_NLS=OFF

grep -q '^ENABLE_NLS:BOOL=OFF$' "${BUILD_DIR}/CMakeCache.txt"

cmake --build "${BUILD_DIR}"
cmake --install "${BUILD_DIR}"

test -f "${PREFIX}/lib/liblzma.a"
echo "==> xz ${XZ_VERSION} installed as static liblzma"
