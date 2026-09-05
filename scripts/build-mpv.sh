#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BUILD_ROOT="${BUILD_ROOT:-${ROOT_DIR}/build}"
SRC_ROOT="${SRC_ROOT:-${BUILD_ROOT}/src}"
WORK_ROOT="${WORK_ROOT:-${BUILD_ROOT}/work}"
PREFIX="${PREFIX:-${BUILD_ROOT}/install}"

mkdir -p \
    "${SRC_ROOT}" \
    "${WORK_ROOT}" \
    "${PREFIX}"

export ROOT_DIR
export BUILD_ROOT
export SRC_ROOT
export WORK_ROOT
export PREFIX

export PATH="${PREFIX}/bin:/mingw64/bin:${PATH}"

export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PREFIX}/share/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"

NAME="mpv"
SRC_DIR="${SRC_ROOT}/${NAME}"
BUILD_DIR="${WORK_ROOT}/${NAME}"

echo "========================================"
echo "Building mpv"
echo "========================================"

echo "ROOT_DIR=${ROOT_DIR}"
echo "PREFIX=${PREFIX}"
echo "SRC_DIR=${SRC_DIR}"
echo "BUILD_DIR=${BUILD_DIR}"

# ------------------------------------------------------------
# Clone latest source
# ------------------------------------------------------------

if [[ ! -d "${SRC_DIR}/.git" ]]; then

    echo
    echo "==> Cloning latest mpv"

    git clone \
        --depth 1 \
        https://github.com/178meorg/mpv.git \
        "${SRC_DIR}"

else

    echo
    echo "==> Updating mpv"

    cd "${SRC_DIR}"

    git fetch \
        --depth 1 \
        origin \
        HEAD

    git reset \
        --hard \
        FETCH_HEAD

fi

cd "${SRC_DIR}"

echo
echo "==> mpv commit"

git rev-parse HEAD

# ------------------------------------------------------------
# Configure
# ------------------------------------------------------------

rm -rf "${BUILD_DIR}"

echo
echo "========================================"
echo "Configuring mpv"
echo "========================================"

meson setup "${BUILD_DIR}" \
    --prefix="${PREFIX}" \
    --libdir=lib \
    --buildtype=release \
    -Dlibmpv=true \
    -Dbuild-date=false \
    -Dmanpage-build=disabled \
    -Dhtml-build=disabled \
    -Dtests=false

# ------------------------------------------------------------
# Show configuration
# ------------------------------------------------------------

echo
echo "========================================"
echo "mpv configuration"
echo "========================================"

meson configure "${BUILD_DIR}"

# ------------------------------------------------------------
# Build
# ------------------------------------------------------------

echo
echo "========================================"
echo "Building mpv"
echo "========================================"

meson compile \
    -C "${BUILD_DIR}" \
    -j"$(nproc)"

# ------------------------------------------------------------
# Install
# ------------------------------------------------------------

echo
echo "========================================"
echo "Installing mpv"
echo "========================================"

meson install \
    -C "${BUILD_DIR}"

# ------------------------------------------------------------
# Verify
# ------------------------------------------------------------

echo
echo "========================================"
echo "Verifying libmpv"
echo "========================================"

find "${PREFIX}" \
    -maxdepth 3 \
    -type f \
    \( \
        -name 'libmpv*.dll' \
        -o -name 'libmpv*.dll.a' \
        -o -name 'libmpv*.a' \
        -o -name 'mpv*.dll' \
    \) \
    -print

echo
echo "========================================"
echo "mpv build completed"
echo "========================================"

echo "PREFIX=${PREFIX}"