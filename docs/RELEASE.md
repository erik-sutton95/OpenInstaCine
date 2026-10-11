# Releases

Same model as OpenPocketCine: trunk-based, short PRs into `main`, squash merge,
annotated `v*` tags for product trains. TestFlight comes from Xcode Cloud on
`main` ([`testflight-ci.md`](testflight-ci.md)), Play closed testing from GitHub
Actions on `main` once `ANDROID_PLAY_UPLOAD=true`
([`android-play-ci.md`](android-play-ci.md)), and sideload APKs from GitHub
Releases. Sentry: [`sentry-deployment.md`](sentry-deployment.md).

Agents do not push `main`, create tags or releases, or touch store and Sentry
accounts. Those are human gates.

## Versions

One product version for both apps, two store counters.

| Field | Source | Now |
| --- | --- | --- |
| Product version | iOS `MARKETING_VERSION` (`ios/Config/Version.xcconfig`) and Android `openinstacine.versionName` (`Apps/Android/gradle.properties`) | `0.1.0` |
| iOS build | Xcode Cloud counter | |
| Android Play build | `ANDROID_VERSION_CODE_BASE` + `github.run_number` (`-PversionCode`) | |
| Android sideload build | `openinstacine.versionCode` (the floor) | `1` |

Keep the two product versions equal. Bump them together only for a new train
(`0.1.0` -> `0.2.0`), then tag `v0.2.0` on `main` (one tag for both platforms).
`just ios-version`, `just android-version`.

## Sideload APK

For Android phones without Play. Only after the app is verified on a physical
phone with a Luna Ultra.

1. **Bump.** One `chore(android)` PR raises `openinstacine.versionCode` by one
   (Android refuses to install over an equal code). Merge it.
2. **Build** from that `main` commit with the sideload key
   `.local/android/press-release.jks` (store path, passwords and alias in
   `.local/android/press-release.env`: `STORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`)
   and the `openinstacine-android` DSN from `.local/reliability.properties`:

   ```bash
   just android-sideload <n>   # -> .local/apk/OpenInstaCine-<version>-<n>-sideload.apk
   ```

   Check `aapt2 dump badging` shows the new `versionCode`, and
   `apksigner verify --print-certs` the same certificate as the previous APK.
3. **Publish**, tag `sideload-v<versionName>-<n>`:

   ```bash
   gh release create sideload-v0.1.0-1 .local/apk/OpenInstaCine-0.1.0-1-sideload.apk \
     --repo erik-sutton95/OpenInstaCine --target <main sha> \
     --title "OpenInstaCine 0.1.0 (1)" --latest \
     --notes "<one to five tester-facing bullets>

   Installs over any earlier OpenInstaCine 0.1.0 sideload build. One arm64 APK, Android 10 or newer. A Google Play copy is signed differently: remove it before installing."
   ```

The sideload key is not the Play upload key, so a sideload install and a Play
install cannot update each other. Back up both keys outside the repo.

## Owner checklist

Account steps no repo change can do. Values are exact.

### Before any release

- [ ] Verify the Android app on a physical arm64 phone (Android 10+) with a Luna
      Ultra on firmware 1.1.15: pair, live view, record, zoom, gimbal. Until then
      it is build-verified only.
- [ ] Publish <https://opencapture.org/openinstacine/privacy>, `/terms` and
      `/support`. The app and store copy link there.
- [ ] Confirm `support@opencapture.org` receives mail (named in-app, in the legal
      text and in tester notes). Change it everywhere if another address is wanted.

### Apple (team `4V4EGQ6LZA`)

- [ ] Certificates, Identifiers & Profiles: explicit App IDs
      `com.opencapture.openinstacine` with **Hotspot Configuration** and **Access
      WiFi Information**, and `com.opencapture.openinstacine.watch`.
- [ ] App Store Connect, New App: iOS, name `OpenInstaCine`, bundle id
      `com.opencapture.openinstacine`, SKU `openinstacine`. Privacy Policy URL
      `https://opencapture.org/openinstacine/privacy`, Support URL
      `https://opencapture.org/openinstacine/support`.
