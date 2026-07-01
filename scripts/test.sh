#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

xcodebuild test -project SharePods.xcodeproj -scheme SharePods -destination 'platform=macOS' -derivedDataPath build
