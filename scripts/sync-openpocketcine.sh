#!/usr/bin/env bash
# Re-sync OpenInstaCine's iOS shell and shared engine from a local OpenPocketCine checkout.
#
#   scripts/sync-openpocketcine.sh [--dry-run]     # uses ../OpenPocketCine HEAD
#   OPENPOCKETCINE_PATH=/path scripts/sync-openpocketcine.sh
#   OLD_COMMIT=<sha> scripts/sync-openpocketcine.sh --dry-run   # pretend the last sync was <sha>
#   NEW_COMMIT=<sha> scripts/sync-openpocketcine.sh             # sync to <sha> instead of HEAD
#
# Three-way update. The "renamed upstream" tree (engine + tests + tools copied verbatim, ios/
# renamed to OpenInstaCine, Luna-owned and Osmo-only files dropped, brand overlays applied by
# scripts/apply-openpocketcine-overlays.py) is built at the last synced commit and at upstream
# HEAD. The old->new diff is applied with `git apply --3way`, so our edits to upstream-derived
# files survive and real overlaps come out as conflicts. Engine/test dirs with no local changes
# are rsynced instead (fast path). Commit or stash the paths being synced first: --3way uses
# the index. After editing the overlay script, run it once by hand; it is baked into both trees.
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

# Files OpenInstaCine owns inside ios/ (Luna seams and brand assets). Never touched by a sync.
# Adapters/ and our own Sources/MonitorContracts are outside the upstream tree entirely.
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
  OpenInstaCine/PictureEVMeter.swift
  OpenInstaCine/Assets.xcassets
  OpenInstaCine/Resources
  OpenInstaCineWatch/Assets.xcassets
  TestFlight
  Config/Version.xcconfig
)

# Upstream files that only test or serve the Osmo DUML session. Never synced.
OSMO_ONLY=(
  OpenInstaCineTests/MediaLiveRecoveryOwnershipTests.swift
  OpenInstaCineTests/MultiviewStageTests.swift
  OpenInstaCineTests/FormatCeilingNoteTests.swift
  OpenInstaCineTests/MediaCacheSchedulingTests.swift
  OpenInstaCineTests/CapturePreviewTrafficTests.swift
  OpenInstaCineTests/MultiviewControlsTests.swift
  OpenInstaCineTests/ShutterAnglePersistenceTests.swift
  OpenInstaCineTests/SessionRecoveryLifecycleTests.swift
  OpenInstaCineTests/ConnectionLifecycleRegressionTests.swift
  OpenInstaCineTests/EVMeterAssistTests.swift
  OpenInstaCineTests/GimbalModeSelectionTests.swift
  OpenInstaCineTests/HandshakeBindTests.swift
  OpenInstaCineTests/CameraDialReconciliationTests.swift
)

# MonitorPresentation, MonitorUI and their tests come from the OpenCineUI package (ios/project.yml),
# and Android monitor-ui from its included build. A sync never copies them, even from an upstream
# commit that still has its own copies.
ENGINE=(OpenPocketViewCore CJNI OpenPocketCineAndroidFacade)
SHARED_UI_TESTS=(Tests/MonitorPresentationTests)
TOOLS=(stamp-source-revision.sh build-identity.py pull-control-log.sh analyze-live-log.py)
# Release tooling copied once and retargeted (openinstacine-* Sentry projects, OpenInstaCine and
# :monitor paths). OpenInstaCine owns these copies; a sync never writes them. Port upstream fixes by hand.
RELEASE_OWNED=(
  'tools/sentry-*' tools/build-identity-test.py tools/ios-package-resolved-check.py
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
  mkdir -p "$raw" "$out/Sources" "$out/tools" "$out/scripts"
  git -C "$SRC" archive "$1" Sources Tests ios tools | tar -x -C "$raw"
  for d in "${ENGINE[@]}"; do cp -R "$raw/Sources/$d" "$out/Sources/"; done
  cp -R "$raw/Tests" "$out/Tests"
  for d in "${SHARED_UI_TESTS[@]}"; do rm -rf "${out:?}/$d"; done
  for d in "${TOOLS[@]}"; do cp "$raw/tools/$d" "$out/tools/"; done
  rsync -a --exclude '*.xcodeproj' --exclude xcuserdata --exclude '*.local.xcconfig' \
    "$raw/ios/" "$out/ios/"
  rename_tree "$out/ios"
  for d in "${LUNA_OWNED[@]}" "${OSMO_ONLY[@]}"; do rm -rf "${out:?}/ios/$d"; done
  cp "$ROOT/scripts/apply-openpocketcine-overlays.py" "$out/scripts/"
  /usr/bin/python3 "$out/scripts/apply-openpocketcine-overlays.py"
  rm -rf "$out/scripts"
}

