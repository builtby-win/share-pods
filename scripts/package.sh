#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

: "${VERSION:?package.sh: VERSION is required}"
CONFIGURATION="${CONFIGURATION:-Release}"
app="build/Build/Products/${CONFIGURATION}/SharePods.app"
zip="dist/SharePods-${VERSION}.zip"

mkdir -p dist
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
