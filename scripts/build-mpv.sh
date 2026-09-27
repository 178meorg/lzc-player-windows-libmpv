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

NAME="mpv"
SRC_DIR="${SRC_ROOT}/${NAME}"
BUILD_DIR="${WORK_ROOT}/${NAME}"
PACKAGE_NAME="libmpv-windows-x86_64"
PACKAGE_DIR="${BUILD_ROOT}/${PACKAGE_NAME}"
PACKAGE_ARCHIVE="${BUILD_ROOT}/${PACKAGE_NAME}.zip"

echo "========================================"
echo "Building mpv"
echo "========================================"

echo "ROOT_DIR=${ROOT_DIR}"
echo "PREFIX=${PREFIX}"
echo "SRC_DIR=${SRC_DIR}"
echo "BUILD_DIR=${BUILD_DIR}"

# ------------------------------------------------------------
# Clone latest source
# ------------------------------------------------------------

if [[ ! -d "${SRC_DIR}/.git" ]]; then

    echo
    echo "==> Cloning latest mpv"

    git clone \
        --depth 1 \
        https://github.com/178meorg/mpv.git \
        "${SRC_DIR}"

else

    echo
    echo "==> Updating mpv"

    cd "${SRC_DIR}"

    git fetch \
        --depth 1 \
        origin \
        HEAD

    git reset \
        --hard \
        FETCH_HEAD

fi

cd "${SRC_DIR}"

echo
echo "==> mpv commit"

git rev-parse HEAD

# ------------------------------------------------------------
# Configure
# ------------------------------------------------------------

rm -rf "${BUILD_DIR}"

echo
echo "========================================"
echo "Configuring mpv"
echo "========================================"

meson setup "${BUILD_DIR}" \
    --prefix="${PREFIX}" \
    --libdir=lib \
    --buildtype=release \
    --default-library=shared \
    --prefer-static \
    -Ddebug=true \
    -Db_ndebug=true \
    -Doptimization=3 \
    -Db_lto=true \
    -Dcplayer=true \
    -Dlibmpv=true \
    -Dbuild-date=false \
    -Dpdf-build=enabled \
    -Dmanpage-build=enabled \
    -Dhtml-build=enabled \
    -Dtests=true \
    -Dlua=enabled \
    -Djavascript=enabled \
    -Dsdl2-gamepad=enabled \
    -Ddvdnav=enabled \
    -Dlibarchive=enabled \
    -Dlibbluray=enabled \
    -Duchardet=enabled \
    -Drubberband=enabled \
    -Dopenal=enabled \
    -Dlcms2=enabled \
    -Dspirv-cross=enabled \
    -Dvapoursynth=enabled \
    -Dlibcurl=enabled \
    -Dvulkan=enabled

python - "${BUILD_DIR}" <<'PY'
import json
import subprocess
import sys

build_dir = sys.argv[1]
options = json.loads(subprocess.check_output(
    ["meson", "introspect", "--buildoptions", build_dir], text=True
))
actual = {item["name"]: item["value"] for item in options}
expected = {
    "cplayer": True,
    "libmpv": True,
    "debug": True,
    "optimization": "3",
    "b_lto": True,
    "pdf-build": "enabled",
    "manpage-build": "enabled",
    "html-build": "enabled",
    "tests": True,
    "lua": "enabled",
    "javascript": "enabled",
    "sdl2-gamepad": "enabled",
    "dvdnav": "enabled",
    "libarchive": "enabled",
    "libbluray": "enabled",
    "uchardet": "enabled",
    "rubberband": "enabled",
    "openal": "enabled",
    "lcms2": "enabled",
    "spirv-cross": "enabled",
    "vapoursynth": "enabled",
    "libcurl": "enabled",
    "vulkan": "enabled",
}
errors = []
for name, wanted in expected.items():
    got = actual.get(name, "<missing>")
    print(f"{name}: {got} (expected {wanted})")
    if got != wanted:
        errors.append(f"{name}: expected {wanted}, got {got}")
if errors:
    raise SystemExit("Meson configuration mismatch:\n  " + "\n  ".join(errors))
PY

# ------------------------------------------------------------
# Show configuration
# ------------------------------------------------------------

echo
echo "========================================"
echo "mpv configuration"
echo "========================================"

meson configure "${BUILD_DIR}"

# ------------------------------------------------------------
# Build
# ------------------------------------------------------------

echo
echo "========================================"
echo "Building mpv"
echo "========================================"

meson compile \
    -C "${BUILD_DIR}" \
    -j"$(nproc)"

# ------------------------------------------------------------
# Install
# ------------------------------------------------------------

echo
echo "========================================"
echo "Installing mpv"
echo "========================================"

meson install \
    -C "${BUILD_DIR}"

# ------------------------------------------------------------
# Verify
# ------------------------------------------------------------

echo
echo "========================================"
echo "Verifying libmpv"
echo "========================================"

find "${PREFIX}" \
    -maxdepth 3 \
    -type f \
    \( \
        -name 'libmpv.a' \
        -o -name 'libmpv.dll.a' \
        -o -name 'libmpv-2.dll' \
    \) \
    -print

test -d "${PREFIX}/include/mpv"
test -f "${PREFIX}/bin/mpv.exe"
test -f "${PREFIX}/lib/libmpv.dll.a"
test -f "${PREFIX}/bin/libmpv-2.dll"

rm -rf "${PACKAGE_DIR}" "${PACKAGE_ARCHIVE}"
mkdir -p "${PACKAGE_DIR}/include"

cp -R "${PREFIX}/include/mpv" "${PACKAGE_DIR}/include/"
cp "${PREFIX}/lib/libmpv.dll.a" "${PACKAGE_DIR}/"
cp "${PREFIX}/bin/libmpv-2.dll" "${PACKAGE_DIR}/"

(
    cd "${BUILD_ROOT}"
    zip -r "${PACKAGE_ARCHIVE}" "${PACKAGE_NAME}" >/dev/null
)

test -s "${PACKAGE_ARCHIVE}"

echo
echo "Package created:"
echo "  ${PACKAGE_ARCHIVE}"

echo
echo "========================================"
echo "mpv build completed"
echo "========================================"

echo "PREFIX=${PREFIX}"
