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
    source = source.replace(old, new, 1)
elif new not in source:
    raise SystemExit('Windows Vulkan Loader target layout changed')

# The shared Windows target suppresses MinGW's lib prefix. Static archives
# need that prefix for the usual -lvulkan-1 linker flag.
old_prefix = '''        set_target_properties(vulkan
                              PROPERTIES
                              PREFIX "")'''
new_prefix = old_prefix.replace('PREFIX ""', 'PREFIX "lib"')
if old_prefix in source:
    source = source.replace(old_prefix, new_prefix, 1)
elif new_prefix not in source:
    raise SystemExit('Windows Vulkan Loader archive prefix layout changed')

# Static archives expose private INTERFACE targets through their CMake export.
# That export is not needed by our pkg-config consumers and upstream does not
# export loader_specific_options, so omit it for this static build.
for old, new in (
    ('install(TARGETS vulkan EXPORT VulkanLoaderConfig)',
     'install(TARGETS vulkan)'),
    ('install(EXPORT VulkanLoaderConfig DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/VulkanLoader NAMESPACE Vulkan::)',
     ''),
):
    if old in source:
        source = source.replace(old, new, 1)
    elif new and new not in source:
        raise SystemExit('Vulkan Loader CMake export layout changed')
path.write_text(source)
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

# Upstream's MinGW pkg-config file uses -lvulkan-1.dll for the import
# library. Point it at the archive and include the Windows setup API needed
# by the loader implementation.
python - "${PREFIX}/lib/pkgconfig/vulkan.pc" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text()
old = 'Libs: -L${libdir} -lvulkan-1.dll'
if source.count(old) != 1:
    raise SystemExit('Unexpected Vulkan pkg-config library flags')
path.write_text(source.replace(old, 'Libs: -L${libdir} -lvulkan-1\nLibs.private: -lcfgmgr32'))
PY

export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PREFIX}/share/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"
pkg-config --static --libs vulkan | grep -q -- '-lvulkan-1'

echo "==> Vulkan-Loader ${VERSION} build completed"

find "${PREFIX}" \
    -maxdepth 3 \
    \( -iname 'vulkan-1.dll' -o -iname 'vulkan*.dll' \) \
    -print
