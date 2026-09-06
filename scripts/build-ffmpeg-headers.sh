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
        git -C "${source}" init
        git -C "${source}" remote add origin "${url}"
        git -C "${source}" fetch --depth 1 origin "refs/tags/${ref}"
        git -C "${source}" checkout --detach FETCH_HEAD
    fi
    printf '%s\n' "${source}"
}

amf_source="$(clone_git amf-headers https://github.com/GPUOpen-LibrariesAndSDKs/AMF.git "${AMF_VERSION}")"
mkdir -p "${PREFIX}/include/AMF"
cp -R "${amf_source}/amf/public/include/." "${PREFIX}/include/AMF/"

nv_source="$(clone_git nvcodec-headers https://git.videolan.org/git/ffmpeg/nv-codec-headers.git "${NV_CODEC_HEADERS_VERSION}")"
make -C "${nv_source}" PREFIX="${PREFIX}" install

avisynth_source="$(clone_git avisynth-headers https://github.com/AviSynth/AviSynthPlus.git "${AVISYNTH_VERSION}")"
avisynth_header="$(find "${avisynth_source}" -type f -iname 'avisynth.h' -print -quit)"
if [[ -z "${avisynth_header}" ]]; then
    echo "AviSynth header was not found in ${avisynth_source}" >&2
    find "${avisynth_source}" -maxdepth 4 -type f \( -name '*.h' -o -name '*.hpp' \) -print >&2
    exit 1
fi
mkdir -p "${PREFIX}/include/avisynth"
find "${avisynth_source}" -type f \( -name '*.h' -o -name '*.hpp' \) -exec cp -f {} "${PREFIX}/include/avisynth/" \;

test -f "${PREFIX}/include/AMF/core/AMF.h"
test -f "${PREFIX}/include/ffnvcodec/nvEncodeAPI.h"
test -d "${PREFIX}/include/avisynth"

echo "==> FFmpeg headers installed"