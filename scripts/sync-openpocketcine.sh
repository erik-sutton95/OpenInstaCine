#!/usr/bin/env bash
# Re-sync OpenInstaCine's iOS presentation shell from a local OpenPocketCine checkout.
#
#   scripts/sync-openpocketcine.sh [--dry-run]     # uses ../OpenPocketCine HEAD
#   OPENPOCKETCINE_PATH=/path scripts/sync-openpocketcine.sh
#   OLD_COMMIT=<sha> scripts/sync-openpocketcine.sh --dry-run   # pretend the last sync was <sha>
#   NEW_COMMIT=<sha> scripts/sync-openpocketcine.sh             # sync to <sha> instead of HEAD
#
# Scope (RELEASE-01; docs/implementation/openpocketcine-foundation.md, "Sync scope"): ios/
# and three neutral tools, nothing else. Shared code reaches this app only through the pinned
# OpenCine platform package (../OpenCine: MonitorUI, OpenCineCore with Media/Motion/Relay/Apple/
# FrameIO, the Android :vulkan renderer and the Insta360 products), never through this script. The Swift core (Package.swift,
# Sources/, Tests/) and Apps/Android are OpenInstaCine-owned: upstream's core now depends on
# OpenCineDJI, which this app does not link, and ours carries the STATE-01 Luna edits.
#
# Three-way update. The "renamed upstream" tree (ios/ renamed to OpenInstaCine, Luna-owned and
# DJI-only files dropped, brand overlays applied by scripts/apply-openpocketcine-overlays.py,
# plus TOOLS) is built at the last synced commit and at upstream HEAD. The old->new diff is
# applied with `git apply --3way`, so our edits to upstream-derived files survive and real
# overlaps come out as conflicts. A file the last synced upstream had but this repository has
# deleted (moved to a shared package, Osmo-only or DJI-only) is never patched or brought back.
# Commit or stash the paths being synced first: --3way uses the index. After editing the
# overlay script, run it once by hand; it is baked into both trees.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${OPENPOCKETCINE_PATH:-$ROOT/../OpenPocketCine}"
COMMIT_FILE="$ROOT/docs/implementation/openpocketcine-sync-commit.txt"
DRY=false
case "${1:-}" in --dry-run) DRY=true ;; "") ;; *) echo "usage: $0 [--dry-run]" >&2; exit 2 ;; esac
[[ -f "$SRC/Package.swift" && -d "$SRC/ios/OpenPocketCine" ]] || {
  echo "error: OpenPocketCine not found at $SRC (set OPENPOCKETCINE_PATH)" >&2; exit 1; }
OLD="$(git -C "$SRC" rev-parse --verify "${OLD_COMMIT:-$(cat "$COMMIT_FILE")}^{commit}")"
NEW="$(git -C "$SRC" rev-parse --verify "${NEW_COMMIT:-HEAD}^{commit}")"

