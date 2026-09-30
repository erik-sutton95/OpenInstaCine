# Play closed testing (GitHub Actions)

The Android analog of Xcode Cloud, ported from OpenPocketCine:
[`.github/workflows/android-play.yml`](../.github/workflows/android-play.yml)
builds a signed App Bundle with a monotonic `versionCode` and uploads it to Play
closed testing (`alpha`). One-time setup is the [owner checklist](RELEASE.md#owner-checklist).

Status: the Android app builds (`:app:assembleDebug`, signed `assembleRelease`
and `bundleRelease`) and its unit tests pass, but it is **not yet verified on a
physical phone against a real Luna**. Do that before the first Play or sideload
release.

## What the workflow does

| Step | Where it lives |
| --- | --- |
| Swift core + JNI `.so` | [`scripts/ci-install-swift-android.sh`](../scripts/ci-install-swift-android.sh) + `:monitor:stageSwiftCore` |
| Package guard | fails unless `app/build.gradle.kts` still says `com.opencapture.openinstacine` |
| Signed AAB | `./gradlew bundleRelease -PversionCode=…` with `ANDROID_KEYSTORE_*` |
| `versionName` | `openpocketcine.versionName` in [`Apps/Android/gradle.properties`](../Apps/Android/gradle.properties) (equal to iOS) |
| `versionCode` | `ANDROID_VERSION_CODE_BASE` + `github.run_number` |
| Sentry DSN / symbols | `SENTRY_DSN_ANDROID` -> `:monitor` `BuildConfig`; `tools/sentry-upload.py --platform android` when `SENTRY_UPLOAD_ENABLED=true` |
| Tester notes | [`Apps/Android/Play/WhatToTest.en-US.txt`](../Apps/Android/Play/WhatToTest.en-US.txt), Play "what's new" (500 characters) [`Apps/Android/Play/whatsnew/whatsnew-en-US`](../Apps/Android/Play/whatsnew/whatsnew-en-US) |
| Upload | `r0adkll/upload-google-play`, package `com.opencapture.openinstacine`, track `alpha` |

It runs on **Run workflow** (or `just android-play-dispatch`) and on pushes to
`main` that touch Android paths, only in `erik-sutton95/OpenInstaCine`, never on
`pull_request`, and auto-upload only when the repository variable
`ANDROID_PLAY_UPLOAD` is exactly `true`. Missing `play-closed` secrets fail the
job. A dispatch without `PLAY_SERVICE_ACCOUNT_JSON` still signs the AAB and
attaches it as an artifact: that is the file for the first manual Console upload
(the Play API cannot create a package).

## Signing and ids

`app/build.gradle.kts` signs release only when `ANDROID_KEYSTORE_FILE` is set
(with `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`).
Debug builds are `com.opencapture.openinstacine.debug`, labelled
"OpenInstaCine Dev", so they install beside a Play or sideload build.
Keystores live only in `.local/` (gitignored, like `*.jks` / `*.keystore`).

```bash
just android-bundle        # local signed AAB from .local/play-signing.env
just android-play-notes    # check and print the Play notes
just android-version
```

## Store listing

Short description (80 characters):

```text
Open-source field monitor for the Insta360 Luna Ultra. Live view and control.
```

Full description:

```text
OpenInstaCine is a free, open-source field monitor for the Insta360 Luna Ultra.
It is not made or endorsed by Insta360.

Pair over Bluetooth, join the camera's Wi-Fi, and watch a live view with
waveform, histogram and false colour. Record, zoom and move the gimbal from
your phone. Needs camera firmware 1.1.15, a 64-bit phone and Android 10 or
newer. There is no account in the app.

Source: https://github.com/erik-sutton95/OpenInstaCine
Privacy: https://opencapture.org/openinstacine/privacy
```

Privacy policy URL: <https://opencapture.org/openinstacine/privacy>.
Support URL: <https://opencapture.org/openinstacine/support>.
Screenshots must be Android captures.

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| Workflow skipped on `main` | `ANDROID_PLAY_UPLOAD` is not exactly `true`, or no Android path changed |
| Missing `play-closed` secrets | `just android-play-sync-secrets` |
| Package not found | The first AAB has not been uploaded in Play Console |
| Insufficient permissions | Service account not invited on Play Console Users and permissions |
| versionCode collision | Raise `ANDROID_VERSION_CODE_BASE` above the Play high-water mark |
