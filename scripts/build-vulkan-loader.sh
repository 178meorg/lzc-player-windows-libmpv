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

# Vulkan-Loader ignores BUILD_STATIC_LOADER on Windows and hard-codes a
# shared target. Build that target as an archive so Vulkan stays in libmpv.
python - "${SRC_DIR}/loader/CMakeLists.txt" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text()
old = '''    add_library(vulkan
                SHARED
                ${NORMAL_LOADER_SRCS}'''
new = old.replace('SHARED', 'STATIC')
if old in source:
    path.write_text(source.replace(old, new, 1))
elif new not in source:
    raise SystemExit('Windows Vulkan Loader target layout changed')
PY

rm -rf "${BUILD_DIR}"

cmake \
    -S "${SRC_DIR}" \
    -B "${BUILD_DIR}" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
    -DVULKAN_HEADERS_INSTALL_DIR="${PREFIX}" \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_TESTS=OFF \
    -DBUILD_WERROR=OFF

cmake --build "${BUILD_DIR}"
cmake --install "${BUILD_DIR}"

test -s "${PREFIX}/lib/libvulkan-1.a"
test ! -f "${PREFIX}/bin/vulkan-1.dll"

echo "==> Vulkan-Loader ${VERSION} build completed"

find "${PREFIX}" \
    -maxdepth 3 \
    \( -iname 'vulkan-1.dll' -o -iname 'vulkan*.dll' \) \
    -print