# Files OpenInstaCine owns inside ios/ (Luna seams, brand assets, package graph). Never touched
# by a sync; upstream edits to them are reported for porting by hand. Luna protocol and Apple
# adapter code lives in the sibling OpenCine package (Insta360Protocol, Insta360Apple).
LUNA_OWNED=(
  OpenInstaCine/CameraSession.swift
  OpenInstaCine/CameraSessionControls.swift
  OpenInstaCine/CameraMedia.swift
  OpenInstaCine/LunaShellMapping.swift
  OpenInstaCine/LunaThumbnailImage.swift
  OpenInstaCine/DebugRemote.swift
  # SHELL-03 I-1: the root, covers and monitor lifetime are OpenCineAppKit's AppShell and
  # ShellModel, the common controls its MonitorControlModel. What is left here is this app's
  # composition and typed adapters; upstream edits are ported by hand until I-6 retires the sync.
  OpenInstaCine/AppRoot.swift
  OpenInstaCine/CamerasExperience.swift
  OpenInstaCine/CameraSessionCore.swift
  OpenInstaCine/OpenInstaCineBrand.swift
  OpenInstaCine/OsmoMonitorPresentation.swift
  # SHELL-03 I-2: shared monitor placement, status and guarded capture widgets. These
  # files now compose native/integration slots around OpenCine; keep that adoption.
  OpenInstaCine/LiveViewScreen.swift
  OpenInstaCine/FieldMonitorChrome.swift
  OpenInstaCine/LiveCameraControlBar.swift
  OpenInstaCine/LiveRecordButton.swift
  OpenInstaCine/LiveDispToggle.swift
  OpenInstaCine/LiveLockButton.swift
  OpenInstaCine/LiveSystemChrome.swift
  OpenInstaCine/CaptureControlSheets.swift
  OpenInstaCine/CaptureQuickControl.swift
  OpenInstaCine/LiveMonitorLayout.swift
  OpenInstaCine/MonitorUIReview.swift
  OpenInstaCineTests/MonitorCanvasObservationTests.swift
  OpenInstaCineUITests/MonitorUIFlowTests.swift
  # SHELL-03 I-3: shared sampling math and scoped native publication. Keep the
  # source adapters and generation checks; donor publishers cannot be restored.
  OpenInstaCine/LiveFrameSample.swift
  OpenInstaCine/LiveScopes.swift
  OpenInstaCine/ScopePanelPlacement.swift
  OpenInstaCine/ScopeTraceMetalView.swift
  OpenInstaCine/Assists/WaveformAssist.swift
  OpenInstaCine/Assists/ParadeAssist.swift
  OpenInstaCine/Assists/VectorscopeAssist.swift
  OpenInstaCine/HevcDecoder.swift
  OpenInstaCine/LiveDecodeMetrics.swift
  OpenInstaCine/VideoView.swift
  OpenInstaCine/PlaybackFeed.swift
  OpenInstaCine/LiveMonitorFx.swift
  OpenInstaCine/LiveMonitorLooks.swift
  OpenInstaCine/FeedWorkingRaster.swift
  OpenInstaCine/FeedPresentScaler.swift
  OpenInstaCine/FeedSuperResolution.swift
  OpenInstaCine/FeedUpscale.swift
  OpenInstaCine/LiveAssists.swift
  OpenInstaCine/MonitorVideoBackdrop.swift
  OpenInstaCine/Assists/AssistInspectorImageRenderer.swift
  OpenInstaCine/Assists/FalseColorAssist.swift
  OpenInstaCine/Assists/HistogramAssist.swift
  OpenInstaCine/Assists/NDAssist.swift
  OpenInstaCine/Assists/TrafficLightsAssist.swift
  OpenInstaCine/MediaPlayer.swift
  OpenInstaCine/WatcherRelayClient.swift
  OpenInstaCine/Assists/AssistInspectorPreview.swift
  OpenInstaCineTests/AssistInspectorLifecycleTests.swift
  OpenInstaCineTests/AssistInspectorPreviewTests.swift
  OpenInstaCineTests/HistogramAssistTests.swift
  OpenInstaCineTests/DecoderGenerationTests.swift
  OpenInstaCineTests/FirstConnectTests.swift
  OpenInstaCineTests/LiveFrameSampleTests.swift
  OpenInstaCineTests/FalseColorAssistTests.swift
  OpenInstaCineTests/LiveFeedOrientationTests.swift
  OpenInstaCineTests/FeedPresentationTests.swift
  OpenInstaCineTests/MonitorBackdropLifecycleTests.swift
  OpenInstaCineTests/ScopePublicationOwnershipTests.swift
  OpenInstaCineTests/PlaybackAssistTests.swift
  OpenInstaCineTests/VideoDisplayOwnershipTests.swift
  # What is left of upstream's startup chrome once the wizard moved to OpenCineAppKit (SHELL-02).
  OpenInstaCine/StartupChrome.swift
  OpenInstaCine/PictureEVMeter.swift
  OpenInstaCine/Assets.xcassets
  OpenInstaCine/Resources
  OpenInstaCineWatch/Assets.xcassets
  TestFlight
  Config/Version.xcconfig
  # Package graph: the Insta360 products of OpenCine here, OpenCineDJI/OpenCineMulticam upstream.
  project.yml
  Package.resolved
  ci_scripts
  # Upstream's Frame.io client moved into OpenCine's OpenCineFrameIO (OPTIONAL-01); this
  # copy stays until OpenInstaCine adopts that product.
  OpenInstaCine/Frameio
)

