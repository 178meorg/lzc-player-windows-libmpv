#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"
source "${ROOT_DIR}/config/versions.env"

NAME="Vulkan-Loader"
VERSION="${VULKAN_LOADER_VERSION}"

SRC_DIR="${SRC_ROOT}/${NAME}-${VERSION}"
BUILD_DIR="${WORK_ROOT}/${NAME}-${VERSION}"

if [[ ! -d "${SRC_DIR}" ]]; then
    git clone \
        --depth 1 \
        --branch "v${VERSION}" \
        https://github.com/KhronosGroup/Vulkan-Loader.git \
        "${SRC_DIR}"
fi

rm -rf "${BUILD_DIR}"

cmake \
    -S "${SRC_DIR}" \
    -B "${BUILD_DIR}" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
    -DVULKAN_HEADERS_INSTALL_DIR="${PREFIX}" \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_STATIC_LOADER=ON \
    -DBUILD_TESTS=OFF \
    -DBUILD_WERROR=OFF

cmake --build "${BUILD_DIR}"
cmake --install "${BUILD_DIR}"

echo "==> Vulkan-Loader ${VERSION} build completed"

find "${PREFIX}" \
    -maxdepth 3 \
    \( -iname 'vulkan-1.dll' -o -iname 'vulkan*.dll' \) \
    -print