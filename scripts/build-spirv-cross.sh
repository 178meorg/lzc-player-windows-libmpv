#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"
source "${ROOT_DIR}/config/versions.env"

NAME="SPIRV-Cross"
VERSION="${SPIRV_CROSS_VERSION}"

SRC_DIR="${SRC_ROOT}/${NAME}-${VERSION}"
BUILD_DIR="${WORK_ROOT}/${NAME}-${VERSION}"

if [[ ! -d "${SRC_DIR}" ]]; then
    git clone \
        --depth 1 \
        --branch "${VERSION}" \
        https://github.com/KhronosGroup/SPIRV-Cross.git \
        "${SRC_DIR}"
fi

rm -rf "${BUILD_DIR}"

cmake \
    -S "${SRC_DIR}" \
    -B "${BUILD_DIR}" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
    -DSPIRV_CROSS_SHARED=OFF \
    -DSPIRV_CROSS_STATIC=ON \
    -DSPIRV_CROSS_CLI=OFF \
    -DSPIRV_CROSS_ENABLE_TESTS=OFF \
    -DSPIRV_CROSS_ENABLE_MSL=ON \
    -DSPIRV_CROSS_ENABLE_HLSL=ON \
    -DSPIRV_CROSS_ENABLE_GLSL=ON \
    -DSPIRV_CROSS_ENABLE_CPP=ON

cmake --build "${BUILD_DIR}"
cmake --install "${BUILD_DIR}"

STATIC_PC="${PREFIX}/lib/pkgconfig/spirv-cross-c.pc"
if [[ -f "${STATIC_PC}" ]]; then
    sed -i \
        's|^Libs:.*|Libs: -L${libdir} -lspirv-cross-c -lspirv-cross-cpp -lspirv-cross-hlsl -lspirv-cross-msl -lspirv-cross-reflect -lspirv-cross-glsl -lspirv-cross-core|' \
        "${STATIC_PC}"
fi

echo "==> SPIRV-Cross ${VERSION} build completed"

pkg-config --modversion spirv-cross-c || true