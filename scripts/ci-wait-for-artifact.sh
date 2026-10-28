#!/usr/bin/env bash
# Wait for another job of this workflow run to upload an artifact, then unpack it.
#
#   ci-wait-for-artifact.sh NAME PRODUCER_JOB OUT_DIR
#
# The nightly iPad oracle job runs beside the native job and needs that job's build-for-testing
# output: it boots its own simulator meanwhile, then calls this script. NAME is the artifact,
# PRODUCER_JOB the uploading job's name as ci.yml writes it (a called workflow prefixes
# "<caller job> / "). Fails when the producer finished without uploading NAME, or after
# CI_WAIT_TIMEOUT seconds (default 3000). Needs GH_TOKEN with actions: read, GITHUB_REPOSITORY
# and GITHUB_RUN_ID; CI_WAIT_INTERVAL sets the poll interval (default 20 seconds).
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "usage: $0 NAME PRODUCER_JOB OUT_DIR" >&2
  exit 2
fi
name="$1"
producer="$2"
out_dir="$3"
run="repos/${GITHUB_REPOSITORY:?}/actions/runs/${GITHUB_RUN_ID:?}"
interval="${CI_WAIT_INTERVAL:-20}"
deadline=$((SECONDS + ${CI_WAIT_TIMEOUT:-3000}))

# Prints the id of the newest unexpired artifact called NAME in this run, or nothing.
artifact_id() {
  gh api "${run}/artifacts?name=${name}&per_page=100" | python3 -c '
import json, sys
artifacts = [a for a in json.load(sys.stdin).get("artifacts", []) if not a.get("expired")]
artifacts.sort(key=lambda a: a.get("created_at", ""))
print(artifacts[-1]["id"] if artifacts else "")
'
}

# Prints the producer job's status in the run's latest attempt (queued, in_progress, completed),
# or nothing when the run has no such job.
producer_status() {
  gh api "${run}/jobs?filter=latest&per_page=100" | PRODUCER="$producer" python3 -c '
import json, os, sys
producer = os.environ["PRODUCER"]
for job in json.load(sys.stdin).get("jobs", []):
    if job["name"] == producer or job["name"].endswith(" / " + producer):
        print(job["status"])
        break
'
}

while :; do
  id="$(artifact_id)"
  [ -z "$id" ] || break
  status="$(producer_status)"
  if [ "$status" = completed ] || [ -z "$status" ]; then
    # The producer may have uploaded just before it finished: look once more.
    id="$(artifact_id)"
    [ -z "$id" ] || break
    echo "::error::${producer} ${status:-is not in this run} without uploading ${name}" >&2
    exit 1
  fi
  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "::error::${name} did not appear within ${CI_WAIT_TIMEOUT:-3000} seconds" >&2
    exit 1
  fi
  sleep "$interval"
done

echo "Downloading ${name} (artifact ${id})"
mkdir -p "$out_dir"
archive="$(mktemp)"
trap 'rm -f "$archive"' EXIT
gh api "repos/${GITHUB_REPOSITORY}/actions/artifacts/${id}/zip" > "$archive"
unzip -q -o "$archive" -d "$out_dir"
