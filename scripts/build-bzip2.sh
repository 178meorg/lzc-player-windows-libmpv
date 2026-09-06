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

NAME="bzip2"
SRC_DIR="${SRC_ROOT}/${NAME}-${BZIP2_VERSION}"
BUILD_DIR="${WORK_ROOT}/${NAME}-${BZIP2_VERSION}"
TARBALL="${SRC_ROOT}/${NAME}-${BZIP2_VERSION}.tar.gz"
URL="https://sourceware.org/pub/bzip2/${NAME}-${BZIP2_VERSION}.tar.gz"

if [[ ! -f "${TARBALL}" ]]; then
    curl -fsSL --retry 5 --retry-delay 2 -o "${TARBALL}" "${URL}"
fi
if [[ ! -d "${SRC_DIR}" ]]; then
    tar -xf "${TARBALL}" -C "${SRC_ROOT}"
fi

cd "${SRC_DIR}"
make clean >/dev/null 2>&1 || true
make -j"${JOBS:-$(nproc)}" libbz2.a

mkdir -p "${PREFIX}/include" "${PREFIX}/lib"
cp -f libbz2.a "${PREFIX}/lib/"
cp -f bzlib.h "${PREFIX}/include/"

test -f "${PREFIX}/lib/libbz2.a"
echo "==> bzip2 ${BZIP2_VERSION} installed as static library"
