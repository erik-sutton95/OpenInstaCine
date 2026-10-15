# Sentry release setup

Opt-in reliability reporting, as in OpenPocketCine: off by default, offered on
first launch and in Operator Setup, and only when the build carries a valid DSN.
This page is the release and CI contract.

Organization **opencapture** (EU, `*.ingest.de.sentry.io`). Projects:

| Platform | Project | Release name |
| --- | --- | --- |
| iOS | `openinstacine-ios` | `com.opencapture.openinstacine@<version>+<build>`, `dist` = build |
| Android | `openinstacine-android` | same shape |

Never point OpenInstaCine at the `openpocketcine-*` projects or DSNs. DSNs are
never committed.

The SDK adapters are OpenCine's optional reporting adapter (`OpenCineSentryApple`, its own
package at `Packages/OpenCineSentryApple`, and Android `:appkit-sentry`); this app links them and
keeps only its host values (`AppDiagnostics`). OpenCine pins Sentry Cocoa **9.24.0** and sentry-android **8.58.0**.
The release tooling below is OpenCine's `scripts/sentry/`, checked out next to this repository;
this app passes its project slug (`--project`) and, on Android, its modules (`--android-module
app --android-module monitor`).

## Where the DSN comes from

| Build | iOS | Android |
| --- | --- | --- |
| Xcode Cloud | `SENTRY_DSN_IOS` -> `ci_post_clone.sh` -> `ios/OpenInstaCine/Reliability.local.xcconfig` | |
| Play workflow | | `SENTRY_DSN_ANDROID` secret -> `:monitor` `BuildConfig.SENTRY_DSN_ANDROID` |
| Local | `just ios-local-dsn` writes the ignored xcconfig from `.local/reliability.properties` | `.local/reliability.properties` (`SENTRY_DSN_ANDROID=…`), or the env var |

`.local/reliability.properties` holds both keys, `SENTRY_DSN_IOS=` and
`SENTRY_DSN_ANDROID=`. `.local/` and `*.local.xcconfig` are gitignored.

Gates:

- Every successful Xcode Cloud archive runs `scripts/sentry/sentry-verify-ios-dsn.py --require`
  on the packaged `Info.plist`. No DSN, no archive.
- The Play workflow runs `scripts/sentry/sentry-require-android-dsn.sh` before bundling
  when `SENTRY_UPLOAD_ENABLED=true`.

## Symbol upload

Off unless `SENTRY_UPLOAD_ENABLED` is exactly `true`. Then
`scripts/sentry/sentry-install.sh` installs the pinned `sentry-cli` (version in
`scripts/sentry/sentry-cli-version`, SHA-256 in `scripts/sentry/sentry-cli-checksums.txt`) and
`scripts/sentry/sentry-upload.py --platform ios|android` checks and uploads:

- iOS: the archive's dSYMs.
- Android: native `.so` symbols from `:monitor` (Swift core, CMake), merged app
  libraries, and the R8 mapping. Play CI generates `SENTRY_PROGUARD_UUID` before
  bundling; Gradle embeds the same value as `io.sentry.proguard-uuid`. The
  mapping and UUID are retained together in the `r8-mapping` artifact. A
  `mapping.txt` without `SENTRY_PROGUARD_UUID` still fails the upload.

Local release recipes generate a UUID unless one is supplied. For a direct
Gradle release or a later manual mapping upload, export `SENTRY_PROGUARD_UUID`
before building, record it with that build's mapping, and reuse it for upload.
A direct Gradle build without the UUID has no Sentry mapping binding and must
not be used for a reporting-enabled release. Reporting consent and upload
opt-in are unchanged.

`SENTRY_PROJECT` defaults to `openinstacine-ios` / `openinstacine-android`; set it
explicitly in each CI environment anyway. Needs `SENTRY_AUTH_TOKEN` (org token
with release and debug-file write). No source bundles are uploaded.

## Server privacy (mandatory)

Both projects need the recursive relay PII rule, so Sentry cannot keep an
inferred user or location:

```json
{
  "rules": { "removeUser": { "type": "anything", "redaction": { "method": "remove" } } },
  "applications": { "user.**": ["removeUser"], "user.geo.**": ["removeUser"] }
}
```

This was requested from the owner; confirm it on both projects before the first
external build.

## Local checks

```bash
just sentry-test   # offline: install, upload, DSN and build-identity tests
```
