#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"
source "${ROOT_DIR}/config/versions.env"

NAME="SPIRV-Tools"
VERSION="${SPIRV_TOOLS_VERSION}"

SRC_DIR="${SRC_ROOT}/${NAME}-${VERSION}"
BUILD_DIR="${WORK_ROOT}/${NAME}-${VERSION}"

if [[ ! -d "${SRC_DIR}" ]]; then
    git clone \
        --depth 1 \
        --branch "${VERSION}" \
        https://github.com/KhronosGroup/SPIRV-Tools.git \
        "${SRC_DIR}"
fi

cd "${SRC_DIR}"

if [[ ! -d external/spirv-headers ]]; then
    git clone \
        --depth 1 \
        --branch "${SPIRV_HEADERS_VERSION}" \
        https://github.com/KhronosGroup/SPIRV-Headers.git \
        external/spirv-headers
fi

rm -rf "${BUILD_DIR}"

cmake \
    -S "${SRC_DIR}" \
    -B "${BUILD_DIR}" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DSPIRV_SKIP_TESTS=ON \
    -DSPIRV_SKIP_EXECUTABLES=OFF \
    -DSPIRV_WERROR=OFF

cmake --build "${BUILD_DIR}"
cmake --install "${BUILD_DIR}"

echo "==> SPIRV-Tools ${VERSION} build completed"