---
title: Android app
description: OpenPocketCine's Compose phone shell with a Kotlin Luna adapter. arm64-v8a only, Android 10 or newer.
---

The Android app lives in `Apps/Android/`. It runs the OpenPocketCine Android
shell with OpenInstaCine identity, the yellow accent and a Luna adapter driving
it. It runs against a real Luna Ultra (firmware 1.1.15): pairing, camera Wi-Fi,
live view, camera and gimbal control, and media. iOS is the daily driver, and a
few iOS features are still missing here (below). arm64 phones, Android 10 or
newer.

If pairing or live view fails, tap **Report a problem** on the pairing screen or
in **Operator Setup → System**
([Troubleshooting](../../guides/troubleshooting/)).

## Before pairing

Force quit the Insta360 app on every phone near the camera. It can hold the
camera, and then pairing or the video link never completes. The first pairing
step shows this as a tip, and after 20 seconds with no camera **Still looking**
repeats it.

## Permissions

Pairing asks only for what finding the camera over Bluetooth needs: **Nearby
devices** on Android 12 and newer, or **Location** on Android 10 and 11 (which
also need Location turned on to scan). Joining the camera's Wi-Fi is a system
network request and needs no extra permission. If Android no longer shows a
permission prompt, the pairing screen's **Open Settings** opens this app's page
in Android Settings.

## Field Monitor interface

The chrome, assists, capture drawers, Operator Setup and media match iOS and
OpenPocketCine. The Luna mapping is the same as on iOS: ISO with the 160 stop,
shutter, EV, white balance, the firmware 1.1.15 format table, Standard, I-Log
and Dolby Vision, the Luna shooting modes, zoom chips 1x, 2x, 3x, 6x and 15x,
FOCUS (AF-S, AF-C, Product Showcase), the METER tile, and the gimbal modes
Roll Lock, Roll & Tilt, FPV and FPV-V. See the [iOS app](../ios/) for the
control table.

- Double-tap the picture to start Deep Track with a box square on the sensor;
  in AF-C, face boxes appear and tapping one tracks it.
- Long-press the focus box to lock it; the focus key recenters focus and cancels
  Deep Track.
- Time-of-day timecode from the camera clock, in the status bar.
- The AUDIO tile, meters and assist are hidden: firmware 1.1.15 has no audio on
  the phone protocol.
- LUT **Auto** picks the official I-Log to Rec.709 cube in I-Log, live and in
  playback, and the chip reads **Auto · I-Log → Rec.709**.

## Level

**LEVEL** shows **No level data**: the Luna reports no camera attitude.

### Double-tap Level

The Double-tap choice in the gimbal drawer offers **Level** as on iOS. Android
takes the pitch from the camera-head IMU stream and sends one absolute-angle move.

## EV meter

The Luna reports no metered EV, so the EV meter reads the picture
(`PictureEVMeter.kt`), with a learned offset per transfer curve.

## Motion Control

Programmed A, B and C moves use the gimbal's absolute angle, read every 100 ms,
with the shared Motion Control drawer.

## How Swift reaches Android

The shared monitor core is Swift, cross-compiled for `aarch64-unknown-linux-android29`
and loaded through JNI (`Sources/OpenPocketCineAndroidFacade`). The Luna link is
not: `Apps/Android/luna-adapter` is a separate Kotlin implementation of UCD2
framing, protobuf, GATT, JCA crypto and the network-bound socket. Its request
bytes are pinned to the same captured fixtures as the Swift package
(`LunaControlTest`, `LunaStatusTest`).

| Module | Role |
| --- | --- |
| `:app` | Thin launcher `com.opencapture.openinstacine`: installs the brand, the I-Log camera look and `LunaBackend` |
| `:monitor` | Shared Compose shell, MediaCodec, Vulkan/GLES, assists, library and player (OpenPocketCine `app/src` as a library) |
| OpenCineUI `monitor-ui` | Shared Compose design language from the sibling OpenCineUI checkout (included build); the accent is brand-assigned |
| `:core-api` | Kotlin backend contract: discovery, lifecycle, state, capabilities, frames, optional camera controls |
| `:luna-adapter` | Android GATT, crypto, Wi-Fi and TCP, UCD2 and Luna messages |

The internal `com.opencapture.openpocketcine` package, JNI symbols and the
`OpenPocketCineAndroid` library name remain so the inherited decoder, LUT and
assist calls load. Build recipes: [Setup](../../guides/setup/#android).

## Operator surface

### Connection and recovery

Reconnect tries Bluetooth first when the camera advertised this run, otherwise
the saved Wi-Fi details (sealed in the Keystore) for 20 seconds, then Bluetooth.
The Wi-Fi join is retried in 35-second attempts for up to two minutes after the
Bluetooth handoff, and any Wi-Fi network already on `192.168.42.x` is adopted.
A live drop runs the shared bounded recovery behind the Recovery card: with
phone Wi-Fi turned off and on, the app is back to live in about 30 seconds
without a tap.

### Media

The album lists camera files (proxies hidden), renders thumbnails from the
camera's NV12 frames, deletes by URI (the camera removes the `.lrv` too), and
downloads or plays over HTTP from `192.168.42.1`. Live video pauses while the
album is open. Favorites stay on the phone.

### Still missing versus iOS

- The flat I-Log preview preference.
- AirPods head tracking.
- Gimbal limit pulses; Level uses the IMU pitch only.
- A decoder flush on album exit.

## Releases

Google Play closed testing is built by GitHub Actions on `main` once enabled, and
sideload APKs are published as GitHub Releases. Maintainer setup:
[`docs/android-play-ci.md`](https://github.com/erik-sutton95/OpenInstaCine/blob/main/docs/android-play-ci.md)
and [`docs/RELEASE.md`](https://github.com/erik-sutton95/OpenInstaCine/blob/main/docs/RELEASE.md).
Availability is announced on the
[OpenInstaCine page](https://opencapture.org/openinstacine/).
