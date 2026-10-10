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

# mpv and libplacebo request spirv-cross-c-shared by name. Build that target
# as a static archive, as the Windows mpv-dev builds do.
python - "${SRC_DIR}/CMakeLists.txt" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text()
replacements = {
    "spirv_cross_add_library(spirv-cross-c-shared spirv_cross_c_shared SHARED":
        "spirv_cross_add_library(spirv-cross-c-shared spirv_cross_c_shared STATIC",
    "\ttarget_compile_definitions(spirv-cross-c-shared PRIVATE SPVC_EXPORT_SYMBOLS)\n\n": "",
    "\tset_target_properties(spirv-cross-c-shared PROPERTIES\n"
    "\t\t\tVERSION ${SPIRV_CROSS_VERSION}\n"
    "\t\t\tSOVERSION ${spirv-cross-abi-major})\n": "",
}
for old, new in replacements.items():
    if source.count(old) == 1:
        source = source.replace(old, new, 1)
    elif new and source.count(new) == 1:
        continue  # Source was patched by an earlier run.
    elif not new and old not in source:
        continue
    else:
        raise SystemExit(f"Unexpected SPIRV-Cross CMake source in {path}")
path.write_text(source)
PY

rm -rf "${BUILD_DIR}"

cmake \
    -S "${SRC_DIR}" \
    -B "${BUILD_DIR}" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
    -DSPIRV_CROSS_SHARED=ON \
    -DSPIRV_CROSS_STATIC=OFF \
    -DSPIRV_CROSS_CLI=OFF \
    -DSPIRV_CROSS_ENABLE_TESTS=OFF \
    -DSPIRV_CROSS_ENABLE_MSL=ON \
    -DSPIRV_CROSS_ENABLE_HLSL=ON \
    -DSPIRV_CROSS_ENABLE_GLSL=ON \
    -DSPIRV_CROSS_ENABLE_CPP=ON

cmake --build "${BUILD_DIR}"
cmake --install "${BUILD_DIR}"

STATIC_PC="${PREFIX}/lib/pkgconfig/spirv-cross-c-shared.pc"
test -f "${STATIC_PC}"
sed -i \
    's|^Libs:.*|Libs: -L${libdir} -lspirv-cross-c-shared -l:libstdc++.a|' \
    "${STATIC_PC}"

test -f "${PREFIX}/lib/libspirv-cross-c-shared.a"

echo "==> SPIRV-Cross ${VERSION} build completed"

pkg-config --modversion spirv-cross-c-shared
