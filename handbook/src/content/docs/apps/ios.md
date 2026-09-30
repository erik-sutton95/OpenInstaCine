---
title: iOS app
description: SwiftUI iPhone and iPad shell shared with OpenPocketCine, with a Luna Ultra backend. Physical device for BLE and camera Wi-Fi.
---

The iOS app is a universal iPhone and iPad SwiftUI shell in
`ios/OpenInstaCine/`. It is the OpenPocketCine monitor with a yellow accent and
a Luna Ultra backend in place of the DJI link, and it is the daily driver.
Generate the Xcode project with XcodeGen: see [Setup](../../guides/setup/).

Luna-specific code lives in `CameraSession.swift`, `CameraSessionControls.swift`,
`CameraMedia.swift` (Luna extension), `LunaShellMapping.swift`,
`LunaThumbnailImage.swift`, `OpenInstaCineBrand.swift`,
`OsmoCameraPageAdapter.swift` and `OsmoMonitorPresentation.swift`. The `Osmo*`
names are kept so shared call sites bind unchanged. Everything else in
`ios/OpenInstaCine` is the shared shell.

## Field Monitor interface

The screens, drawers and gestures are OpenPocketCine's. Portrait phones place
exposure values in rows above the system buttons; landscape puts them along the
bottom of the picture. Tap a value for its details drawer; hold or drag for a
compact dial and lift to apply. Camera controls hold your selection while the
camera confirms it, so an older status update does not briefly move the dial
back. White balance kelvin and metering apply on the camera 3.5 to 5 seconds
later, so their pins last longer (5 and 6 seconds).

What changes for the Luna:

| Control | On the Luna |
| --- | --- |
| ISO | Auto plus 100, 160, 200, 400, 800, 1600, 3200, 6400. No auto ISO ceiling or native ISO hop. |
| Shutter | 1/8000 to 1/5. Manual exposure sends program, ISO and shutter in one message. Shutter angle writes 1/N for the current frame rate. |
| White balance | Auto or 2000 to 10000 K. No tint. |
| EV | Exposure bias in thirds. |
| FORMAT | Every resolution firmware 1.1.15 stores: 8K, 8K 2.35:1, 4K, 4K 2.35:1, 2.7K, 1080p, 1:1 3K, and 9:16 4K, 3K, 2.7K and 1080. |
| Color | Standard, I-Log, Dolby Vision. The camera refuses Vivid and HDR. |
| Shooting mode | Video, Timelapse, TimeShift, Slow Motion, PureVideo, Photo. |
| FOCUS | AF-S, AF-C and Product Showcase. |
| METER | A tile beside EXPOSURE: tap to switch Matrix and Face Priority. |
| Zoom | Chips 1x, 2x, 3x, 6x and 15x, plus pinch. Digital zoom to 15x. |
| Gimbal | Roll Lock, Roll & Tilt, FPV and FPV-V; Slow, Default and Fast; recenter and flip. |

Tap the picture to focus: the box is the official app's size, centered on the
tap. Long-press the focus box to lock it so a stray tap cannot move it; the
focus key recenters it.

### Deep Track

Drag a box around a subject, tap a face box while in AF-C, or double-tap the
picture to start Deep Track. The search box is white until the camera locks,
then the camera's own box turns green and follows the subject. If the subject is
lost the last box turns white while the camera keeps searching; cancel from the
box or the focus key. The camera drives the gimbal itself while tracking.

### Timecode

