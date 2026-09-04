#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "${ROOT_DIR}/config/versions.env"

BUILD_ROOT="${ROOT_DIR}/build"
SRC_ROOT="${BUILD_ROOT}/src"
INSTALL_PREFIX="${BUILD_ROOT}/install"

FFMPEG_NAME="ffmpeg-${FFMPEG_VERSION}"
FFMPEG_TARBALL="${SRC_ROOT}/${FFMPEG_NAME}.tar.xz"
FFMPEG_SOURCE="${SRC_ROOT}/${FFMPEG_NAME}"

FFMPEG_URL="https://ffmpeg.org/releases/${FFMPEG_NAME}.tar.xz"

export PATH="/mingw64/bin:${PATH}"

# 让后面的依赖统一从我们自己的 PREFIX 查找
export PKG_CONFIG_PATH="${INSTALL_PREFIX}/lib/pkgconfig"

log() {
    printf '\n\033[1;32m==> %s\033[0m\n' "$*"
}

die() {
    printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2
    exit 1
}

# ------------------------------------------------------------
# Environment
# ------------------------------------------------------------

log "Checking environment"

if [[ "${MSYSTEM:-}" != "MINGW64" ]]; then
    die "This script must run in MSYS2 MINGW64."
fi

required_commands=(
    curl
    tar
    make
    gcc
    g++
    pkg-config
    nasm
    yasm
)

for cmd in "${required_commands[@]}"; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        die "Required command not found: ${cmd}"
    fi
done

echo "MSYSTEM          = ${MSYSTEM}"
echo "FFmpeg version   = ${FFMPEG_VERSION}"
echo "Root             = ${ROOT_DIR}"
echo "Build root       = ${BUILD_ROOT}"
echo "Install prefix   = ${INSTALL_PREFIX}"
echo "CC               = ${CC:-gcc}"
echo "CXX              = ${CXX:-g++}"

# ------------------------------------------------------------
# Directories
# ------------------------------------------------------------

mkdir -p \
    "${SRC_ROOT}" \
    "${INSTALL_PREFIX}"

# ------------------------------------------------------------
# Download
# ------------------------------------------------------------

log "Downloading FFmpeg ${FFMPEG_VERSION}"

if [[ ! -f "${FFMPEG_TARBALL}" ]]; then
    curl \
        --fail \
        --location \
        --retry 5 \
        --retry-delay 2 \
        --connect-timeout 20 \
        --output "${FFMPEG_TARBALL}" \
        "${FFMPEG_URL}"
else
    echo "Already downloaded:"
    echo "  ${FFMPEG_TARBALL}"
fi

# ------------------------------------------------------------
# Extract
# ------------------------------------------------------------

log "Extracting FFmpeg"

if [[ ! -d "${FFMPEG_SOURCE}" ]]; then
    tar -xf "${FFMPEG_TARBALL}" -C "${SRC_ROOT}"
else
    echo "Source already exists:"
    echo "  ${FFMPEG_SOURCE}"
fi

cd "${FFMPEG_SOURCE}"

# ------------------------------------------------------------
# Clean
# ------------------------------------------------------------

log "Cleaning previous build"

make distclean >/dev/null 2>&1 || true

# ------------------------------------------------------------
# Configure
# ------------------------------------------------------------

log "Configuring FFmpeg"

./configure \
    --prefix="${INSTALL_PREFIX}" \
    --target-os=mingw32 \
    --arch=x86_64 \
    --enable-shared \
    --disable-static \
    --disable-debug \
    --disable-doc \
    --disable-programs \
    --enable-pic

# ------------------------------------------------------------
# Build
# ------------------------------------------------------------

log "Building FFmpeg"

JOBS="${JOBS:-$(nproc)}"

echo "Using ${JOBS} parallel jobs"

make -j"${JOBS}"

# ------------------------------------------------------------
# Install
# ------------------------------------------------------------

log "Installing FFmpeg"

make install

# ------------------------------------------------------------
# Verify
# ------------------------------------------------------------

log "Verifying FFmpeg"

required_libraries=(
    libavcodec
    libavformat
    libavutil
    libavfilter
    libswresample
    libswscale
)

for lib in "${required_libraries[@]}"; do
    if ! pkg-config --exists "${lib}"; then
        die "pkg-config package not found: ${lib}"
    fi

    version="$(pkg-config --modversion "${lib}")"

    echo "${lib}: ${version}"
done

echo
echo "FFmpeg libraries:"

find "${INSTALL_PREFIX}/lib" \
    -maxdepth 1 \
    -type f \
    -name '*.dll.a' \
    -printf '  %f\n' \
    | sort

echo
echo "FFmpeg DLLs:"

find "${INSTALL_PREFIX}/bin" \
    -maxdepth 1 \
    -type f \
    -name '*.dll' \
    -printf '  %f\n' \
    | sort

echo
echo "Headers:"

find "${INSTALL_PREFIX}/include" \
    -maxdepth 2 \
    -type f \
    -name '*.h' \
    | head -20

log "FFmpeg ${FFMPEG_VERSION} build completed"

echo
echo "PREFIX:"
echo "  ${INSTALL_PREFIX}"