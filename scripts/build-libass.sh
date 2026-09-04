#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/config/versions.env"

BUILD_ROOT="${ROOT_DIR}/build"
SRC_ROOT="${BUILD_ROOT}/src"
PREFIX="${BUILD_ROOT}/install"

NAME="libass-${LIBASS_VERSION}"
TARBALL="${SRC_ROOT}/${NAME}.tar.xz"
SOURCE_DIR="${SRC_ROOT}/${NAME}"

URL="https://github.com/libass/libass/releases/download/${LIBASS_VERSION}/${NAME}.tar.xz"

export PATH="/mingw64/bin:${PREFIX}/bin:${PATH}"
export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig"

echo "========================================"
echo "Building libass ${LIBASS_VERSION}"
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

echo
echo "Dependencies:"
echo "----------------------------------------"

pkg-config --modversion freetype2
pkg-config --modversion fribidi
pkg-config --modversion harfbuzz

echo
echo "Configuring libass..."
echo "----------------------------------------"

./configure \
    --prefix="${PREFIX}" \
    --enable-shared \
    --disable-static \
    --disable-doc

echo
echo "Building..."
echo "----------------------------------------"

make -j"$(nproc)"

echo
echo "Installing..."
echo "----------------------------------------"

make install

echo
echo "========================================"
echo "libass installed successfully"
echo "========================================"

echo
echo "libass version:"
pkg-config --modversion libass

echo
echo "libass dependencies:"
pkg-config --libs libass