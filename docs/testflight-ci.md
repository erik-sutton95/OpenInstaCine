# TestFlight (Xcode Cloud)

Xcode Cloud is the TestFlight path, as in OpenPocketCine: Apple-managed signing, a
build counter, and a native upload after archive. There is no GitHub Actions
TestFlight workflow. One-time account setup is the [owner checklist](RELEASE.md#owner-checklist).

## What the cloud workflow does

| Step | Where it lives |
| --- | --- |
| Generate `ios/OpenInstaCine.xcodeproj` (gitignored) | [`ios/ci_scripts/ci_post_clone.sh`](../ios/ci_scripts/ci_post_clone.sh) (XcodeGen 2.46.0) |
| Copy `ios/Package.resolved` into the workspace | same script (Cloud builds with `-disableAutomaticPackageResolution`) |
| Sentry DSN | `SENTRY_DSN_IOS` -> [`tools/sentry-dsn-xcconfig.py`](../tools/sentry-dsn-xcconfig.py) -> ignored `ios/OpenInstaCine/Reliability.local.xcconfig` |
| Check notes, verify the packaged DSN, upload dSYMs | [`ios/ci_scripts/ci_post_xcodebuild.sh`](../ios/ci_scripts/ci_post_xcodebuild.sh) |
| Marketing version | [`ios/Config/Version.xcconfig`](../ios/Config/Version.xcconfig) `MARKETING_VERSION` |
| Build number | Xcode Cloud counter |
| Tester notes | [`ios/TestFlight/WhatToTest.en-US.txt`](../ios/TestFlight/WhatToTest.en-US.txt) |

Every successful archive runs `tools/sentry-verify-ios-dsn.py --require`: an
archive without a real `https` DSN fails, even with symbol uploads off. See
[`sentry-deployment.md`](sentry-deployment.md).

The `ci_scripts/` hooks and the helpers they call (`tools/sentry-*`,
`scripts/ios-release-notes*.sh`) are maintained in this app and target its
`openinstacine-*` Sentry projects. `ios/TestFlight/` and
`ios/Config/Version.xcconfig` are OpenInstaCine owned too.

Local dry run (a throwaway clone, so nothing local is overwritten):

```bash
git clone -q . /tmp/oic-cloud && cd /tmp/oic-cloud
CI_PRIMARY_REPOSITORY_PATH=$PWD SENTRY_DSN_IOS=https://… sh ios/ci_scripts/ci_post_clone.sh
CI_PRIMARY_REPOSITORY_PATH=$PWD CI_APP_STORE_SIGNED_APP_PATH=$PWD sh ios/ci_scripts/ci_post_xcodebuild.sh
```

## Workflow settings

- Scheme **OpenInstaCine**, action
  Archive, platform iOS, deployment **TestFlight and App Store**.
- Start condition: branch `main`, Files and Folders limited to `Sources/`,
  `Tests/`, `Adapters/`, `ios/`, `Resources/`, `Package.swift`, `scripts/`,
  `tools/`, `justfile`, so docs-only merges do not burn hours.
- Environment: latest released Xcode and macOS. Variables in the owner checklist.
  Leave `FRAMEIO_*` unset (Frame.io login disabled) unless OpenInstaCine gets its
  own Adobe credential. Never reuse OpenPocketCine's.
- Post-actions: TestFlight Internal first; External after TestFlight App Review.

Both bundle ids (`com.opencapture.openinstacine`, `com.opencapture.openinstacine.watch`)
must be registered on team `4V4EGQ6LZA` before the first archive: Xcode Cloud
cannot register the Watch id during export. The app id needs **Hotspot
Configuration** and **Access WiFi Information** (`OpenInstaCine.entitlements`).
A local `just ios-run` with automatic signing registers both.

## Tester notes

`scripts/ios-release-notes-check.sh` enforces the format: either `New features`
with 1 to 4 bullets, or `New and changed` / `Fixes` / `What to test`; no free
text, no commit titles, no implementation jargon, 2000 characters, 200 per
bullet (caps in `scripts/tester-notes-limits.sh`). Each pull request that changes
the iOS app replaces the file with that build's window (CI enforces it):

```bash
just tester-notes-window   # recent feat/fix commits to pick from
just testflight-notes      # check and print
```

## Versions

`MARKETING_VERSION` equals Android `openpocketcine.versionName` (currently
`0.1.0`). Testers see `0.1.0 (build)`. Bump only for a new train
([`RELEASE.md`](RELEASE.md)). `just ios-version`.

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| Cloud cannot open `OpenInstaCine.xcodeproj` | `ci_post_clone.sh` did not run or XcodeGen failed |
| `a resolved file is required` | `ios/Package.resolved` stale: `just ios-resolve`, commit |
| Archive fails in `sentry-verify-ios-dsn.py` | `SENTRY_DSN_IOS` missing or not `https` on the workflow |
| Export cannot register the Watch bundle id | Register `com.opencapture.openinstacine.watch` on the team |
| Provisioning profile missing an entitlement | Enable Hotspot Configuration / Access WiFi Information on the app id |
| "Build number already used" | Raise the workflow's next build number |
