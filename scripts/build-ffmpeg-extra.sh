#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="${BUILD_ROOT:-${ROOT_DIR}/build}"
SRC_ROOT="${SRC_ROOT:-${BUILD_ROOT}/src}"
WORK_ROOT="${WORK_ROOT:-${BUILD_ROOT}/work}"
PREFIX="${PREFIX:-${BUILD_ROOT}/install}"

mkdir -p "${SRC_ROOT}" "${WORK_ROOT}" "${PREFIX}"

export ROOT_DIR BUILD_ROOT SRC_ROOT WORK_ROOT PREFIX
export PATH="${PREFIX}/bin:/mingw64/bin:${PATH}"
export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PREFIX}/share/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"
export CMAKE_PREFIX_PATH="${PREFIX}${CMAKE_PREFIX_PATH:+;${CMAKE_PREFIX_PATH}}"
export CPPFLAGS="-I${PREFIX}/include ${CPPFLAGS:-}"
export LDFLAGS="-L${PREFIX}/lib ${LDFLAGS:-}"

source "${ROOT_DIR}/config/versions.env"
source "${ROOT_DIR}/scripts/build-download.sh"

DOWNLOAD_ROOT="${BUILD_ROOT}/downloads/ffmpeg-extra"

JOBS="${JOBS:-$(nproc)}"

# zimg is bootstrapped from Git; release tarballs alone do not exercise these tools.
for tool in autoreconf autoconf automake aclocal libtoolize gperf; do
    command -v "${tool}" >/dev/null 2>&1 || {
        echo "Missing build tool: ${tool}. On MSYS2, install: pacman -S --needed autoconf automake libtool gperf" >&2
        exit 127
    }
done

clone_git() {
    local name="$1" url="$2" ref="$3"
    local source="${SRC_ROOT}/${name}"
    if [[ ! -d "${source}/.git" ]]; then
        rm -rf "${source}"
        # This function is used in command substitutions, so stdout must contain
        # only the source path. In particular, submodule checkout messages are
        # otherwise captured and make the caller's path invalid.
        git clone --depth 1 --branch "${ref}" --recurse-submodules --shallow-submodules \
            "${url}" "${source}" >&2
    fi
    printf '%s\n' "${source}"
}

build_cmake() {
    local name="$1" url="$2" ref="$3" source_subdir="$4" cmake_args="$5"
    local patch_file="${6:-}"
    local source build
    source="$(clone_git "${name}" "${url}" "${ref}")"
    if [[ -n "${patch_file}" ]]; then
        if git -C "${source}" apply --ignore-whitespace --reverse --check "${patch_file}" >/dev/null 2>&1; then
            echo "==> ${name}: patch already applied"
        elif git -C "${source}" apply --ignore-whitespace --check "${patch_file}" >/dev/null 2>&1; then
            git -C "${source}" apply --ignore-whitespace "${patch_file}"
        else
            echo "Cannot apply patch to ${name}: ${patch_file}" >&2
            sed -n '15,35p' "${source}/libvpl/src/windows/mfx_dispatcher_defs.h" >&2 || true
            return 1
        fi
    fi
    build="${WORK_ROOT}/${name}"
    rm -rf "${build}"
    cmake -S "${source}/${source_subdir}" -B "${build}" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DBUILD_SHARED_LIBS=OFF \
        ${cmake_args}
    cmake --build "${build}" -j"${JOBS}"
    cmake --install "${build}"
}

build_autotools_tar() {
    local name="$1" url="$2" archive_name="$3" source_dir="$4" configure_args="$5"
    local archive="${DOWNLOAD_ROOT}/${archive_name}"
    local source="${SRC_ROOT}/${source_dir}"
    download_archive "${archive}" "${url}"
    [[ -d "${source}" ]] || tar -xf "${archive}" -C "${SRC_ROOT}"
    cd "${source}"
    make distclean >/dev/null 2>&1 || true
    ./configure \
        --prefix="${PREFIX}" \
        --libdir="${PREFIX}/lib" \
        --enable-static \
        --disable-shared \
        ${configure_args}
    make -j"${JOBS}"
    make install
}

build_meson_tar() {
    local name="$1" url="$2" archive_name="$3" source_dir="$4"
    shift 4
    local archive="${DOWNLOAD_ROOT}/${archive_name}"
    local source="${SRC_ROOT}/${source_dir}"
    local build="${WORK_ROOT}/${name}"
    download_archive "${archive}" "${url}"
    [[ -d "${source}" ]] || tar -xf "${archive}" -C "${SRC_ROOT}"
    rm -rf "${build}"
    meson setup "${build}" "${source}" \
        --prefix="${PREFIX}" \
        --libdir=lib \
        --buildtype=release \
        --default-library=static \
        -Dprefer_static=true \
        "$@"
    meson compile -C "${build}" -j"${JOBS}"
    meson install -C "${build}"
}

