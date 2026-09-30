---
title: Luna Ultra shooting modes and formats
description: Mode switch commands and banks, the accepted record resolution list, photo, pano and timelapse options, and the app format picker.
---

Part of the [Luna Ultra reference](../).
Read the overview for firmware, survey scope and evidence levels.

## Shooting modes

The shooting mode is a **device option** (cmd 7), not a photography option.
Video-family modes use option **41** (`VIDEO_SUB_MODE`), photo-family modes
option **40** (`PHOTO_SUB_MODE`). The camera answers every switch with
notification **8275** (photo sub-mode, video sub-mode, sensor), then 8334 (zoom
reset to 1.0) and 8234 (live stream parameters).

| Mode | Wire | GET bank (`FunctionMode`) the official app reads | Firmware 1.1.15 |
| --- | --- | ---: | --- |
| Video | option 41 omitted (0) | 7 | Verified |
| Timelapse | option 41 = 2 | 2 | Verified |
| TimeShift | option 41 = 4 | 12 | Verified |
| Slow Motion | option 41 = 9 | 21 | Verified; live stream becomes 1280×720 at 29 |
| PureVideo | option 41 = 11 | 27 | Verified |
| Photo | option 40 = 0 | 6 | Verified |
| Pano | option 40 = 8 | 67 | Verified; sensor field reads 1 |

### Mode banks

Settings are stored per mode. On v1.0.288 the `FunctionMode` field of a GET or
SET selected the bank. **On v1.1.15 it is ignored**: every GET and SET acts on
the bank of the *current* shooting mode. In slow motion every function mode
returned the slow-motion bank (resolution 214, exposure program 5), and a SET
with function mode 21 while in video mode wrote the video bank. OpenInstaCine
still sends the matching function mode, which is harmless.

### Recording per mode

Record start carries the mode in field 1 and stop carries it in field 2:

| Mode | Start | Stop |
| --- | --- | --- |
| Video, PureVideo | cmd 4 `{1:1}` | cmd 5 `{1:metadata, 2:1}` |
| TimeShift | cmd 4 `{1:4}` | cmd 5 `{…, 2:4}` |
| Slow Motion | cmd 4 `{1:9}` | cmd 5 `{…, 2:9}` |
| Timelapse | cmd 22 `{1:1}` | cmd 23 `{1:1, 2:metadata}` |

All five modes recorded a file and stopped from the iPhone app on v1.1.15.
Details of the stop reply are in [Original media](../media/#recording-and-photos).

## Formats

Resolution, frame rate and aspect are **one enum**, photography option **31**
(`RECORD_RESOLUTION`), written with types `[31, 63]`. A stored value fires
notification 8293 within 0.04 s; a rejected value fires nothing and the value
stays unchanged. The sweep tried 289 schema candidates in video mode on v1.1.15.
The camera drops a change that arrives while it is still reconfiguring, so every
reject was retried with a 2-second settle.

| Geometry | Accepted fps (enum value) |
| --- | --- |
| 7680×4320 (8K) | 24 (210), 25 (211), 30 (154) |
| 7680×3268 (8K 2.35:1) | 24 (219), 25 (212), 30 (213) |
| 3840×2160 (4K) | 24 (49), 25 (48), 30 (24), 48 (258), 50 (92), 60 (23), 100 (220), 120 (214) |
| 3840×1632 (4K 2.35:1) | 24 (440), 25 (439), 30 (438), 48 (437), 50 (436), 60 (435), 100 (434), 120 (433) |
| 2688×1520 (2.7K) | 24 (248), 25 (247), 30 (246), 48 (331), 50 (245), 60 (244), 100 (243), 120 (242) |
| 1920×1080 | 24 (53), 25 (52), 30 (29), 48 (260), 50 (81), 60 (40), 100 (150), 120 (28), 200 (26), 240 (27) |
| 2160×3840 (9:16 4K) | 24 (126), 25 (125), 30 (124) |
| 1728×3072 (9:16 3K) | 24 (455), 25 (454), 30 (453), 48 (452), 50 (451), 60 (450) |
| 1520×2688 (9:16 2.7K) | 24 (445), 25 (444), 30 (443), 48 (468), 50 (442), 60 (441) |
| 1080×1920 (9:16) | 24 (85), 25 (71), 30 (64), 48 (298), 50 (82), 60 (68) |
| 1:1 3K | 119, 120, 121, 446, 447, 448 (from the official app) |

Still rejected: 1080×1920 at 100 to 240, 2160×3840 at 48 and above, 4K 15 and
180, 1620×2880, 1520×2688 at 100 and 120. No 4:3, 3:4, 2720×1530, 5.3K, 6K or
8K 4:3 value was accepted. Whether the 100 to 240 fps values record at that rate
in *normal* video mode was not tested; slow motion has its own bank (default
214). The official app's 1080p 240 choice also writes color 35 = 1 (Standard).

Enum names and measured rates can differ: 30p banks report 29 in notification
8234. `LunaVideoResolution` in the protocol package maps all 476 schema values
to width, height, fps and an aspect label.

## Photo

Photo mode shoots with an empty cmd 3 (`TAKE_PICTURE`); the official app also
attaches phone GPS, which OpenInstaCine leaves out. In photo mode the exposure
program is written to both still (20) and video (21) exposure, and photo EV adds
type 77 = 1. The official app's photo options on v1.1.15:

| Option | Wire |
| --- | --- |
| Photo size and aspect | types `[40, 63, 30]`: 1:1 `30:1 40:30`, 16:9 `40:29`, 9:16 `30:2 40:54`, 3:4 `30:6 40:56`, 4:3 `30:4 40:34`, UHD `40:33` |
| RAW | type 25 |
| Live Photo | type 85, `{2:2}` on, `{2:1}` off |
| Self-timer | type 26, 3 or 5 s |
| Beauty | type 90 |

A verified photo was 3520×2644 JPEG.

## Pano

Pano is option 40 = 8. The shutter is cmd 3 with field 1 = **5**: the gimbal
sweeps and stitches 19 frames; notification 8208 reports progress. Pano reads
back as Photo in OpenInstaCine.

## Timelapse

The interval is cmd **18** `{1:{1:0xFFFFFFFF, 2:milliseconds}, 2:1}`; duration
is photography type 54 in seconds. Cmd 17 reads the options (observed interval
1000 ms). Recording uses cmd 22 and 23.

## OpenInstaCine format picker

The shared FORMAT drum lists every geometry above that the shell can show: 8K,
8K 2.35:1, 4K, 4K 2.35:1, 2.7K, 1080p, 1:1 3K, and 9:16 4K, 3K, 2.7K and 1080.
The session mirrors the decoded picture's aspect, so 9:16 and 1:1 formats lay
out like OpenPocketCine's vertical picture handling. Timelapse interval,
duration, photo size, RAW, Live Photo, timer and beauty have no control in the
shared shell yet.
