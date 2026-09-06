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

NAME="openssl-${OPENSSL_VERSION}"
SRC_DIR="${SRC_ROOT}/${NAME}"
TARBALL="${SRC_ROOT}/${NAME}.tar.gz"
URL="https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/${NAME}.tar.gz"

if [[ ! -f "${TARBALL}" ]]; then
    curl -fsSL --retry 5 --retry-delay 2 -o "${TARBALL}" "${URL}"
fi
if [[ ! -d "${SRC_DIR}" ]]; then
    tar -xf "${TARBALL}" -C "${SRC_ROOT}"
fi
cd "${SRC_DIR}"
make clean >/dev/null 2>&1 || true

./Configure \
    mingw64 \
    no-shared \
    no-tests \
    --prefix="${PREFIX}" \
    --openssldir="${PREFIX}/ssl" \
    --libdir=lib
make -j"${JOBS:-$(nproc)}"
make install_sw

test -f "${PREFIX}/lib/libcrypto.a"
test -f "${PREFIX}/lib/libssl.a"
echo "==> OpenSSL ${OPENSSL_VERSION} installed as static libraries"
