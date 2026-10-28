#!/usr/bin/env bash
# Regression tests for scripts/ci-wait-for-artifact.sh, against a stand-in gh that serves a
# scripted run: when the artifact appears and what the producer job's status is at each poll.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

mkdir "$temp_dir/bin" "$temp_dir/payload"
echo "build" > "$temp_dir/payload/products.tar"
(cd "$temp_dir/payload" && zip -q "$temp_dir/artifact.zip" products.tar)

cat > "$temp_dir/bin/gh" <<'EOF'
#!/usr/bin/env bash
# ARTIFACT_AT: the artifact list call (1-based) from which the artifact exists; 0 means never.
# STATUSES: the producer's status at each jobs call, comma-separated; the last one repeats.
# JOB_NAME: the producer's name in the run. EXPIRED_TOO: also list an older, expired artifact.
[ "$1" = api ] || { echo "unexpected gh call: $*" >&2; exit 2; }
echo "$2" >> "$CALLS"
case "$2" in
  repos/o/r/actions/runs/7/artifacts\?name=ios-build*)
    count="$(grep -c '/artifacts?' "$CALLS")"
    listed=""
    if [ "${EXPIRED_TOO:-}" = 1 ]; then
      listed='{"id": 41, "expired": true, "created_at": "2026-10-28T20:30:00Z"}'
    fi
    if [ "$ARTIFACT_AT" != 0 ] && [ "$count" -ge "$ARTIFACT_AT" ]; then
      listed="${listed:+$listed, }{\"id\": 42, \"expired\": false, \"created_at\": \"2026-10-28T20:20:00Z\"}"
    fi
    echo "{\"artifacts\": [$listed]}"
    ;;
  repos/o/r/actions/runs/7/jobs\?filter=latest*)
    count="$(grep -c '/jobs?' "$CALLS")"
    status="$(echo "$STATUSES" | tr ',' '\n' | sed -n "${count}p")"
    [ -n "$status" ] || status="$(echo "$STATUSES" | tr ',' '\n' | tail -1)"
    echo "{\"jobs\": [{\"name\": \"Full suite / Meta checks\", \"status\": \"completed\"},
      {\"name\": \"${JOB_NAME}\", \"status\": \"${status}\"}]}"
    ;;
  repos/o/r/actions/artifacts/42/zip) cat "$ARTIFACT_ZIP" ;;
  *) echo "unexpected gh api path: $2" >&2; exit 2 ;;
esac
EOF
chmod +x "$temp_dir/bin/gh"
export PATH="$temp_dir/bin:$PATH" CALLS="$temp_dir/calls" ARTIFACT_ZIP="$temp_dir/artifact.zip" \
  GITHUB_REPOSITORY=o/r GITHUB_RUN_ID=7 CI_WAIT_INTERVAL=0

# expect <pass|fail> <artifact list calls> <artifact at> <statuses> [job name]
expect() {
  local verdict=0 out="$temp_dir/out"
  rm -rf "$out" "$CALLS"
  touch "$CALLS"
  ARTIFACT_AT="$3" STATUSES="$4" JOB_NAME="${5:-Full suite / Native Swift/iOS}" \
    "$script_dir/ci-wait-for-artifact.sh" ios-build "Native Swift/iOS" "$out" \
    > "$temp_dir/log" 2>&1 || verdict=1
  local polls
  polls="$(grep -c '/artifacts?' "$CALLS" || true)"
  if [ "$verdict" != "$([ "$1" = pass ] && echo 0 || echo 1)" ] || [ "$polls" != "$2" ]; then
    printf 'Artifact at %s, statuses %s: expected %s after %s list calls, got exit %s after %s\n' \
      "$3" "$4" "$1" "$2" "$verdict" "$polls" >&2
    cat "$temp_dir/log" >&2
    exit 1
  fi
  if [ "$1" = pass ] && [ "$(cat "$out/products.tar")" != build ]; then
    echo "Artifact at $3: the download was not unpacked into the output directory" >&2
    exit 1
  fi
}

# Already uploaded: no wait.
expect pass 1 1 in_progress
# Uploaded while the producer still runs: keeps polling until it appears.
expect pass 3 3 queued,in_progress,in_progress
# The producer finished without it: fails at once instead of waiting for the timeout.
expect fail 3 0 in_progress,completed
# The producer finished right after uploading: the second look finds it.
expect pass 2 2 completed
# A job not in this run fails rather than waiting.
expect fail 2 0 in_progress "Full suite / Android"
# A run started directly (not through nightly.yml) names the job without a caller prefix.
expect pass 2 2 in_progress "Native Swift/iOS"
# An expired artifact of the same name is never picked.
EXPIRED_TOO=1 expect pass 2 2 in_progress
# The deadline still bounds a producer that never finishes.
CI_WAIT_TIMEOUT=0 expect fail 1 0 in_progress

echo "ci-wait-for-artifact.sh tests passed."
