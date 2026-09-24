#!/usr/bin/env bash
# Re-sync OpenInstaCine's iOS shell and shared engine from a local OpenPocketCine checkout.
#
#   scripts/sync-openpocketcine.sh            # uses ../OpenPocketCine
#   OPENPOCKETCINE_PATH=/path scripts/sync-openpocketcine.sh
#
# Upstream files are copied verbatim, renamed to OpenInstaCine, then brand hunks are applied
# (scripts/apply-openpocketcine-overlays.py). Luna-owned files are never overwritten.
# Review `git diff` afterwards: changed upstream code near a Luna seam needs a human.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${OPENPOCKETCINE_PATH:-$ROOT/../OpenPocketCine}"
[[ -f "$SRC/Package.swift" && -d "$SRC/ios/OpenPocketCine" ]] || {
  echo "error: OpenPocketCine not found at $SRC (set OPENPOCKETCINE_PATH)" >&2; exit 1; }

# Files OpenInstaCine owns inside the copied trees (Luna seams and brand assets).
LUNA_OWNED=(
  OpenInstaCine/CameraSession.swift
  OpenInstaCine/CameraSessionControls.swift
  OpenInstaCine/CameraMedia.swift
  OpenInstaCine/LunaShellMapping.swift
  OpenInstaCine/LunaThumbnailImage.swift
  OpenInstaCine/DebugRemote.swift
  OpenInstaCine/OpenInstaCineBrand.swift
  OpenInstaCine/OsmoCameraPageAdapter.swift
  OpenInstaCine/OsmoMonitorPresentation.swift
  OpenInstaCine/Assets.xcassets
  OpenInstaCine/Resources
  OpenInstaCineWatch/Assets.xcassets
  LunaOfficialUITests
)

# Upstream files that only test or serve the Osmo DUML session. Deleted after every sync.
OSMO_ONLY=(
  OpenInstaCineTests/MediaLiveRecoveryOwnershipTests.swift
  OpenInstaCineTests/SessionRecoveryLifecycleTests.swift
  OpenInstaCineTests/ConnectionLifecycleRegressionTests.swift
  OpenInstaCineTests/EVMeterAssistTests.swift
  OpenInstaCineTests/GimbalModeSelectionTests.swift
  OpenInstaCineTests/HandshakeBindTests.swift
  OpenInstaCineTests/CameraDialReconciliationTests.swift
)

rename_tree() {
  local dir="$1"
  find "$dir" -depth -name "*OpenPocketCine*" | while read -r path; do
    mv "$path" "${path%/*}/$(basename "$path" | sed 's/OpenPocketCine/OpenInstaCine/g')"
  done
  LC_ALL=C grep -rlI -e OpenPocketCine -e openpocketcine "$dir" | while read -r file; do
    LC_ALL=C sed -i '' -e 's/OpenPocketCine/OpenInstaCine/g' -e 's/openpocketcine/openinstacine/g' "$file"
  done
}

echo "Syncing from $(git -C "$SRC" rev-parse --short HEAD): $(git -C "$SRC" log -1 --format=%s)"

# 1. Shared engine packages and their tests: byte-identical upstream.
for dir in MonitorPresentation MonitorUI OpenPocketViewCore CJNI OpenPocketCineAndroidFacade; do
  rsync -a --delete --exclude .DS_Store "$SRC/Sources/$dir/" "$ROOT/Sources/$dir/"
done
for dir in "$SRC"/Tests/*/; do
  name="$(basename "$dir")"
  rsync -a --delete --exclude .DS_Store "$dir" "$ROOT/Tests/$name/"
done

# 2. iOS shell into a staging copy, renamed, then merged without touching Luna files.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
rsync -a --exclude .DS_Store --exclude '*.xcodeproj' --exclude xcuserdata \
  --exclude '*.local.xcconfig' "$SRC/ios/" "$STAGE/ios/"
rename_tree "$STAGE/ios"
EXCLUDES=()
for owned in "${LUNA_OWNED[@]}"; do EXCLUDES+=(--exclude "/$owned"); done
rsync -a --exclude .DS_Store "${EXCLUDES[@]}" "$STAGE/ios/" "$ROOT/ios/"
for gone in "${OSMO_ONLY[@]}"; do rm -f "$ROOT/ios/$gone"; done

# 3. Tools the Xcode build phases call.
for tool in stamp-source-revision.sh build-identity.py pull-control-log.sh analyze-live-log.py; do
  cp "$SRC/tools/$tool" "$ROOT/tools/$tool"
done

# 4. Brand hunks (accent token, project wiring, launch hooks). Fails loudly if upstream moved.
/usr/bin/python3 "$ROOT/scripts/apply-openpocketcine-overlays.py"

git -C "$SRC" rev-parse HEAD > "$ROOT/docs/implementation/openpocketcine-sync-commit.txt"
echo "Done. Next: git diff, (cd ios && xcodegen generate), build, and re-check Luna seams."
