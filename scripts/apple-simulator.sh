#!/usr/bin/env bash
# This helper only addresses a UUID validated against CoreSimulator's inventory.
# It never enumerates, installs to, launches on, or controls a physical phone.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$repo_root"
if [[ $# -lt 1 || $# -gt 2 ]]; then
    printf 'Usage: %s SIMULATOR_UUID [private-recording.hevc]\n' "$0" >&2
    exit 2
fi
simulator_id="$1"
xcrun simctl list devices available --json | python3 -c '
import json, sys
devices = [d for values in json.load(sys.stdin)["devices"].values() for d in values]
if not any(d["udid"] == sys.argv[1] and d["isAvailable"] for d in devices):
    sys.exit("The supplied UUID is not an available simulator. Use xcrun simctl list devices available.")
' "$simulator_id"
replay_index=""
if [[ $# -eq 2 ]]; then
    replay_index="$(python3 scripts/prepare-preview-replay.py "$2")"
fi
xcodegen generate --spec Apps/Apple/project.yml
xcodebuild -project Apps/Apple/OpenInstaCine.xcodeproj -scheme OpenInstaCine \
    -destination "platform=iOS Simulator,id=$simulator_id" -configuration Debug \
    -derivedDataPath .local/AppleDerivedData CODE_SIGNING_ALLOWED=NO build
# bootstatus boots the requested simulator if needed and waits for readiness.
xcrun simctl bootstatus "$simulator_id" -b
xcrun simctl install "$simulator_id" .local/AppleDerivedData/Build/Products/Debug-iphonesimulator/OpenInstaCine.app
xcrun simctl terminate "$simulator_id" com.opencapture.openinstacine >/dev/null 2>&1 || true
if [[ -n "$replay_index" ]]; then
    SIMCTL_CHILD_OPENINSTA_REVIEW_INDEX="$replay_index" \
        xcrun simctl launch "$simulator_id" com.opencapture.openinstacine
else
    xcrun simctl launch "$simulator_id" com.opencapture.openinstacine
fi
open -a Simulator --args -CurrentDeviceUDID "$simulator_id"
printf '\nSimulator ready. Use Device > Rotate Left for landscape.\n'
if [[ -n "$replay_index" ]]; then
    printf 'Select Local recording · preview test. The monitor is labeled LOCAL REPLAY.\n'
fi
