#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

tool="$(find_sparkle_tool generate_keys)" || {
    printf 'Could not find Sparkle generate_keys under DerivedData/SourcePackages/checkouts.\n' >&2
    exit 1
}

"$tool"

cat >&2 <<'EOF'
Keep the private key outside git. If you export it, store it in an encrypted vault or keychain export, not in the repository.
EOF