build_autotools_git() {
    local name="$1" url="$2" ref="$3" configure_args="$4"
    local source
    source="$(clone_git "${name}" "${url}" "${ref}")"
    cd "${source}"
    make distclean >/dev/null 2>&1 || true
    if [[ -x ./autogen.sh ]]; then
        ./autogen.sh
    fi
    [[ -x ./configure ]] || {
        echo "Missing configure script for ${name}" >&2
        exit 1
    }
    ./configure \
        --prefix="${PREFIX}" \
        --libdir="${PREFIX}/lib" \
        --enable-static \
        --disable-shared \
        ${configure_args}
    make -j"${JOBS}"
    make install
}

build_cmake expat https://github.com/libexpat/libexpat.git "R_${EXPAT_VERSION//./_}" expat "-DEXPAT_BUILD_EXAMPLES=OFF -DEXPAT_BUILD_TESTS=OFF -DEXPAT_BUILD_TOOLS=OFF"
build_cmake libpng https://github.com/pnggroup/libpng.git "v${LIBPNG_VERSION}" . "-DPNG_TESTS=OFF"
build_cmake libssh https://git.libssh.org/projects/libssh.git "libssh-${LIBSSH_VERSION}" . \
    "-DWITH_EXAMPLES=OFF -DWITH_TESTING=OFF -DWITH_GSSAPI=OFF -DWITH_SERVER=OFF -DWITH_NACL=OFF -DWITH_ZLIB=ON -DOPENSSL_USE_STATIC_LIBS=TRUE"

# libssh 0.11.x exports its static requirements to CMake consumers only.
# pkg-config consumers also need LIBSSH_STATIC to avoid __imp_sftp_init,
# plus the crypto, compression, threading and Windows networking libraries.
ssh_pc="${PREFIX}/lib/pkgconfig/libssh.pc"
sed -i '/^Cflags:/ s/$/ -DLIBSSH_STATIC/' "${ssh_pc}"
cat >> "${ssh_pc}" <<'EOF'
Requires.private: libcrypto zlib
Libs.private: -lpthread -liphlpapi -lws2_32
EOF

# Check the same API as FFmpeg before doing more builds or caching the prefix.
ssh_probe="${WORK_ROOT}/libssh-link-check.exe"
printf '%s\n' '#include <libssh/sftp.h>' \
    'int main(void) { return sftp_init((sftp_session)0); }' \
    | gcc -x c - -x none -o "${ssh_probe}" $(pkg-config --cflags --static libssh) \
        $(pkg-config --libs --static libssh)
rm -f "${ssh_probe}"

build_cmake srt https://github.com/Haivision/srt.git "v${SRT_VERSION}" . "-DENABLE_APPS=OFF -DENABLE_TESTING=OFF -DENABLE_SHARED=OFF -DCMAKE_POLICY_VERSION_MINIMUM=3.5"
build_autotools_git zimg https://github.com/sekrit-twc/zimg.git "release-${LIBZIMG_VERSION}" ""
build_cmake mysofa https://github.com/hoene/libmysofa.git "v${LIBMYSOFA_VERSION}" . "-DBUILD_TESTS=OFF -DBUILD_SHARED_LIBS=OFF -DCMAKE_POLICY_VERSION_MINIMUM=3.5"
build_cmake libvpl https://github.com/oneapi-src/oneVPL.git "v${LIBVPL_VERSION}" . \
    "-DINSTALL_LIB=ON -DBUILD_EXAMPLES=OFF -DBUILD_TESTS=OFF" \
    "${ROOT_DIR}/patches/libvpl-mingw-wcs-fallback.patch"
build_cmake openal-soft https://github.com/kcat/openal-soft.git "${OPENAL_VERSION}" . "-DLIBTYPE=STATIC -DALSOFT_EXAMPLES=OFF -DALSOFT_TESTS=OFF -DALSOFT_UTILS=OFF"

# OpenAL's static pkg-config metadata includes AL_LIBTYPE_STATIC and backend
# libraries, but omits the COM/GUID libraries and the C++ runtime needed by
# MinGW C consumers. Keep these after OpenAL32 in the static link command.
openal_pc="${PREFIX}/lib/pkgconfig/openal.pc"
sed -i '/^Libs.private:/ s/$/ -lole32 -luuid -lstdc++/' "${openal_pc}"

# Match FFmpeg's gcc/pkg-config probe before caching the dependency prefix.
openal_probe="${WORK_ROOT}/openal-link-check.exe"
printf '%s\n' '#include <AL/al.h>' \
    'int main(void) { return alGetError(); }' \
    | gcc -x c - -x none -o "${openal_probe}" $(pkg-config --cflags --static openal) \
        $(pkg-config --libs --static openal)
rm -f "${openal_probe}"

