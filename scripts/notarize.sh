#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

: "${VERSION:?notarize.sh: VERSION is required}"
: "${APPLE_ID:?notarize.sh: APPLE_ID is required}"
: "${APPLE_TEAM_ID:?notarize.sh: APPLE_TEAM_ID is required}"
: "${APPLE_APP_PASSWORD:?notarize.sh: APPLE_APP_PASSWORD is required}"

CONFIGURATION="${CONFIGURATION:-Release}"
app="build/Build/Products/${CONFIGURATION}/SharePods.app"
zip="dist/SharePods-${VERSION}.zip"

xcrun notarytool submit "$zip" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" --wait
xcrun stapler staple "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