- [ ] Export compliance: the app ships `ITSAppUsesNonExemptEncryption = NO`. The
      camera link uses OS-provided standard crypto (CryptoKit ECDH P-256,
      HKDF-SHA256, AES-GCM) only to authenticate and talk to the paired camera.
      Answer the encryption questionnaire once and keep `NO` only if it confirms
      the exemption.
- [ ] App Privacy: Diagnostics (crash and performance data) and, for Report a
      problem only, optional Contact Info (reply email), user content (message)
      and Photos (images the user picks). All opt-in, not linked to identity, no
      tracking. Mirror OpenPocketCine's answers.
- [ ] Xcode Cloud: grant access to `erik-sutton95/OpenInstaCine`; workflow
      "Archive - iOS", scheme `OpenInstaCine`, deployment TestFlight and App
      Store, branch `main`, Files and Folders filter from
      [`testflight-ci.md`](testflight-ci.md). Environment variables:
      `SENTRY_DSN_IOS` (secret, the `openinstacine-ios` DSN),
      `SENTRY_ORG=opencapture`, `SENTRY_PROJECT=openinstacine-ios`,
      `SENTRY_AUTH_TOKEN` (secret), then `SENTRY_UPLOAD_ENABLED=true`.
- [ ] TestFlight: an Internal group first; External group and public link after
      TestFlight App Review.

### Sentry (org `opencapture`, EU)

- [x] Projects `openinstacine-ios` and `openinstacine-android` exist.
- [ ] Confirm the recursive relay PII rule (already requested) on both projects
      ([`sentry-deployment.md`](sentry-deployment.md#server-privacy-mandatory)).
- [ ] An org auth token for CI with release and debug-file write, stored as
      `SENTRY_AUTH_TOKEN` in Xcode Cloud and GitHub.

### Google Play

- [ ] Play Console: create app `OpenInstaCine`, free, package
      `com.opencapture.openinstacine`, Play App Signing on.
- [ ] Upload keystore: `.local/play-upload.keystore` (PKCS12, alias `upload`) and
      `.local/play-signing.env` with `ANDROID_KEYSTORE_FILE`,
      `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS=upload`,
      `ANDROID_KEY_PASSWORD`. Back both up.
- [ ] First AAB by hand: `just android-bundle` (or dispatch the workflow without
      the service account and download the artifact), upload it in Play Console
      to the existing closed-testing track (`Closed testing - Beta`).
- [ ] Listing from [`android-play-ci.md`](android-play-ci.md), Android
      screenshots, Data safety matching the App Privacy answers, content rating,
      target audience.
- [ ] Service account: a GCP project with `androidpublisher.googleapis.com`
      enabled, a service account (for example
      `openinstacine-play-publisher@openinstacine-play-publisher.iam.gserviceaccount.com`),
      its JSON key at `.local/play-service-account.json`, invited in Play Console
      Users and permissions for this app with release to testing tracks.

### GitHub (`erik-sutton95/OpenInstaCine`)

- [ ] Restrict environment `play-closed` to protected branches. Configure secrets
      `ANDROID_KEYSTORE_BASE64`,
      `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`,
      `PLAY_SERVICE_ACCOUNT_JSON`, `SENTRY_DSN_ANDROID`, `SENTRY_AUTH_TOKEN`.
      `just android-play-sync-secrets` sets all but `SENTRY_AUTH_TOKEN` from `.local/`.
- [ ] Repository variables: `SENTRY_ORG=opencapture`,
      `SENTRY_PROJECT=openinstacine-android`, `SENTRY_UPLOAD_ENABLED=true`,
      `ANDROID_VERSION_CODE_BASE` (above any manual upload), and last
      `ANDROID_PLAY_UPLOAD=true` (after the first Console AAB and the service
      account invite).
- [ ] Branch protection on `main` requiring the **CI gate** check.
- [ ] Sideload key: `.local/android/press-release.jks` and
      `.local/android/press-release.env`, new for OpenInstaCine (never
      OpenPocketCine's key). Back them up.
