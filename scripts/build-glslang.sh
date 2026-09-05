#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"
source "${ROOT_DIR}/config/versions.env"

NAME="glslang"
VERSION="${GLSLANG_VERSION}"

SRC_DIR="${SRC_ROOT}/${NAME}-${VERSION}"
BUILD_DIR="${WORK_ROOT}/${NAME}-${VERSION}"

if [[ ! -d "${SRC_DIR}" ]]; then
    git clone \
        --depth 1 \
        --branch "${VERSION}" \
        https://github.com/KhronosGroup/glslang.git \
        "${SRC_DIR}"
fi

rm -rf "${BUILD_DIR}"

cmake \
    -S "${SRC_DIR}" \
    -B "${BUILD_DIR}" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DBUILD_SHARED_LIBS=OFF \
    -DALLOW_EXTERNAL_SPIRV_TOOLS=ON \
    -DSPIRV-Headers_SOURCE_DIR="${PREFIX}/include" \
    -DSPIRV-Tools_SOURCE_DIR="${PREFIX}" \
    -DENABLE_GLSLANG_BINARIES=OFF \
    -DENABLE_SPVREMAPPER=OFF \
    -DENABLE_HLSL=ON \
    -DENABLE_RTTI=ON \
    -DENABLE_OPT=ON \
    -DBUILD_TESTING=OFF

cmake --build "${BUILD_DIR}"
cmake --install "${BUILD_DIR}"

echo "==> glslang ${VERSION} build completed"