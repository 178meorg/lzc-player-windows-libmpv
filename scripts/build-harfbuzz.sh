#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/config/versions.env"

BUILD_ROOT="${ROOT_DIR}/build"
SRC_ROOT="${BUILD_ROOT}/src"
PREFIX="${BUILD_ROOT}/install"

NAME="harfbuzz-${HARFBUZZ_VERSION}"
TARBALL="${SRC_ROOT}/${NAME}.tar.xz"
SOURCE_DIR="${SRC_ROOT}/${NAME}"

URL="https://github.com/harfbuzz/harfbuzz/releases/download/${HARFBUZZ_VERSION}/${NAME}.tar.xz"

export PATH="/mingw64/bin:${PREFIX}/bin:${PATH}"
export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig"

echo "========================================"
echo "Building HarfBuzz ${HARFBUZZ_VERSION}"
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

meson setup build \
    --prefix="${PREFIX}" \
    --libdir=lib \
    --buildtype=release \
    --default-library=static \
    -Ddocs=disabled \
    -Dtests=disabled \
    -Dbenchmark=disabled \
    -Dintrospection=disabled \
    -Dglib=disabled \
    -Dcairo=disabled \
    -Dicu=disabled \
    -Dgraphite2=disabled

meson compile -C build -j"$(nproc)"

meson install -C build

echo
echo "========================================"
echo "HarfBuzz installed"
echo "========================================"

pkg-config --modversion harfbuzz