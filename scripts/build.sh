#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [[ -f "$repo_root/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$repo_root/.env"
  set +a
fi
CONFIGURATION="${CONFIGURATION:-Release}"


signing_settings=()
if [[ -n "${APPLE_TEAM_ID:-}" && "$CONFIGURATION" == "Release" ]]; then
  signing_settings=(DEVELOPMENT_TEAM="$APPLE_TEAM_ID" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" PROVISIONING_PROFILE_SPECIFIER= CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO OTHER_CODE_SIGN_FLAGS=--timestamp)
fi


xcodebuild build -project SharePods.xcodeproj -scheme SharePods -configuration "$CONFIGURATION" -derivedDataPath build "${signing_settings[@]}"
