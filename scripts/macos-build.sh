#!/usr/bin/env bash
# Build the OpenInstaCine camera module for Mac Catalyst.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
derived_data="${MACOS_DERIVED_DATA_PATH:-$repo_root/build/macos/DerivedData}"
configuration="${MACOS_CONFIGURATION:-Debug}"
exec xcodebuild \
  -project "$repo_root/ios/OpenInstaCine.xcodeproj" \
  -scheme OpenInstaCine \
  -configuration "$configuration" \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath "$derived_data" \
  "$@" build