echo "Syncing $(git -C "$SRC" rev-parse --short "$OLD") -> $(git -C "$SRC" rev-parse --short "$NEW"): $(git -C "$SRC" log -1 --format=%s "$NEW")"
build_tree "$OLD" "$T/a"
build_tree "$NEW" "$T/b"

# Dirs named a/ and b/ plus --no-prefix give headers "a/ios/..." / "b/ios/...": they apply at repo root.
(cd "$T" && git diff --no-index --binary --no-renames --no-prefix a b > "$T/sync.patch") || (( $? == 1 ))

# Engine + test dirs: rsync when untouched locally, otherwise three-way like the shell.
RSYNC=() EXCLUDE=(--exclude=__none__)
for d in "${ENGINE[@]/#/Sources/}" $(cd "$T/b" && ls -d Tests/*); do
  if diff -rq -x .DS_Store "$ROOT/$d" "$T/a/$d" > /dev/null 2>&1; then
    RSYNC+=("$d") EXCLUDE+=("--exclude=$d/*")
  else
    echo "warning: $d has local changes vs upstream $(git -C "$SRC" rev-parse --short "$OLD"); three-way instead of rsync:"
    diff -rq -x .DS_Store "$ROOT/$d" "$T/a/$d" 2>&1 | sed "s#$ROOT/##; s#$T/a/#upstream:#; s#^#    #" || true
  fi
done

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
echo "rsync (no local changes): ${RSYNC[*]:-none}"

# --3way needs the old blobs. Real runs store them in our object DB (conflict stages point at
# them); dry runs keep them in the temp dir.
OBJDIR="$(git -C "$ROOT" rev-parse --path-format=absolute --git-path objects)"
if $DRY; then OBJDIR="$T/objects"; mkdir -p "$OBJDIR"; export GIT_ALTERNATE_OBJECT_DIRECTORIES="$OBJDIR"; fi
(cd "$T/a" && find . -type f | cut -c3- | GIT_OBJECT_DIRECTORY="$OBJDIR" \
  git --git-dir="$(git -C "$ROOT" rev-parse --absolute-git-dir)" hash-object -w --no-filters --stdin-paths > /dev/null)

if $DRY; then
  KEEP="${TMPDIR:-/tmp}"; KEEP="${KEEP%/}/openpocketcine-sync.patch"
  cp "$T/sync.patch" "$KEEP" && echo "Full patch: $KEEP"
  git -C "$ROOT" apply --3way --check "${EXCLUDE[@]}" "$T/sync.patch" \
    && echo "Dry run: patch applies cleanly. Nothing written." \
    || { echo "Dry run: patch does NOT apply cleanly (see above). Nothing written." >&2; exit 1; }
  exit 0
fi

if ! git -C "$ROOT" apply --3way "${EXCLUDE[@]}" "$T/sync.patch"; then
  CONFLICTS="$(git -C "$ROOT" diff --name-only --diff-filter=U)"
  [[ -n "$CONFLICTS" ]] || { echo "error: git apply aborted (errors above, e.g. a locally edited file upstream deletes or a dirty file); nothing applied." >&2; exit 1; }
  echo "CONFLICTS (resolve, then: echo $NEW > docs/implementation/openpocketcine-sync-commit.txt):" >&2
  echo "$CONFLICTS" | sed 's/^/    /' >&2
fi
for d in ${RSYNC[@]+"${RSYNC[@]}"}; do
  mkdir -p "$ROOT/$d"
  rsync -a --delete --exclude .DS_Store "$T/b/$d/" "$ROOT/$d/"
done
[[ -z "${CONFLICTS:-}" ]] || exit 1
echo "$NEW" > "$COMMIT_FILE"
echo "Done. Next: git diff, (cd ios && xcodegen generate), build, and re-check Luna seams."
