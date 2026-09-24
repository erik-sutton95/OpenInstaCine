#!/usr/bin/env bash
# Vendor the current OpenPocketCine shared engine + native shells into this repo.
# OpenInstaCine keeps brand identity, Luna adapters, and protocol research.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${OPENPOCKETCINE_PATH:-$ROOT/../OpenPocketCine}"
PYTHON="${PYTHON:-/usr/bin/python3}"

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

[[ -d "$SRC/.git" ]] || fail "OpenPocketCine not found at $SRC (set OPENPOCKETCINE_PATH)"
[[ -f "$SRC/Package.swift" ]] || fail "OpenPocketCine Package.swift missing at $SRC"

COMMIT="$(git -C "$SRC" rev-parse HEAD)"
SHORT="$(git -C "$SRC" rev-parse --short HEAD)"
SUBJECT="$(git -C "$SRC" log -1 --format='%s')"
DATE="$(git -C "$SRC" log -1 --format='%cI')"

rsync_tree() {
  local from="$1" to="$2"
  shift 2
  mkdir -p "$to"
  rsync -a --delete --exclude '.DS_Store' --exclude 'build/' --exclude '.build/' "$@" "$from"/ "$to"/
}

echo "Syncing OpenPocketCine $SHORT ($COMMIT)"
echo "  $SUBJECT"

# --- Portable Swift packages (byte-identical to PocketCine) ---
rsync_tree "$SRC/Sources/MonitorPresentation" "$ROOT/Sources/MonitorPresentation"
rsync_tree "$SRC/Sources/MonitorUI" "$ROOT/Sources/MonitorUI"
rsync_tree "$SRC/Sources/OpenPocketViewCore" "$ROOT/Sources/OpenPocketViewCore"
rsync_tree "$SRC/Sources/CJNI" "$ROOT/Sources/CJNI"
rsync_tree "$SRC/Sources/OpenPocketCineAndroidFacade" "$ROOT/Sources/OpenPocketCineAndroidFacade"
rsync_tree "$SRC/Tests/MonitorPresentationTests" "$ROOT/Tests/MonitorPresentationTests"
rsync_tree "$SRC/Tests/OpenPocketViewCoreTests" "$ROOT/Tests/OpenPocketViewCoreTests"
rsync_tree "$SRC/Tests/OpenPocketCineAndroidFacadeTests" "$ROOT/Tests/OpenPocketCineAndroidFacadeTests"
mkdir -p "$ROOT/Tests/OpenPocketViewCoreTests"
rsync -a --delete --exclude '.DS_Store' \
  "$SRC/Tests/OpenPocketViewCoreTests/Fixtures"/ "$ROOT/Tests/OpenPocketViewCoreTests/Fixtures"/ 2>/dev/null || true

# --- Apple monitor shell (live screens, decode, media). Brand app stays thin. ---
SHELL="$ROOT/Shared/Apple/MonitorShell"
mkdir -p "$SHELL"
rsync -a --delete \
  --exclude '.DS_Store' \
  --exclude 'Assets.xcassets/' \
  --exclude 'OpenPocketCineApp.swift' \
  --exclude 'CameraSession.swift' \
  --exclude 'OpenPocketCine.entitlements' \
  --exclude 'Info-Frameio.plist' \
  --exclude 'Frameio.xcconfig' \
  --exclude 'Frameio.local.xcconfig.example' \
  --exclude 'Reliability.local.xcconfig' \
  --exclude 'Reliability.local.xcconfig.example' \
  --exclude 'ReliabilityReporting.swift' \
  --exclude 'ReliabilityReportingConfiguration.swift' \
  --exclude 'ReliabilityReportingNetwork.swift' \
  --exclude 'ReliabilityReportingPrivacy.swift' \
  --exclude 'ReliabilityReportingVerification.swift' \
  --exclude 'ProblemReporting.swift' \
  --exclude 'ProblemReportView.swift' \
  --exclude 'ProblemReportImage.swift' \
  --exclude 'FeedIncidentRuntime.swift' \
  --exclude 'FeedSessionSummaryStore.swift' \
  --exclude 'FeedStressAutomation.swift' \
  "$SRC/ios/OpenPocketCine"/ "$SHELL"/

# --- Android shared UI + fat shell copied as the :monitor library ---
rsync_tree "$SRC/Apps/Android/monitor-ui" "$ROOT/Apps/Android/monitor-ui" \
  --exclude 'build/' --exclude '.gradle/'
mkdir -p "$ROOT/Apps/Android/monitor/src"
rsync -a --delete \
  --exclude '.DS_Store' --exclude 'build/' \
  "$SRC/Apps/Android/app/src"/ "$ROOT/Apps/Android/monitor/src"/
if [[ -f "$SRC/Apps/Android/app/proguard-rules.pro" ]]; then
  cp "$SRC/Apps/Android/app/proguard-rules.pro" "$ROOT/Apps/Android/monitor/proguard-rules.pro"
fi
rsync -a "$SRC/Apps/Android/gradle/" "$ROOT/Apps/Android/gradle/"
cp "$SRC/Apps/Android/gradle.properties" "$ROOT/Apps/Android/gradle.properties"
cp "$SRC/Apps/Android/gradlew" "$SRC/Apps/Android/gradlew.bat" "$ROOT/Apps/Android/"
cp "$SRC/Apps/Android/libs.versions.toml" "$ROOT/Apps/Android/gradle/libs.versions.toml" 2>/dev/null || true
if [[ -f "$SRC/Apps/Android/gradle/libs.versions.toml" ]]; then
  cp "$SRC/Apps/Android/gradle/libs.versions.toml" "$ROOT/Apps/Android/gradle/libs.versions.toml"
fi
if [[ -f "$SRC/scripts/android-stage-swift-core.sh" ]]; then
  cp "$SRC/scripts/android-stage-swift-core.sh" "$ROOT/scripts/android-stage-swift-core.sh"
fi

"$PYTHON" "$ROOT/scripts/apply-openpocketcine-overlays.py"

mkdir -p "$ROOT/docs/implementation"
cat > "$ROOT/docs/implementation/openpocketcine-provenance.json" <<EOF
{
  "source_repo": "OpenPocketCine",
  "commit": "$COMMIT",
  "short": "$SHORT",
  "subject": $(printf '%s' "$SUBJECT" | "$PYTHON" -c 'import json,sys; print(json.dumps(sys.stdin.read()))'),
  "date": "$DATE",
  "synced_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "trees": [
    "Sources/MonitorPresentation",
    "Sources/MonitorUI",
    "Sources/OpenPocketViewCore",
    "Sources/CJNI",
    "Sources/OpenPocketCineAndroidFacade",
    "Tests/MonitorPresentationTests",
    "Tests/OpenPocketViewCoreTests",
    "Tests/OpenPocketCineAndroidFacadeTests",
    "Shared/Apple/MonitorShell",
    "Apps/Android/monitor-ui",
    "Apps/Android/monitor/src"
  ]
}
EOF

echo "Wrote docs/implementation/openpocketcine-provenance.json"
echo "Done. Brand, Luna adapters, and protocol research were not overwritten."
