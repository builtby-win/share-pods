#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

if [[ -f "$repo_root/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$repo_root/.env"
  set +a
fi

"$script_dir/test.sh"
"$script_dir/build.sh"
"$script_dir/package.sh"

if [[ "${SKIP_NOTARIZE:-0}" != 1 ]]; then
  "$script_dir/notarize.sh"
fi

if [[ "${SKIP_GITHUB:-0}" != 1 ]]; then
  if [[ "${SKIP_SPARKLE:-0}" != 1 && -x "$script_dir/generate-appcast.sh" ]]; then
    "$script_dir/generate-appcast.sh"
  fi

  "$script_dir/release-github.sh"
fi
