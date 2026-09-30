---
title: Luna Ultra coverage and implementation
description: What is verified on firmware 1.1.15, what the official app does that OpenInstaCine does not, and remaining qualification.
---

Part of the [Luna Ultra reference](../).
Read the overview for firmware, survey scope and evidence levels.

## Coverage and remaining work

| Area | Verified coverage | Remaining qualification |
| --- | --- | --- |
| Connection | Own-client approval, saved-identity reconnect, Wi-Fi wake over Bluetooth, TCP session, bounded recovery on iOS and Android | Approval rejection and timeout, persistence across a camera reboot, multi-client arbitration, maximum BLE write size |
| Live view | 1280×720 HEVC 25 fps, 2 s keyframes, first packet about 0.4 s after start, 271-second continuous window on the Mac lab | End-to-end latency |
| Exposure and color | Every exposure program, EV, kelvin, color 1, 2 and 5, sharpness, filter, ISO ceiling | Charging-flag semantics, the other AF modes' preview behavior |
| Formats | 58 video-mode resolutions stored; official 1:1 3K and 9:16 2.7K values | Whether 100 to 240 fps values record at that rate in normal video mode |
| Gimbal | Modes, speed, stick, recenter, flip, absolute angle, Level, Motion Control, head tracking | Hold while the handle moves; meaning of MOVE field 4 |
| Deep Track | Box, face box and double tap; the `0x85` state stream; cancel | Tracking Framing (cmd 244/245) is not in the app |
| Media | List, metadata, NV12 thumbnails, HTTP with a session, `.lrv` playback, delete | Whether HTTP needs cmd 118 or only an open session (needs a reboot to clear any grant) |
| Audio | Confirmed absent from the phone protocol | Confirm Voice Enhancement and Original Audio metadata values by recording in those modes |
| Timecode | Clock set, frame-clock timing, readout within a frame or two | |
| Notifications | 8198, 8208, 8234, 8275, 8293, 8298, 8308, 8315, 8317, 8334 decoded | 8302 now fires periodically with `sleep = true` while GET 92 reports all false |

## Official-app behavior not in OpenInstaCine

From the firmware 1.1.15 official-app capture. These have no control in the
shared shell yet:

- Filters (18) and sharpness, and contrast and saturation through the whole-panel SET.
- Photo size, RAW, Live Photo, self-timer and beauty.
- Timelapse interval (cmd 18) and duration (54).
- Tracking Framing, the 3 × 3 grid of where the gimbal holds the subject.
- Phone GPS in photos and during capture.

The official iOS app has no controls for audio, stabilization, Stage Mode or
Color Recovery on the Luna.

## Implementation follow-up

1. **Color Recovery.** The phone photography option 73 is accepted but never
   stored, on both 1.0.288 and 1.1.15. The toggle lives on the camera's
   detachable screen. How to expose it in the app is undecided.
2. **Android parity.** The flat I-Log preview preference, AirPods head tracking,
   gimbal limit pulses and a decoder flush on album exit are still missing on
   Android.
3. **Clip audio mode.** `LunaFileMetadata.audioMode` decodes the mode a clip was
   recorded with; the UI does not show it yet.
4. **Poll rate.** OpenInstaCine polls about ten times as often as the official
   app. No cost has been measured.
5. **Re-verification after shell syncs.** Each OpenPocketCine sync is re-checked
   on the camera: live picture, false color over I-Log and the pairing hints.

The feature-by-feature parity table is
[`docs/implementation/luna-ios-status.md`](https://github.com/erik-sutton95/OpenInstaCine/blob/main/docs/implementation/luna-ios-status.md).
This inventory guides future implementation. It does not add those controls to
either shell or replace physical verification.
