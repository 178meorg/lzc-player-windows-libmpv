#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"
source "${ROOT_DIR}/config/versions.env"

NAME="shaderc"
VERSION="${SHADERC_VERSION}"

SRC_DIR="${SRC_ROOT}/${NAME}-${VERSION}"
BUILD_DIR="${WORK_ROOT}/${NAME}-${VERSION}"

if [[ ! -d "${SRC_DIR}" ]]; then
    git clone \
        --depth 1 \
        --branch "v${VERSION}" \
        https://github.com/google/shaderc.git \
        "${SRC_DIR}"
fi

cd "${SRC_DIR}"

./utils/git-sync-deps

rm -rf "${BUILD_DIR}"

cmake \
    -S "${SRC_DIR}" \
    -B "${BUILD_DIR}" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DSHADERC_SKIP_TESTS=ON \
    -DSHADERC_SKIP_EXAMPLES=ON \
    -DSHADERC_SKIP_COPYRIGHT_CHECK=ON \
    -DSHADERC_SKIP_EXECUTABLES=OFF \
    -DSHADERC_SKIP_LIBCXX=ON \
    -DENABLE_EXCEPTIONS=ON

cmake --build "${BUILD_DIR}"
cmake --install "${BUILD_DIR}"

echo "==> shaderc ${VERSION} build completed"

find "${PREFIX}" \
    -maxdepth 3 \
    \( -iname '*shaderc*.dll' -o -iname '*shaderc*.a' -o -iname '*shaderc*.pc' \) \
    -print