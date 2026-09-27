#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="${BUILD_ROOT:-${ROOT_DIR}/build}"
SRC_ROOT="${SRC_ROOT:-${BUILD_ROOT}/src}"
PREFIX="${PREFIX:-${BUILD_ROOT}/install}"

mkdir -p "${SRC_ROOT}" "${PREFIX}/include"

export ROOT_DIR BUILD_ROOT SRC_ROOT PREFIX
export PATH="${PREFIX}/bin:/mingw64/bin:${PATH}"

source "${ROOT_DIR}/config/versions.env"

clone_git() {
    local name="$1" url="$2" ref="$3"
    local source="${SRC_ROOT}/${name}"
    if [[ ! -d "${source}/.git" ]]; then
        rm -rf "${source}"
        mkdir -p "${source}"
        git -C "${source}" init --quiet
        git -C "${source}" remote add origin "${url}"
    fi
    # Reused source directories must follow versions.env after a version bump.
    # Keep stdout reserved for the source path captured by the caller.
    git -C "${source}" fetch --depth 1 origin "refs/tags/${ref}" >&2
    git -C "${source}" checkout --detach FETCH_HEAD >&2
    printf '%s\n' "${source}"
}

amf_source="$(clone_git amf-headers https://github.com/GPUOpen-LibrariesAndSDKs/AMF.git "${AMF_VERSION}")"
mkdir -p "${PREFIX}/include/AMF"
cp -R "${amf_source}/amf/public/include/." "${PREFIX}/include/AMF/"

nv_source="$(clone_git nvcodec-headers https://git.videolan.org/git/ffmpeg/nv-codec-headers.git "${NV_CODEC_HEADERS_VERSION}")"
make -C "${nv_source}" PREFIX="${PREFIX}" install

avisynth_source="$(clone_git avisynth-headers https://github.com/AviSynth/AviSynthPlus.git "${AVISYNTH_VERSION}")"
# AviSynth's Version.cmake calls `git describe --tags`. Preserve the current
# checkout while ensuring the fetched version tag is available to that call.
git -C "${avisynth_source}" fetch --depth 1 origin "+refs/tags/${AVISYNTH_VERSION}:refs/tags/${AVISYNTH_VERSION}"
avisynth_build="${BUILD_ROOT}/work/avisynth-headers"
cmake -S "${avisynth_source}" -B "${avisynth_build}" -G Ninja \
    -DHEADERS_ONLY=ON \
    -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
    -DCMAKE_INSTALL_INCLUDEDIR=include
cmake --build "${avisynth_build}" --target VersionGen
cmake --install "${avisynth_build}"

test -f "${PREFIX}/include/AMF/core/Factory.h"
test -f "${PREFIX}/include/AMF/core/Version.h"
test -f "${PREFIX}/include/ffnvcodec/nvEncodeAPI.h"
test -f "${PREFIX}/include/avisynth/avisynth_c.h"
test -f "${PREFIX}/include/avisynth/avs/config.h"
test -f "${PREFIX}/include/avisynth/avs/version.h"
test -f "${PREFIX}/include/avisynth/avs/arch.h"

echo "==> FFmpeg headers installed"