# Upstream DJI app code (BLE, datalink, Multi View on OpenCineMulticam, the OpenCineDJI control
# port, the Wi-Fi and Hotspot setup sheets). Never synced: it builds on OpenCineDJI APIs this app
# does not link, and the frozen copies were deleted here (SHELL-04). Upstream files that only test
# or serve the Osmo DUML session and that we deleted are also skipped by the deleted-here rule.
DJI_ONLY=(
  OpenInstaCine/BleLink.swift
  OpenInstaCine/DatalinkDriver.swift
  'OpenInstaCine/Multiview*'
  OpenInstaCine/StationNetworkSetupView.swift
  OpenInstaCine/AddSetupView.swift
  OpenInstaCine/WiFiNameAccess.swift
  OpenInstaCineTests/NanoFrameQueueTests.swift
  'OpenInstaCine/CameraSession+DJI*'
  'OpenInstaCineTests/DJI*'
  'OpenInstaCineTests/Multiview*'
  'OpenInstaCineUITests/MultiviewUIFlowTests.swift'
  'OpenInstaCineUITests/PhysicalStationSetupTests.swift'
  # Not DJI: tests upstream's OpenCineFrameIO credentials (see Frameio above).
  OpenInstaCineTests/FrameioCredentialsTests.swift
)

# Upstream's cameras page, pair wizard and saved-camera store, replaced by OpenCine's shared app
# shell (OpenCineAppKit CamerasScreen / PairScreen / CamerasModel / SavedCamerasStore, SHELL-02),
# and the helpers only they used. Never synced back.
SHARED_SHELL=(
  OpenInstaCine/LivePortraitSystemBar.swift
  OpenInstaCine/SavedCamerasView.swift
  OpenInstaCine/OsmoCameraPageAdapter.swift
  OpenInstaCine/ConnectionSetupView.swift
  OpenInstaCine/SavedCameraStore.swift
  OpenInstaCine/CameraWifiKeychain.swift
  OpenInstaCineTests/CameraPagePresentationTests.swift
)

