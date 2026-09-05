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

source "${ROOT_DIR}/config/versions.env"

NAME="libplacebo"
VERSION="${LIBPLACEBO_VERSION}"

SRC_DIR="${SRC_ROOT}/${NAME}-${VERSION}"
BUILD_DIR="${WORK_ROOT}/${NAME}-${VERSION}"

if [[ ! -d "${SRC_DIR}" ]]; then
    git clone \
        --depth 1 \
        --branch "v${VERSION}" \
        https://code.videolan.org/videolan/libplacebo.git \
        "${SRC_DIR}"
fi

rm -rf "${BUILD_DIR}"

cd "${SRC_DIR}"

meson setup "${BUILD_DIR}" \
    --prefix="${PREFIX}" \
    --libdir=lib \
    --buildtype=release \
    --default-library=static \
    -Dtests=false \
    -Dbench=false \
    -Ddemos=false \
    -Dfuzz=false \
    -Dvulkan=enabled \
    -Dd3d11=enabled \
    -Dopengl=enabled \
    -Dshaderc=enabled \
    -Dglslang=disabled \
    -Dlcms=enabled \
    -Dlibdovi=enabled \
    -Dunwind=disabled \
    -Dvulkan-registry="${PREFIX}/share/vulkan/registry/vk.xml"

meson configure "${BUILD_DIR}"

ninja -C "${BUILD_DIR}"

ninja -C "${BUILD_DIR}" install

echo
echo "========================================"
echo "libplacebo ${VERSION} build completed"
echo "========================================"

echo
echo "Enabled features:"
meson configure "${BUILD_DIR}" | grep -Ei \
    'vulkan|d3d11|opengl|shaderc|glslang|lcms|dovi' || true