---
title: Luna Ultra exposure, focus and audio
description: Exposure programs, white balance, color and filters, AF mode, metering and tap focus, the missing audio controls, and timecode.
---

Part of the [Luna Ultra reference](../).
Read the overview for firmware, survey scope and evidence levels.

All settings on this page are **photography options**: GET with cmd 10 (field 1
= types, field 2 = function mode), SET with cmd 9 (field 1 = types being set,
field 2 = a nested `PhotographyOptions`, field 3 = function mode). The official
app serializes a whole options message on every SET and the camera applies only
the types listed in field 1. The SET reply lists the stored types in field 1; a
transport 200 alone is not enough.

## Exposure

Exposure is option **21** `VIDEO_EXPOSURE_OPTIONS` (20 for stills), a nested
`ExposureOptions` of `program`, `iso` and `shutter_speed` (seconds, double).
Programs: 0 Auto, 1 ISO priority, 2 shutter priority, 3 Manual. The official app
always writes types `[21, 24, 100]` (24 is the ISO ceiling, 100 the IQ 3A mode).

| Setting | Sent | Readback on v1.1.15 |
| --- | --- | --- |
| Auto | program 0 | Verified |
| ISO priority | 100, 160, 400, 800, 1600, 3200, 6400 | Verified. 50 and 12800 are also stored: the camera does not validate range |
| Shutter priority | 1/8000 to 1/5 | Verified. 1/2, 1 s and 1/16000 are also stored |
| Manual | program 3 with ISO and shutter, types `[21, 100]` | Verified (800 1/60, 200 1/25, 6400 1/5) |
| ISO ceiling | type 24: 400, 1600, 3200, 6400 or 0 | Verified |
| EV | type 7, sint32 tenths (+0.3 = 3, zigzag 6) | Verified +0.3, -0.7, +2, -2, 0 |

:::caution[Manual exposure and the ISO ceiling]
Manual with an ISO must **not** carry the ISO ceiling sentinel (type 24 =
4294964096). With it, the camera converts program 3 to program 2 and drops the
ISO. OpenInstaCine's encoder sends types `[21, 100]` for manual with ISO.
:::

Long shutters are honored and the live preview follows them: at manual ISO 6400,
1/25 gives 25.9 fps, 1/15 gives 14.8, 1/10 gives 10.5 and 1/5 gives 4.98. The
camera reports only the values that were set (ISO 0 and shutter 0 in Auto), never
the applied auto values, so AE lock has nothing to pin.

## White balance

Kelvin is option **39**; 0 means Auto. The camera applies a kelvin change
**3.5 to 3.9 s** after the SET. Verified: 2000, 2500, 3200, 4000, 5600, 6500,
8000 and 10000 K, and Auto. There is no tint. Option 13 (the preset field) has no
readable effect.

:::caution[GET 13 clobbers 39]
The camera answers a GET of type 13 by writing 39 = 0. A GET listing `[39, 13]`
therefore reports Auto even when a kelvin is stored. Read `[13, 39]` or `[39]`.
:::

## Color, sharpness and filters

| Option | Values | Firmware 1.1.15 |
| --- | --- | --- |
| Color mode, 35 | 1 Standard, 2 I-Log, 5 Dolby Vision | Verified. Vivid (3) replies 200 but stores Standard; HDR (4) is ignored. Dolby needs Auto shutter and sets filter strength 3 |
| Sharpness, 6 | 0 Low, 1 Medium, 2 High | Verified in Standard. In I-Log the camera always *reports* 1; the stored value shows after switching to Standard |
| Filter, 18 | Standard 0, NC Film 24, GR-F 26, Positive Film 34, Leica Chrome 36, Cinematic 37, Fresh 38, Leica Natural 15, Leica Vivid 16 | Observed from the official app; SET verified for 0 and 1 |
| Filter strength, 104 | integer | Verified; notification 8334 fires |
| I-Log switch, 72 | | No effect; color is option 35 |
| Color Recovery, 73 | | Accepted, never stored or reported. Not a working toggle on the phone protocol |

A color change takes about 1.2 s (the camera switches its image pipeline).
Contrast (3), saturation (4) and the other panel values are written by the
official app in one whole-panel SET of types
`31,63,21,24,100,7,39,72,18,104,6,46,53,91,35,93,101,3,4`.

The I-Log live preview carries the log curve (black near Y 37 versus about 16 in
Standard) while the stream's VUI still says BT.709. Color Recovery is set on the
camera's detachable screen; the phone app has no switch for it.

## Focus and metering

| Option | Values | Firmware 1.1.15 |
| --- | --- | --- |
| AF mode, 93 | 1 AF-S, 3 AF-C, 6 Product Showcase (official names). 0, 2, 4, 5 are stored but never offered; 7 is ignored | Verified; stored at once. Shared across function modes |
| Metering, 46 | 0 Matrix, 1 Face Priority | Verified; stored **3.7 to 4.9 s** after the SET, like kelvin |
| Tap focus, 94 | `AF_TRIGGER_PARAMS`: type 1 (start) plus a float ROI x, y, w, h in preview fractions | Accepted; no stored state |

Individual SETs work for both 93 and 46; the whole-panel SET is not needed. No
notification arrives for these two options, so re-read them after a change.

The official tap-focus box is **0.1545 × 0.2727** of the preview with the camera
upright (0.0869 × 0.1545 was the camera lying on its side). The box is centered
on the tap.

## Audio

**Firmware 1.1.15 exposes no audio mode control on the phone protocol.** The Luna
manual lists three modes (Original Audio, Wind Reduction, Voice Enhancement),
set on the camera or its detachable screen.

| Candidate | Result on v1.1.15 |
| --- | --- |
| Device option 109 `AUDIO_WNR_TYPE` | Not implemented: GET is not echoed; SET replies empty and changes nothing |
| Device option 108 `AUDIO_RECODER_ENABLE` | Not implemented |
| Photography options 1 to 300 | Nothing above 104 carries a value; no audio entry in the schema |
| cmd 251 `SET_AUDIO_STREAM` while live | Empty reply, no new media subtype |
| Live start with `enableAudio` | Accepted, but no AAC subtype appears |

The only audio value the camera reports is the mode a clip was recorded with:
`ExtraMetadata.audio_mode` (field 61) in the clip's metadata. Observed 20
`AI_WINDREDUCTION_INNER` (Wind Reduction); 21 Voice Enhancement and 24 Original
Audio are inferred from the schema. No live audio or levels reach the phone.

## Timecode

The camera's timecode is **time of day from its own clock**. The camera menu only
switches timecode on or off and shows it on the preview. **Nothing on the phone
protocol carries timecode**: no option, notification, clip metadata field or
`tmcd` track.

| Request | Body | Notes |
| --- | --- | --- |
| cmd 7, options 12, 13, 175 | `{12: unix seconds, 13: seconds east of GMT, 175: zone name}` | What the official app sends on every connect |
| cmd 214 `SYNCTIME_ACCURATE` | `{1: {1: s, 2: ms}, 2: count}` | Sent twice (count 0, then 1). Afterwards the camera clock matched the phone to the second |

The camera's time of day cannot be read back. Every live media frame carries a
u64 millisecond stamp on a monotonic frame clock that does not move when the time
is set. OpenInstaCine sets the clock at each live start, pins the frame clock to
the phone clock by the earliest frame arrival minus 90 ms, and formats each frame
as non-drop `HH:MM:SS:FF`. The readout is within a frame or two of the camera's
own. Full notes:
[`docs/research/luna-timecode.md`](https://github.com/erik-sutton95/OpenInstaCine/blob/main/docs/research/luna-timecode.md).