build_autotools_tar \
    libmodplug \
    "https://downloads.sourceforge.net/project/modplug-xmms/libmodplug/${LIBMODPLUG_VERSION}/libmodplug-${LIBMODPLUG_VERSION}.tar.gz" \
    "libmodplug-${LIBMODPLUG_VERSION}.tar.gz" \
    "libmodplug-${LIBMODPLUG_VERSION}" \
    ""

# The public header defaults to dllimport on Windows unless static use is
# declared. Propagate that declaration to FFmpeg's pkg-config check and build.
modplug_pc="${PREFIX}/lib/pkgconfig/libmodplug.pc"
sed -i '/^Cflags:/ s/$/ -DMODPLUG_STATIC/' "${modplug_pc}"

build_autotools_tar \
    fontconfig \
    "https://www.freedesktop.org/software/fontconfig/release/fontconfig-${FONTCONFIG_VERSION}.tar.xz" \
    "fontconfig-${FONTCONFIG_VERSION}.tar.xz" \
    "fontconfig-${FONTCONFIG_VERSION}" \
    "--disable-docs --disable-libxml2 --disable-nls"

# libbluray 1.4.x uses Meson; 1.4.1 fixes static linking on Windows with FreeType.
build_meson_tar \
    libbluray \
    "https://download.videolan.org/pub/videolan/libbluray/${LIBBLURAY_VERSION}/libbluray-${LIBBLURAY_VERSION}.tar.xz" \
    "libbluray-${LIBBLURAY_VERSION}.tar.xz" \
    "libbluray-${LIBBLURAY_VERSION}" \
    -Dbdj_jar=disabled \
    -Denable_docs=false \
    -Denable_tools=false \
    -Denable_examples=false \
    -Denable_devtools=false

# Meson can put absolute MinGW archive paths in Libs.private. FFmpeg's
# configure moves those paths ahead of -lbluray, where --as-needed cannot
# resolve libbluray's GDI references. Keep them as linker flags instead.
bluray_pc="${PREFIX}/lib/pkgconfig/libbluray.pc"
sed -E -i \
    -e 's@[^ ]*/libgdi32\.a@-lgdi32@g' \
    -e 's@[^ ]*/libssp\.a@-lssp@g' \
    "${bluray_pc}"

build_autotools_tar \
    libdvdread \
    "https://download.videolan.org/pub/videolan/libdvdread/${LIBDVDREAD_VERSION}/libdvdread-${LIBDVDREAD_VERSION}.tar.bz2" \
    "libdvdread-${LIBDVDREAD_VERSION}.tar.bz2" \
    "libdvdread-${LIBDVDREAD_VERSION}" \
    ""

build_autotools_tar \
    libdvdnav \
    "https://download.videolan.org/pub/videolan/libdvdnav/${LIBDVDNAV_VERSION}/libdvdnav-${LIBDVDNAV_VERSION}.tar.bz2" \
    "libdvdnav-${LIBDVDNAV_VERSION}.tar.bz2" \
    "libdvdnav-${LIBDVDNAV_VERSION}" \
    ""

for library in expat libpng libssh srt zimg libmysofa vpl openal fontconfig libbluray dvdread dvdnav libmodplug; do
    pkg-config --exists "${library}" || {
        echo "Missing pkg-config package: ${library}" >&2
        exit 1
    }
done

modplug_probe="${WORK_ROOT}/libmodplug-link-check.exe"
printf '%s\n' '#include <libmodplug/modplug.h>' \
    'int main(void) { return ModPlug_Load(0, 0) != 0; }' \
    | gcc -x c - -x none -o "${modplug_probe}" $(pkg-config --cflags --static libmodplug) \
        $(pkg-config --libs --static libmodplug)
rm -f "${modplug_probe}"

# Match FFmpeg's static fontconfig link check before saving the prefix cache.
fontconfig_probe="${WORK_ROOT}/fontconfig-link-check.exe"
printf '%s\n' '#include <fontconfig/fontconfig.h>' 'int main(void) { return FcInit() ? 0 : 1; }' \
    | gcc -x c - -x none -o "${fontconfig_probe}" $(pkg-config --cflags --static fontconfig) \
        $(pkg-config --libs --static fontconfig)
rm -f "${fontconfig_probe}"

# FFmpeg's configure checks bd_open by linking, not just by finding libbluray.pc.
# Catch a broken static dependency chain before caching this install prefix.
bluray_probe="${WORK_ROOT}/libbluray-link-check.exe"
printf '%s\n' '#include <libbluray/bluray.h>' '#include <stdint.h>' \
    'long check_bd_open(void) { return (long) bd_open; }' \
    'int main(void) { return ((intptr_t)check_bd_open) & 0xFFFF; }' \
    | gcc -x c - -x none -o "${bluray_probe}" $(pkg-config --cflags --static libbluray) \
        $(pkg-config --libs --static libbluray)
rm -f "${bluray_probe}"

echo "==> FFmpeg extra dependencies installed"
