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

# The fork links directly against VSScript.dll. Use runtime loading and retain
# only the VapourSynth compile dependencies so libmpv does not link it or Python.
# Git on Windows may check out both the source and patch with CRLF. Normalize
# both before git apply; a CRLF patch fails even against an LF source.
vapoursynth_patch="${WORK_ROOT}/mpv-vapoursynth-runtime-load.patch"
python - "${ROOT_DIR}/patches/mpv-vapoursynth-runtime-load.patch" "${vapoursynth_patch}" <<'PY'
from pathlib import Path
import sys

for path in (Path("meson.build"), Path("video/filter/vf_vapoursynth.c")):
    data = path.read_bytes()
    if b"\r\n" in data:
        path.write_bytes(data.replace(b"\r\n", b"\n"))
patch = Path(sys.argv[1]).read_bytes()
Path(sys.argv[2]).write_bytes(patch.replace(b"\r\n", b"\n"))
PY
if git apply --reverse --check "${vapoursynth_patch}" >/dev/null 2>&1; then
    echo "==> mpv VapourSynth runtime-load patch already applied"
elif git apply --check "${vapoursynth_patch}"; then
    git apply "${vapoursynth_patch}"
else
    echo "Cannot apply mpv VapourSynth runtime-load patch" >&2
    exit 1
fi

# Catch a misplaced patch before spending time on the Meson build.
python - <<'PY'
from pathlib import Path

source = Path("video/filter/vf_vapoursynth.c").read_text()
start = source.index("static int drv_vss_init(struct priv *p)")
end = source.index("static void drv_vss_uninit(struct priv *p)", start)
init = source[start:end]
assert "{\n#ifdef _WIN32" in init
assert init.count('GetProcAddress(p->vsscript_lib, "getVSScriptAPI")') == 1
assert 'p->vs_script_api = get_vsscript_api(VSSCRIPT_API_VERSION);' in init
assert source.count('p->vsscript_lib = LoadLibraryA(') == 1
PY

# MuJS is required by -Djavascript=enabled. The MSYS2 package is not
# consistently available on CI runners, so use the Meson WrapDB fallback.
mkdir -p subprojects
if [[ ! -f subprojects/mujs.wrap && ! -d subprojects/mujs ]]; then
    meson wrap install mujs
fi
meson subprojects download mujs

# ------------------------------------------------------------
# Configure
# ------------------------------------------------------------

rm -rf "${BUILD_DIR}"

echo
echo "========================================"
echo "Configuring mpv"
echo "========================================"

# Meson may use the C++ linker for static C++ dependencies. C link arguments
# do not apply to that driver, so set the static runtime policy for both.
meson setup "${BUILD_DIR}" \
    --prefix="${PREFIX}" \
    --libdir=lib \
    --buildtype=release \
    --default-library=shared \
    --prefer-static \
    -Dmujs:default_library=static \
    -Ddebug=true \
    -Db_ndebug=true \
    -Doptimization=3 \
    -Db_lto=true \
    -Dc_link_args="-static -static-libgcc -static-libstdc++" \
    -Dcpp_link_args="-static -static-libgcc -static-libstdc++" \
    -Dcplayer=true \
    -Dlibmpv=true \
    -Dbuild-date=false \
    -Dpdf-build=disabled \
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
    -Dvulkan=enabled

python - "${BUILD_DIR}" <<'PY'
import json
from pathlib import Path
import re
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
    "c_link_args": ["-static", "-static-libgcc", "-static-libstdc++"],
    "cpp_link_args": ["-static", "-static-libgcc", "-static-libstdc++"],
    "pdf-build": "disabled",
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

# Check the generated DLL link command before compiling all mpv objects.
targets = json.loads(subprocess.check_output(
    ["meson", "introspect", "--targets", build_dir], text=True
))
libmpv = next((target for target in targets if any(
    Path(filename).name.lower() == "libmpv-2.dll" for filename in target["filename"]
)), None)
if libmpv is None:
    raise SystemExit("Meson did not generate the libmpv DLL target")
link_args = [arg for group in libmpv["target_sources"] if "linker" in group
             for arg in group["parameters"]]
if not link_args:
    raise SystemExit("Could not read the libmpv DLL link arguments")
linker = next(group["linker"] for group in libmpv["target_sources"] if "linker" in group)
print("libmpv linker: " + " ".join(linker))
required_runtime_flags = {"-static", "-static-libgcc", "-static-libstdc++"}
missing_runtime_flags = required_runtime_flags.difference(link_args)
if missing_runtime_flags:
    raise SystemExit("libmpv link command is missing static runtime flags: "
                     + " ".join(sorted(missing_runtime_flags)))
print("libmpv link arguments: static MinGW runtimes enabled")
unexpected = [arg for arg in link_args if re.search(
    r"(?:^-l(?:python|vapoursynth|vsscript)|(?:^|[/\\])(?:lib)?"
    r"(?:python|vapoursynth|vsscript)[^/\\]*\.(?:a|lib|dll)$)", arg, re.I
)]
if unexpected:
    raise SystemExit("libmpv must load VapourSynth at runtime, but links: "
                     + " ".join(unexpected))
print("libmpv link arguments: no VapourSynth or Python libraries")
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

echo "==> Checking libmpv runtime DLL dependencies"
command -v objdump >/dev/null
mapfile -t runtime_dlls < <(objdump -p "${PREFIX}/bin/libmpv-2.dll" | sed -n 's/^[[:space:]]*DLL Name: //p')
((${#runtime_dlls[@]})) || { echo "Could not read libmpv DLL imports" >&2; exit 1; }
missing_runtime=()
for dll in "${runtime_dlls[@]}"; do
    echo "  ${dll}"
    if [[ -f "${PREFIX}/bin/${dll}" || -f "/mingw64/bin/${dll}" ]]; then
        missing_runtime+=("${dll}")
    fi
done
if ((${#missing_runtime[@]})); then
    printf 'libmpv requires external runtime DLL: %s\n' "${missing_runtime[@]}" >&2
    exit 1
fi

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
