#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

CONFIGURATION="${CONFIGURATION:-Release}"

xcodebuild build -project SharePods.xcodeproj -scheme SharePods -configuration "$CONFIGURATION" -derivedDataPath build
