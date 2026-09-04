#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "${ROOT_DIR}/config/versions.env"

BUILD_ROOT="${BUILD_ROOT:-${ROOT_DIR}/build}"
SRC_ROOT="${SRC_ROOT:-${BUILD_ROOT}/src}"
PREFIX="${PREFIX:-${BUILD_ROOT}/install}"

mkdir -p \
    "${SRC_ROOT}" \
    "${PREFIX}"

export ROOT_DIR
export BUILD_ROOT
export SRC_ROOT
export PREFIX

export PATH="/mingw64/bin:${HOME}/.cargo/bin:${PREFIX}/bin:${PATH}"
export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig"

NAME="libdovi"
VERSION="libdovi-${LIBDOVI_VERSION}"

SRC_DIR="${SRC_ROOT}/${VERSION}"

echo "========================================"
echo "Building libdovi ${LIBDOVI_VERSION}"
echo "========================================"

if [[ ! -d "${SRC_DIR}/.git" ]]; then
    rm -rf "${SRC_DIR}"

    git clone \
        --depth 1 \
        --branch "${VERSION}" \
        https://github.com/quietvoid/dovi_tool.git \
        "${SRC_DIR}"
fi

cd "${SRC_DIR}/dolby_vision"

echo "Cargo package:"
grep '^name =' Cargo.toml | head -1

which rustc
which cargo
rustc -vV
cargo -V

echo
echo "Building libdovi..."

cargo cinstall \
    --target x86_64-pc-windows-gnu \
    --release \
    --prefix="${PREFIX}" \
    --libdir="${PREFIX}/lib"

echo
echo "========================================"
echo "libdovi installed"
echo "========================================"

echo "Checking installation..."

find "${PREFIX}" \
    -maxdepth 4 \
    \( \
        -name 'libdovi*' \
        -o -name 'dovi.pc' \
        -o -name '*.h' \
    \) \
    -print

echo
echo "pkg-config:"
pkg-config --modversion dovi