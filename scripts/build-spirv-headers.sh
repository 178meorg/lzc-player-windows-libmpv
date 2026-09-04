#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"
source "${ROOT_DIR}/config/versions.env"

NAME="SPIRV-Headers"
VERSION="${SPIRV_HEADERS_VERSION}"

SRC_DIR="${SRC_ROOT}/${NAME}-${VERSION}"
BUILD_DIR="${WORK_ROOT}/${NAME}-${VERSION}"

if [[ ! -d "${SRC_DIR}" ]]; then
    git clone \
        --depth 1 \
        --branch "${VERSION}" \
        https://github.com/KhronosGroup/SPIRV-Headers.git \
        "${SRC_DIR}"
fi

rm -rf "${BUILD_DIR}"

cmake \
    -S "${SRC_DIR}" \
    -B "${BUILD_DIR}" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
    -DSPIRV_HEADERS_ENABLE_TESTS=OFF

cmake --install "${BUILD_DIR}"

echo "==> SPIRV-Headers ${VERSION} build completed"