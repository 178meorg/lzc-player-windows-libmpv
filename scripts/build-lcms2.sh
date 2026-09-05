#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/config/versions.env"

BUILD_ROOT="${ROOT_DIR}/build"
SRC_ROOT="${BUILD_ROOT}/src"
PREFIX="${BUILD_ROOT}/install"

NAME="lcms2-${LCMS2_VERSION}"
TARBALL="${SRC_ROOT}/${NAME}.tar.gz"
SOURCE_DIR="${SRC_ROOT}/${NAME}"

URL="https://github.com/mm2/Little-CMS/releases/download/lcms${LCMS2_VERSION}/${NAME}.tar.gz"

export PATH="/mingw64/bin:${PREFIX}/bin:${PATH}"
export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig"

echo "========================================"
echo "Building Little CMS ${LCMS2_VERSION}"
echo "========================================"

mkdir -p "${SRC_ROOT}"
mkdir -p "${PREFIX}"

if [[ ! -f "${TARBALL}" ]]; then
    echo "Downloading ${URL}"

    curl \
        -L \
        --fail \
        --retry 5 \
        --retry-delay 2 \
        --retry-all-errors \
        -o "${TARBALL}" \
        "${URL}"
fi

if [[ ! -d "${SOURCE_DIR}" ]]; then
    tar \
        -xf "${TARBALL}" \
        -C "${SRC_ROOT}"
fi

cd "${SOURCE_DIR}"

./configure \
    --prefix="${PREFIX}" \
    --libdir="${PREFIX}/lib" \
    --enable-static \
    --disable-shared

make -j"$(nproc)"

make install

echo
echo "========================================"
echo "Little CMS installed"
echo "========================================"

pkg-config --modversion lcms2