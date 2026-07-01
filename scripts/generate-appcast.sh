#!/usr/bin/env bash
set -euo pipefail

: "${VERSION:?VERSION is required}"
GH_REPO="${GH_REPO:-builtby-win/share-pods}"
: "${SPARKLE_PRIVATE_KEY:?SPARKLE_PRIVATE_KEY is required}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="$repo_root/dist"
output_appcast="$output_dir/appcast.xml"
download_url_prefix="https://github.com/${GH_REPO}/releases/download/v${VERSION}/"

find_sparkle_tool() {
    local tool_name="$1"
    local root candidate

    for root in "${DERIVED_DATA_PATH:-}" "${DERIVED_DATA_DIR:-}" "$repo_root/build" "$HOME/Library/Developer/Xcode/DerivedData"; do
        [[ -n "$root" && -d "$root/SourcePackages/checkouts" ]] || continue
        candidate="$(find "$root/SourcePackages/checkouts" -type f -name "$tool_name" -perm -111 -print -quit 2>/dev/null || true)"
        if [[ -n "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    if command -v "$tool_name" >/dev/null 2>&1; then
        command -v "$tool_name"
        return 0
    fi

    return 1
}

tool="$(find_sparkle_tool generate_appcast)" || {
    printf 'Could not find Sparkle generate_appcast under DerivedData/SourcePackages/checkouts.\n' >&2
    exit 1
}

mkdir -p "$output_dir"
printf '%s\n' "$SPARKLE_PRIVATE_KEY" | "$tool" \
    --ed-key-file - \
    --download-url-prefix "$download_url_prefix" \
    -o "$output_appcast" \
    "$output_dir"
