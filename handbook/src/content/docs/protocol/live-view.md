---
title: Live view
description: HEVC preview over the UCD2 TCP socket, the live-start body, the media header, and the IMU, shutter and Deep Track side streams.
---

Live view rides the same TCP `192.168.42.1:6666` connection as control, as UCD2
**type-1** media frames. There is no separate port and no UDP.

## Codec

| Property | Measured |
| --- | --- |
| Codec | **HEVC Main**, 8-bit 4:2:0 |
| Size | **1280×720** (720×1280 and 1280×960 seen for other formats) |
| Rate | **25 fps** (29 in slow motion; follows long shutters down to about 5 fps) |
| Range and color | Limited range, BT.709 primaries, transfer and matrix |
| Keyframes | IDR every 50 frames (2 s), VPS/SPS/PPS before each |
| First picture | First video packet and keyframe about 0.4 s after the start request |

Measured on firmware 1.0.288 and again on 1.1.15. In **I-Log** the preview
carries the log curve (black near Y 37 against about 16 in Standard) but the VUI
still says BT.709. Treat the picture as log when the camera's color mode is
I-Log; do not trust the VUI. The live picture is also a different stream from
the recording: record resolution, rate and color do not follow from it.

## Transport

Type-1 frames arrive on the control socket between replies and notifications.
Feed every TCP chunk to the [reassembler](../ucd2-transport/#reassembly); a media
frame is complete only after its checksum passes.

## Enable

Send cmd **118** `{1:5}` first: it wakes the gimbal, which otherwise stays folded
down and gives a grey or black picture. Then cmd **1** with the exact captured
body:

```text
10 01 20 80 f7 02 38 2b 50 0e 60 01
```

| field | value | schema name |
|---:|---:|---|
| 2 | 1 | `enableVideo` |
| 4 | 48000 | `audioSampleRate` |
| 7 | 43 | `resolution` (named 1280×720 p30; measured 25 fps) |
| 10 | 14 | `resolution1` (a second stream, not decoded) |
| 12 | 1 | `enableRotate` |

The reply is 200 with an empty body (about 36 ms on firmware 1.1.15), and
notification **8234** reports the stream's width, height and rate. Stop with
cmd **2**. The fields are not exposed as settings: this body is the one the
official app sends and the one that was measured.

## Per packet

A type-1 payload starts with a nine-byte media header:

```text
subtype:u8 | timestamp:u64le (milliseconds) | data
```

The timestamp is a monotonic frame clock since boot: video packets are 40 apart
at 25 fps. It does not move when the camera clock is set, so it is not time of
day; see [timecode](../../devices/luna-ultra/settings/#timecode).

## Media subtypes

| Subtype | Content | Rate | Use |
|---|---|---|---|
| `0x20` | HEVC Annex-B access unit | Every video frame | Hand to the native decoder |
| `0x30` | Camera-head IMU: records of u64 ms plus six little-endian doubles (accelerometer x, y, z in g; gyro x, y, z in rad/s) | 1 kHz samples, about 100 per frame | Level, head-track gyro, gimbal pose fallback. Pan right is +gyro z, tilt up is +gyro y |
| `0x40` | Live shutter time in seconds, little-endian double | Every video frame | The shutter the camera is applying, also in Auto (0.0300 at EV +1, 0.0200 at EV -1) |
| `0x85` | Deep Track state: protobuf `{1: ms, 2: state, 4: {x, y, w, h}}` | Every video frame while tracking | 2 tracking, 3 lost, 5 idle; box in preview fractions |

There is **no audio subtype**: starting live with `enableAudio` is accepted but
no AAC arrives. See [Exposure, focus and audio](../../devices/luna-ultra/settings/#audio).

## Per frame

Only `0x20` carries video. Strip the nine-byte header and pass the Annex-B bytes
to VideoToolbox (iOS) or MediaCodec (Android). An empty `0x20` payload is
malformed. Scopes and assists run on the decoded pixels.

## Reproducing protocol investigations

The Mac lab (`just luna-preview 20`) saves a bounded take's HEVC elementary
stream for FFprobe; `just luna-view` shows a live window. `tools/LunaProbe live
8 out.hevc` does the same through the Swift package. Captures and footage stay
in gitignored folders; see
[`docs/mac-preview.md`](https://github.com/erik-sutton95/OpenInstaCine/blob/main/docs/mac-preview.md).
