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

## Where the DSN comes from

| Build | iOS | Android |
| --- | --- | --- |
| Xcode Cloud | `SENTRY_DSN_IOS` -> `ci_post_clone.sh` -> `ios/OpenInstaCine/Reliability.local.xcconfig` | |
| Play workflow | | `SENTRY_DSN_ANDROID` secret -> `:monitor` `BuildConfig.SENTRY_DSN_ANDROID` |
| Local | `just ios-local-dsn` writes the ignored xcconfig from `.local/reliability.properties` | `.local/reliability.properties` (`SENTRY_DSN_ANDROID=…`), or the env var |

`.local/reliability.properties` holds both keys, `SENTRY_DSN_IOS=` and
`SENTRY_DSN_ANDROID=`. `.local/` and `*.local.xcconfig` are gitignored.

Gates:

- Every successful Xcode Cloud archive runs `tools/sentry-verify-ios-dsn.py --require`
  on the packaged `Info.plist`. No DSN, no archive.
- The Play workflow runs `tools/sentry-require-android-dsn.sh` before bundling
  when `SENTRY_UPLOAD_ENABLED=true`.

## Symbol upload

Off unless `SENTRY_UPLOAD_ENABLED` is exactly `true`. Then
`tools/sentry-install.sh` installs the pinned `sentry-cli` (version in
`tools/sentry-cli-version`, SHA-256 in `tools/sentry-cli-checksums.txt`) and
`tools/sentry-upload.py --platform ios|android` checks and uploads:

- iOS: the archive's dSYMs.
- Android: native `.so` symbols from `:monitor` (Swift core, CMake) and the
  merged app libraries. Minify is off, so there is no ProGuard mapping; a
  `mapping.txt` without `SENTRY_PROGUARD_UUID` fails the upload.

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
