#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/config/versions.env"

BUILD_ROOT="${ROOT_DIR}/build"
SRC_ROOT="${BUILD_ROOT}/src"
PREFIX="${BUILD_ROOT}/install"

NAME="freetype-${FREETYPE_VERSION}"
TARBALL="${SRC_ROOT}/${NAME}.tar.xz"
SOURCE_DIR="${SRC_ROOT}/${NAME}"

URL="https://download.savannah.gnu.org/releases/freetype/${NAME}.tar.xz"

export PATH="/mingw64/bin:${PREFIX}/bin:${PATH}"
export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig"

echo "========================================"
echo "Building FreeType ${FREETYPE_VERSION}"
echo "========================================"

mkdir -p "${SRC_ROOT}"
mkdir -p "${PREFIX}"

if [[ ! -f "${TARBALL}" ]]; then
    echo "Downloading ${URL}"

    curl -L \
        --fail \
        --retry 5 \
        -o "${TARBALL}" \
        "${URL}"
fi

if [[ ! -d "${SOURCE_DIR}" ]]; then
    tar -xf "${TARBALL}" -C "${SRC_ROOT}"
fi

cd "${SOURCE_DIR}"

rm -rf build

mkdir -p build
cd build

../configure \
    --prefix="${PREFIX}" \
    --enable-shared \
    --disable-static \
    --disable-docs \
    --without-zlib \
    --without-bzip2 \
    --without-png \
    --without-harfbuzz

make -j"$(nproc)"

make install

echo
echo "========================================"
echo "FreeType installed"
echo "========================================"

pkg-config --modversion freetype2

ls -la "${PREFIX}/bin" | grep -i freetype || true
ls -la "${PREFIX}/lib" | grep -i freetype || true