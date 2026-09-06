#!/usr/bin/env bash

# Download to a temporary file so interrupted transfers never become cache hits.
download_archive() {
    local archive="$1" url="$2"
    local candidate temporary
    local -a urls=("${url}")
    if [[ "${url}" == https://download.videolan.org/pub/videolan/* ]]; then
        urls+=("https://ftp.osuosl.org/pub/videolan/${url#https://download.videolan.org/pub/videolan/}")
    fi

    if [[ -f "${archive}" ]] && tar -tf "${archive}" >/dev/null 2>&1; then
        echo "==> Using cached archive: ${archive}"
        return 0
    fi

    mkdir -p "$(dirname "${archive}")"
    temporary="$(mktemp "${archive}.part.XXXXXX")" || return 1
    for candidate in "${urls[@]}"; do
        echo "==> Downloading ${candidate}"
        if curl -fsSL --connect-timeout 15 --max-time 300 \
            --retry 2 --retry-delay 2 --retry-connrefused \
            -o "${temporary}" "${candidate}"; then
            if tar -tf "${temporary}" >/dev/null 2>&1; then
                mv -f "${temporary}" "${archive}"
                return 0
            fi
            echo "Invalid archive from ${candidate}" >&2
        fi
        echo "Download failed: ${candidate}" >&2
    done
    rm -f "${temporary}"
    echo "All download sources failed for ${archive}" >&2
    return 1
}
