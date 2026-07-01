#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

: "${VERSION:?release-github.sh: VERSION is required}"
GH_REPO="${GH_REPO:-builtby-win/share-pods}"

tag="v${VERSION}"
zip="dist/SharePods-${VERSION}.zip"
appcast="dist/appcast.xml"
assets=("$zip")

if [[ -f "$appcast" ]]; then
  assets+=("$appcast")
fi

if gh release view "$tag" --repo "$GH_REPO" >/dev/null 2>&1; then
  gh release upload "$tag" "${assets[@]}" --repo "$GH_REPO" --clobber
else
  gh release create "$tag" "${assets[@]}" --repo "$GH_REPO" --title "$tag" --notes ""
fi
