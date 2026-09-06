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

NAME="lzo-${LZO_VERSION}"
SRC_DIR="${SRC_ROOT}/${NAME}"
TARBALL="${SRC_ROOT}/${NAME}.tar.gz"
URL="https://www.oberhumer.com/opensource/lzo/download/${NAME}.tar.gz"

if [[ ! -f "${TARBALL}" ]]; then
    curl -fsSL --retry 5 --retry-delay 2 -o "${TARBALL}" "${URL}"
fi
if [[ ! -d "${SRC_DIR}" ]]; then
    tar -xf "${TARBALL}" -C "${SRC_ROOT}"
fi
cd "${SRC_DIR}"
make distclean >/dev/null 2>&1 || true

./configure \
    --host=x86_64-w64-mingw32 \
    --prefix="${PREFIX}" \
    --enable-static \
    --disable-shared
make -j"${JOBS:-$(nproc)}"
make install

test -f "${PREFIX}/lib/liblzo2.a"
echo "==> lzo ${LZO_VERSION} installed as static library"
