---
title: Setup and build
description: Install tooling, generate the iOS project, build the Android app, and run the tests.
---

`just` is the single entry point. From a clone of
[erik-sutton95/OpenInstaCine](https://github.com/erik-sutton95/OpenInstaCine):

```bash
just              # list all recipes
just check        # hygiene: lab parser tests, release-note checks, whitespace
just core-test    # shared core and Luna protocol package (swift test)
```

Shared protocol logic is tested without a camera. Pairing and live view need a
**physical** phone and an **Insta360 Luna Ultra on firmware 1.1.15**. The
first connection asks you to approve the phone on the camera's touchscreen.

## iOS

Needs Xcode 26, [XcodeGen](https://github.com/yonaskolov/XcodeGen) and `just`
(`brew install just xcodegen`):

```bash
just ios-generate         # generate ios/OpenInstaCine.xcodeproj
just ios-build            # Simulator build, no signing
just ios-run [device]     # signed build, install and launch on a USB iPhone
just ios-test             # app unit tests
```

The Simulator has no Bluetooth or hotspot API. To run on a phone, set your Team
under Signing and enable **Hotspot Configuration** and **Access WiFi
Information** on the App ID. The app targets iOS 17 and later.

More: [iOS app](../../apps/ios/).

## Android

Needs a JDK (the recipes default to Homebrew's `openjdk`), Android SDK with NDK
r27, and the Swift Android SDK (Swift 6.3.3); CI installs it with
[`scripts/ci-install-swift-android.sh`](https://github.com/erik-sutton95/OpenInstaCine/blob/main/scripts/ci-install-swift-android.sh).
From the repo root:

```bash
just android-build    # debug APK
just android-check    # debug APK, unit tests and lint for app, monitor and luna-adapter
```

The app is **arm64-v8a only**, Android 10 or newer. The debug build is named
**OpenInstaCine Dev** with a grayscale launcher mark. More:
[Android app](../../apps/android/).

## Simulator live testing

The Simulator has no Bluetooth or hotspot API, but it shares the Mac's network.
In a Simulator build the Luna backend skips Bluetooth and talks straight to a
camera on the current network. Join the Mac's Wi-Fi to the camera network
(camera at `192.168.42.1`), keep internet on another interface, install the
DEBUG build, and launch it with a client identity the camera has already
approved (Simulator builds read it from the `LUNA_IDENTITY` environment
variable). The identity is private: keep it in `.local/` and never paste it into
commits, docs or logs.

DEBUG builds (never Release) run a small HTTP remote on TCP 18780 that
[`tools/oic_remote.py`](https://github.com/erik-sutton95/OpenInstaCine/blob/main/tools/oic_remote.py)
drives: connect, change settings, move the gimbal, open media, take a
screenshot or grab the last decoded frame.

```bash
export OIC_URL=http://127.0.0.1:18780
python3 tools/oic_remote.py state          # phase, live stats, camera settings
python3 tools/oic_remote.py do '{"action":"iso","value":400}'
python3 tools/oic_remote.py shot out.png   # key window snapshot
```

The full action list and the scripted XCUITest walkthrough are in
[`docs/DEVELOPMENT.md`](https://github.com/erik-sutton95/OpenInstaCine/blob/main/docs/DEVELOPMENT.md).

## Mac live-view lab

A Python viewer connects to a real camera without the app. It is the research
harness the protocol was mapped with:

```bash
just lab-setup                              # Python venv
just luna-authorize 'EXACT_ADVERTISED_NAME' # first time: approve on the camera
just luna-view                              # BLE, Wi-Fi join, live window
```

It may change the Mac's Wi-Fi and removes only the camera network profile it
added. `tools/LunaProbe` is a Swift command-line client over the same protocol
package, used for the firmware 1.1.15 verification. Details:
[`docs/mac-preview.md`](https://github.com/erik-sutton95/OpenInstaCine/blob/main/docs/mac-preview.md).

## Shared shell with OpenPocketCine

The monitor UI is shared with [OpenPocketCine](https://openpocketcine.app/).
`just sync-openpocketcine` re-copies the iOS shell from a sibling
`../OpenPocketCine` checkout and leaves the Luna files alone. The contract
between the two apps is
[`docs/SHARED-MONITOR-ENGINE.md`](https://github.com/erik-sutton95/OpenInstaCine/blob/main/docs/SHARED-MONITOR-ENGINE.md).

## This handbook

```bash
cd handbook
npm ci
npm run dev           # http://localhost:4321/
HANDBOOK_BASE=/openinstacine/docs npm run build
```

It is published at
[opencapture.org/openinstacine/docs](https://opencapture.org/openinstacine/docs/)
when `handbook/` changes on `main`.

## Contributing

Bugs go in [GitHub issues](https://github.com/erik-sutton95/OpenInstaCine/issues/new).
Pull requests follow Conventional Commits and the
[pull request template](https://github.com/erik-sutton95/OpenInstaCine/blob/main/.github/PULL_REQUEST_TEMPLATE.md):
`just check`, the relevant native check (`just core-test`, `just ios-build` or
`just android-check`), and docs updated when behavior or setup changed.
Community rules: [Code of Conduct](https://github.com/erik-sutton95/OpenInstaCine/blob/main/CODE_OF_CONDUCT.md).

## Hygiene

Camera Wi-Fi passwords, approval identities, packet captures, camera footage,
signing material and unofficial LUT dumps stay out of git. The app keeps its
approval identity and the camera Wi-Fi password in the Keychain (iOS) or
Keystore (Android).