The status bar, portrait bar and Apple Watch show time-of-day timecode that
matches the camera's own. The app sets the camera clock when live view starts
and times each frame from the camera's frame clock. See
[Luna timecode](../../devices/luna-ultra/settings/#timecode).

## Level

**LEVEL** in View Assist needs camera attitude, which the Luna does not report,
so it shows **No level data**. It never turns green without data.

### Double-tap Level

In the gimbal drawer, **Double-tap** chooses what a double-tap on the joystick
or Circle/B on a game controller does:

- **Recenter** (default): the camera's own recenter.
- **Level**: an absolute-angle move that takes out the pitch error the
  camera-head IMU measures against gravity, keeping yaw, with one refining pass.
  It lands within 0.4° of world level in about 2 seconds.

## Motion Control and head tracking

**Motion Control** records A, B and C points from the gimbal's absolute angle
and replays the move with a countdown, smoothing, loop, pause and stop. Zoom
changes between points are refused.

**AirPods head tracking** steers the gimbal from headphone motion. It drives the
stick in a 30 Hz loop closed on the gimbal angle, which is smoother than
streaming target angles. Pan tops out at about 63°/s; faster head turns trail.
The on-screen stick or a game controller cancels an aim, head tracking or a
programmed move. Details:
[Zoom and gimbal controls](../../devices/luna-ultra/controls/).

## EV meter

Enable **EV** in View Assist to show the exposure line. The Luna sends no
metered EV, so on OpenInstaCine the meter reads the picture: the median against
18% gray, less the learned auto-exposure placement. Auto exposure reads about
0.0.

## Moving scopes

WAVE, PARADE, HISTO, VECTOR, LIGHTS and ND drag and resize as in OpenPocketCine.
Long-press a View Assist toolbar button for its settings.

## What it does

- Bluetooth pairing with owner approval on the camera, camera Wi-Fi join, saved
  cameras, Bluetooth-first reconnect with a saved Wi-Fi fallback, bounded
  recovery after a drop.
- 1280×720 HEVC live view at 25 fps.
- Scopes and assists: waveform, RGB parade, histogram, vectorscope, false color
  (CineStop, Video, IRE and Limits, reading LOG or 709), zebras, Traffic Lights,
  focus peaking, EV meter, ND suggestions, grids, aspect guides, crosshair,
  mirror and de-squeeze.
- LUTs: **Auto** picks the official Insta360 I-Log to Rec.709 cube for I-Log.
  Creative and Custom `.cube` looks are unchanged from OpenPocketCine. With the
  LUT off, the I-Log picture shows flat.
- Record, photo and the REC timer; per-mode record commands for Timelapse,
  TimeShift and Slow Motion.
- Media: browse clips and stills on the camera with camera thumbnails, play the
  `.lrv` proxy with the same scopes and assists as live view, download originals,
  delete takes. Favorites are stored on the phone.
- Lock, DISP clean view and the chrome editor.
- Apple Watch companion.

Not on the Luna: live audio control and meters (the camera sets audio on its own
screen), aperture (fixed iris), AE and AWB lock (the camera does not report the
applied auto values), Multiview, and Wi-Fi or Hotspot setups (the Luna only
connects over its own network). Color Recovery is not in the app yet.

Pairing asks for Bluetooth and Local Network access; if either is off, the
failure offers **Open Settings**. Motion access is only for AirPods head
tracking.

## Device requirements

iOS 17 or newer. BLE, Local Network, and Hotspot Configuration do not work in the
Simulator; a Simulator build can still reach a camera over the Mac's Wi-Fi
([Setup](../../guides/setup/#simulator-live-testing)). Protocol tests
(`just core-test`) do not need hardware.

Platform notes for the wire (Hotspot Configuration, Local Network, CoreBluetooth):
[iOS protocol notes](../../protocol/ios/).

## Releases

TestFlight builds come from Xcode Cloud on `main`. Pull requests that change the
app replace
[`ios/TestFlight/WhatToTest.en-US.txt`](https://github.com/erik-sutton95/OpenInstaCine/blob/main/ios/TestFlight/WhatToTest.en-US.txt)
with the this-build window. Maintainer setup:
[`docs/testflight-ci.md`](https://github.com/erik-sutton95/OpenInstaCine/blob/main/docs/testflight-ci.md)
and [`docs/RELEASE.md`](https://github.com/erik-sutton95/OpenInstaCine/blob/main/docs/RELEASE.md).
Availability is announced on the
[OpenInstaCine page](https://opencapture.org/openinstacine/).

If pairing or live view fails, tap **Report a problem** on the pairing screen or
in **Operator Setup → System**. Technical details and a reply email are optional.