TOOLS=(stamp-source-revision.sh pull-control-log.sh analyze-live-log.py)
# Release tooling copied once and retargeted (openinstacine-* Sentry projects, OpenInstaCine and
# :monitor paths, this app's sibling packages). OpenInstaCine owns these copies; a sync never
# writes them. Port upstream fixes by hand.
RELEASE_OWNED=(
  'tools/sentry-*' tools/build-identity.py tools/build-identity-test.py tools/ios-package-resolved-check.py
  'scripts/ios-release-notes*' 'scripts/android-release-notes*' 'scripts/tester-notes-*'
  'scripts/ios-package-resolved-*' scripts/ci-install-swift-android.sh
  .github/workflows/ci.yml .github/workflows/android-play.yml
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

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# build_tree <commit> <out>: upstream at <commit>, laid out exactly as it lands in this repo.
build_tree() {
  local raw="$T/raw-$1" out="$2" d
  mkdir -p "$raw" "$out/tools" "$out/scripts"
  git -C "$SRC" archive "$1" ios tools | tar -x -C "$raw"
  for d in "${TOOLS[@]}"; do cp "$raw/tools/$d" "$out/tools/"; done
  rsync -a --exclude '*.xcodeproj' --exclude xcuserdata --exclude '*.local.xcconfig' \
    "$raw/ios/" "$out/ios/"
  rename_tree "$out/ios"
  for d in "${LUNA_OWNED[@]}"; do rm -rf "${out:?}/ios/$d"; done
  for d in "${DJI_ONLY[@]}"; do rm -rf "${out:?}"/ios/$d; done  # unquoted: entries may glob
  for d in "${SHARED_SHELL[@]}"; do rm -rf "${out:?}/ios/$d"; done
  cp "$ROOT/scripts/apply-openpocketcine-overlays.py" "$out/scripts/"
  /usr/bin/python3 "$out/scripts/apply-openpocketcine-overlays.py"
  rm -rf "$out/scripts"
}

echo "Syncing $(git -C "$SRC" rev-parse --short "$OLD") -> $(git -C "$SRC" rev-parse --short "$NEW"): $(git -C "$SRC" log -1 --format=%s "$NEW")"
build_tree "$OLD" "$T/a"
build_tree "$NEW" "$T/b"

# Deleted here on purpose (moved to a shared package, Osmo-only, DJI-only): drop from both trees.
(cd "$T/a" && find ios tools -type f) | while read -r f; do
  [[ -e "$ROOT/$f" ]] && continue
  [[ -e "$T/b/$f" ]] && ! cmp -s "$T/a/$f" "$T/b/$f" && echo "note: upstream changed $f, deleted here (not applied)"
  rm -f "$T/a/$f" "$T/b/$f"
done

# Dirs named a/ and b/ plus --no-prefix give headers "a/ios/..." / "b/ios/...": they apply at repo root.
(cd "$T" && git diff --no-index --binary --no-renames --no-prefix a b > "$T/sync.patch") || (( $? == 1 ))

# Upstream edits to files we own are never applied. Port them by hand.
UP_OWNED=()
for f in "${LUNA_OWNED[@]}"; do UP_OWNED+=("ios/$(echo "$f" | sed 's/OpenInstaCine/OpenPocketCine/g')"); done
if [[ -n "$(git -C "$SRC" diff --name-only "$OLD" "$NEW" -- "${UP_OWNED[@]}")" ]]; then
  echo "warning: upstream changed Luna-owned files (not applied, port by hand):"
  git -C "$SRC" diff --stat "$OLD" "$NEW" -- "${UP_OWNED[@]}"
fi

if [[ -n "$(git -C "$SRC" diff --name-only "$OLD" "$NEW" -- "${RELEASE_OWNED[@]}")" ]]; then
  echo "warning: upstream changed release tooling OpenInstaCine owns (not applied, port by hand):"
  git -C "$SRC" diff --stat "$OLD" "$NEW" -- "${RELEASE_OWNED[@]}"
fi

if [[ ! -s "$T/sync.patch" ]]; then
  echo "No upstream changes to apply."
  $DRY || echo "$NEW" > "$COMMIT_FILE"
  exit 0
fi
git -C "$ROOT" apply --stat "$T/sync.patch"

# --3way needs the old blobs. Real runs store them in our object DB (conflict stages point at
# them); dry runs keep them in the temp dir.
OBJDIR="$(git -C "$ROOT" rev-parse --path-format=absolute --git-path objects)"
if $DRY; then OBJDIR="$T/objects"; mkdir -p "$OBJDIR"; export GIT_ALTERNATE_OBJECT_DIRECTORIES="$OBJDIR"; fi
(cd "$T/a" && find . -type f | cut -c3- | GIT_OBJECT_DIRECTORY="$OBJDIR" \
  git --git-dir="$(git -C "$ROOT" rev-parse --absolute-git-dir)" hash-object -w --no-filters --stdin-paths > /dev/null)

if $DRY; then
  KEEP="${TMPDIR:-/tmp}"; KEEP="${KEEP%/}/openpocketcine-sync.patch"
  cp "$T/sync.patch" "$KEEP" && echo "Full patch: $KEEP"
  git -C "$ROOT" apply --3way --check "$T/sync.patch" \
    && echo "Dry run: patch applies cleanly. Nothing written." \
    || { echo "Dry run: patch does NOT apply cleanly (see above). Nothing written." >&2; exit 1; }
  exit 0
fi

if ! git -C "$ROOT" apply --3way "$T/sync.patch"; then
  CONFLICTS="$(git -C "$ROOT" diff --name-only --diff-filter=U)"
  [[ -n "$CONFLICTS" ]] || { echo "error: git apply aborted (errors above, e.g. a locally edited file upstream deletes or a dirty file); nothing applied." >&2; exit 1; }
  echo "CONFLICTS (resolve, then: echo $NEW > docs/implementation/openpocketcine-sync-commit.txt):" >&2
  echo "$CONFLICTS" | sed 's/^/    /' >&2
fi
[[ -z "${CONFLICTS:-}" ]] || exit 1
echo "$NEW" > "$COMMIT_FILE"
echo "Done. Next: git diff, (cd ios && xcodegen generate), build, and re-check Luna seams."
