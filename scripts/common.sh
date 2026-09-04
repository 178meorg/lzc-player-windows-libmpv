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

export CMAKE_PREFIX_PATH="${PREFIX}${CMAKE_PREFIX_PATH:+;${CMAKE_PREFIX_PATH}}"

export CPPFLAGS="-I${PREFIX}/include ${CPPFLAGS:-}"
export LDFLAGS="-L${PREFIX}/lib ${LDFLAGS:-}"

echo "ROOT_DIR=${ROOT_DIR}"
echo "PREFIX=${PREFIX}"
echo "PATH=${PATH}"
echo "PKG_CONFIG_PATH=${PKG_CONFIG_PATH}"