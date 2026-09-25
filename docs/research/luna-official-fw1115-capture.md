# Official Insta360 iOS app on Luna Ultra firmware v1.1.15: full UI capture

Captured 2026-09-25 (07:45 to 10:15 CEST). Camera: Luna Ultra `XBQFN7`,
firmware **v1.1.15** (the app's Firmware Version row and `GET_FILE_EXTRA`
field 3 both read `v1.1.15`). Phone: USB iPhone driving the official app
(`com.insta360.oner`) through the XC driver (`tools/luna_xc_bridge.py`).
Traffic: RVI `rvi0`, `tcpdump host 192.168.42.1`, one pcap per UI area.

This closes the "Official app on v1.1.15 (task 5): blocked" item in
[luna-fw-1.1.15-verification.md](luna-fw-1.1.15-verification.md). Command
numbers use `tools/luna_message_codes.json`; option names use
`tools/luna_photography_options.json` and `tools/luna_device_options.json`.

## Takes and how to re-decode

Raw takes are local only (`.local/` is git-ignored):
`.local/official-fw1115/<NN-name>.pcap`, the tap log `events.log`
(epoch, take, driver JSON, note) and per-take `*.decoded.txt` / `*.decoded.json`.

```sh
python3 tools/luna_pcap_decode.py .local/official-fw1115/05-color.pcap \
    --events .local/official-fw1115/events.log          # requests + notifies, taps inline
python3 tools/luna_pcap_decode.py <take>.pcap --all      # also every camera reply
```

`tools/luna_pcap_decode.py` is new. It strips the 24-byte classic-pcap header
that macOS `tcpdump -i rvi0` writes in front of the pcapng section (plain
`tshark` reports the file as corrupt otherwise), reassembles TCP 6666 per
direction with `ucd2.Reassembler`, and names option types and function modes.

| take | UI area |
| --- | --- |
| 01-connect | terminate, launch, Album tab, capture tab (connect, live start) |
| 02-modes | every mode in the "all modes" grid |
| 03-settings-panel | capture Settings: grid, histogram, joystick, storage location, gimbal follow speed, calibration page |
| 04-resolution | video ratio / resolution / fps picker, every cell |
| 05-color | filter row, filter strength |
| 06-exposure | AUTO MODE panel: Normal EV, reset, Pro: shutter, ISO, EV, WB, metering, focus, BC, contrast, saturation, sharpness, colour |
| 07-gimbal-zoom | zoom presets, zoom-bar swipe, recenter, flip, gimbal modes, joystick, tap focus, long press |
| 08-misc | video record, photo mode (ratio, format, live photo, shutter, timer, beauty, Pro exposure) |
| 09 to 12 | settings deep-dive, timelapse / TimeShift / slow-motion / PureVideo panels, leave preview, Me > Other Settings (storage, format dialog cancelled, region viewed only), Device Information |
| 13-album, 14-delete-photo | player, favorite, LUT toggle, download, delete of the two files this session created |
| 15-pro-retry | Pro pickers retried; preview drag for a quick EV |
| 16-mode-records, 17-cleanup | timelapse / TimeShift / slow-motion records, multi-delete of those three files |

Nothing was formatted, no firmware or Wi-Fi command was sent, no pre-existing
file was deleted. Created and deleted: `VID_20260925_090428_004`,
`IMG_20260925_091016_005`, `VID_20260925_101042_004` (timelapse),
`VID_20260925_101119_005` (TimeShift), `VID_20260925_101150_006` (slow motion).
The album is back to its original 3 files. A photo copy is in the phone's
Photos library from the Download test.

## Headline differences from the v1.0.288 catalog and from OpenInstaCine

1. **No phone heartbeat.** After the TCP preface the official app sends exactly
   **one** UCD2 type-5 frame (0.57 s after the preface, between the first
   requests) and never another; 0 phone type-5 frames in a 103 s take. The
   camera sends type 5 at **1.0 Hz**. OpenInstaCine sends type 5 every 2 s.
2. **Polls are every 10 s, not 1 s.** Steady state (live preview open) is three
   requests every 10.0 s (median of 60+ samples in two takes):
   cmd 8 `[11, 20, 85, 180]`, cmd 8 `[65, 128]`, cmd 10 `[99]` (current mode).
   **Cmd 15 is not polled**; it is sent once right after record start / photo.
   OpenInstaCine polls cmd 15 every 1 s and cmd 8 `[11,20,85,180]` every 5 s.
3. **Stop capture carries a body and returns the file.** Official
   `STOP_CAPTURE` (5) body is `{1: ExtraMetadata, 2: capture mode}` and the 200
   reply is `{1:{1:"/storage_internal/DCIM/Camera01/VID_….mp4"}}`. OpenInstaCine
   sends an empty body and gets an empty reply (so it diffs the file list).
4. **Record start depends on mode.** `START_CAPTURE` (4) field 1 = **1** normal,
   **4** TimeShift, **9** slow motion. Timelapse uses **cmd 22** `{1:1}` /
   **cmd 23** `{1:1, 2: ExtraMetadata}`. OpenInstaCine always sends cmd 4 `{1:1}`.
5. **Photo returns its URI in a second message.** `TAKE_PICTURE` (3) is
   answered 200 `{}` after 0.3 s, then about 2.1 s later the camera sends
   another code-200 frame with an identifier that matches no request, body
   `{1:{1:"/storage_internal/DCIM/Camera01/IMG_….jpg"}}`.
6. **Contrast, saturation, metering, AF mode and "BC" are written through one
   "whole Pro panel" SET** (details below), not per-option SETs.
7. **Gimbal modes offered: Roll Lock 2, Roll & Tilt Lock 3, FPV 1, FPV-V 4.**
   No "direction lock" (5). OpenInstaCine offers 5 and cannot send 4.
8. **Joystick MOVE always carries field 4 = 4**, even in Roll Lock, so field 4 is
   not the gimbal mode. OpenInstaCine never sends field 4.
9. **New RecordResolution values**: 1:1 3K (3072x3072) 24/25/30/48/50/60 =
   119/120/121/448/447/446, and 9:16 2.7K 30 / 25 = **443 / 444** (not in the
   pinned schema). Neither family is in OpenInstaCine's format table.
10. **Filters are writable** (option 18) with real values, and choosing
    1080p 240 fps forces colour Standard in the same SET.
11. **Not in the official iOS UI on v1.1.15:** audio (mic, wind reduction),
    stabilization / FlowState, Stage Mode, Color Recovery, any quick-EV gesture
    on the preview, gestures settings. Nothing to copy for those.

## Connect and preview start (01-connect)

TCP preface `11 00 00 00 06 00 00 AF FA AF FA AF FA AF FA AF FA`, camera type-5
greeting, one phone type-5 frame, then (all plain, 12-byte header, content type
2, request identifiers 1, 2, 3 ... OR `0x80000000`):

| order | cmd | body / types |
| ---: | --- | --- |
| 1 | 8 GET_OPTIONS | 68, 15, 30, 48, 89, 110, 114, 115, 116, 117, 155, 161, 167, **198** |
| 2 | 7 SET_OPTIONS | types 12, 13, 175: local time (epoch s), timezone offset s (7200), geographic zone string. Nested also carries `1:1 5:48000 42:1 82:3` |
| 3 | 8 | 22, 80, 81, 46, 29, 19, 161, 170 (media offsets, activate time) |
| 4 | 39 CHECK_AUTHORIZATION | `{1:uuid, 2:1, 3:uuid}`; reply `{1:0, 2:2, 3:255, 4:uuid}` |
| 5 | 83 PREPARE_GET_FILE_PACKAGE `{1:1}` | reply **500** `{1:3, 2:"msg execute err."}` (same as v1.0.288) |
| 6 | 15, 8 `[11,20,85,68,97,67,82,176,177,189,203]` | status |
| 7 | 151 / 152, 183, 189, 49/50, 160, **265** (empty), 181, 13 (x several), 242, 172, 38, 53 UPLOAD_GPS | album/cloud/firmware bookkeeping |
| +5 s | 7 SET_OPTIONS type 19 ACTIVATE_TIME | ms epoch |

Capture tab (live): 83 `{1:3}` and `{1:4}`, 8 `[93]`, 8 `[66]`, 10
`[96, 97]`, **118 `{1:5}`**, 8 `[41,40,65,124,132,82,135,169,173]`, 157, 38,
8 `[65,128]`, 8 `[160,93]` (repeated about every 0.1 s while settling), 10
with the full video type list (mode 7), 10 with the photo list (**mode 67**),
10 `[99]`, 17 `{1:1}`, 11 `{path, 2:2}` thumbnail, then:

`START_LIVE_STREAM` (1) body **unchanged**: `{2:1, 4:48000, 7:43, 10:14, 12:1}`
= `10 01 20 80 f7 02 38 2b 50 0e 60 01`, byte-identical to OpenInstaCine's.
Camera then sends 8234 (1280x720 @ 25), 8198, 8298.

Initial camera state (restored at the end, confirmed by the last full video
GET in take 16, identical to take 01): res 48 (4K 25), colour 2 (I-Log),
filter 18 = 0, strength 104 = 2, sharpness 1, contrast 3, saturation 3, EV 0,
WB auto, zoom 1.0, exposure program 0, 24 = 3200, 46 = 1, AF 93 = 3, 91 =
`{1:2, 2:2, 3:3, 4:2}` (Roll Lock, Medium), 100 = 2, 101 = 0.

Leaving preview (back arrow or Album tab): cmd 2 `STOP_LIVE_STREAM`, cmd 11
thumbnails of the newest files, **118 `{1:1}`**.

## Shooting modes (02-modes, 10-mode-panels, 16-mode-records)

Mode switch is **cmd 7** with only the relevant family option in field 1:

| UI | cmd 7 types | nested | FunctionMode used afterwards | 8275 `{1 photo sub, 2 video sub, 3 ?}` |
| --- | --- | --- | --- | --- |
| Video | 41 | 41 omitted (0) | 7 | `{1:100, 2:0, 3:3}` |
| Timelapse | 41 | 41 = 2 | 2 | `{1:100, 2:2, 3:3}` |
| TimeShift | 41 | 41 = 4 | 12 | `{1:100, 2:4, 3:3}` |
| Slow Motion | 41 | 41 = 9 | 21 | `{1:100, 2:9, 3:3}` |
| PureVideo | 41 | 41 = 11 | 27 | `{1:100, 2:11, 3:3}` |
| Photo | 40 | 40 omitted (0) | 6 | `{1:0, 2:100, 3:3}` |
| Pano | 40 | 40 = 8 | 67 | `{1:8, 2:100, 3:1}` |

100 in 8275 means "not this family". Each switch also produces **8334
`{1:53, 2:{53:1.0}, 3:<previous FunctionMode>}`**: zoom resets to 1.0 on every
mode change. Then 8234 with the new preview geometry and 8298. The grid shows
only these seven modes: **no Stage Mode** on this app/firmware.

Record per mode:

| mode | start | stop | 8208 capture state | reply to stop |
| --- | --- | --- | --- | --- |
| Video | cmd 4 `{1:1}` (reply 0.27 s) | cmd 5 `{1:X, 2:1}` | 1 | `{1:{1:VID uri}}` after 0.79 s |
| TimeShift | cmd 4 `{1:4}` | cmd 5 `{1:X, 2:4}` | 13 | `{1:{1:VID uri}}` after 2.1 s |
| Slow Motion | cmd 4 `{1:9}` | cmd 5 `{1:X, 2:9}` | 22 | `{1:{1:VID uri}}` after 0.75 s |
| Timelapse | **cmd 22** `{1:1}` | **cmd 23** `{1:1, 2:X}` | 2 | `{}` (URI found via cmd 11 on the new file) |
| Photo | cmd 3 `{2:X}` | | 4 | `{}` then unsolicited 200 `{1:{1:IMG uri}}` |

`X` (ExtraMetadata-like) is `{13:{6:1}, 19:{}, 21:{}, 23:{}, 26:{}, 44:{}, 71:{}, 160:{}}`;
the photo copy adds field 11 = 24 bytes (three doubles, the phone's GPS fix;
values not reproduced here). During a recording the app sends **cmd 53
UPLOAD_GPS every 1.0 s** (533-byte blob), plus 157 DARK_EIS_STATUS, 15 once,
and 8 `[176,177]` after start and stop. Cmd 15 reply while recording:
`{1:{1:1, 2:0, 10:5}}`.

## Capture Settings page (03, 09)

| UI | wire |
| --- | --- |
| Horizontal Grid on / off | cmd 7 types **128** `ASSISTIVE_GRID` `{128:1}` / omitted |
| Histogram on/off, Show Joystick on/off | nothing (app-local) |
| Storage location SD Card (card full) | nothing |
| Gimbal Follow Speed Slow / Fast / Medium | cmd 9 `[91]` `{91:{2:1}}` / `{2:3}` / `{2:2}`, mode 7, then cmd 10 `[91]` read-back |
| Gimbal Calibration page, Cancel | nothing |
| Top-right link icon | "Disconnect the device?" dialog; Cancel sends nothing |

The Settings page has no audio, stabilization, gesture, timer, Color Recovery
or Stage entries.

## Video resolution / fps / ratio (04, 10)

Every cell is cmd 9 types `[31, 63]` `{31:v}` in the current mode. Normal video
(mode 7):

| ratio / res | fps: value |
| --- | --- |
| 16:9 8K | 30:154, 25:211, 24:210 |
| 16:9 4K | 120:214, 100:220, 60:23, 50:92, 48:258, 30:24, 25:48, 24:49 |
| 16:9 2.7K | 120:242, 100:243, 60:244, 50:245, 48:331, 30:246, 25:247, 24:248 |
| 16:9 1080P | 240:27 (**also sets 35 = 1 Standard**, types `[31,63,35]`), 200:26, 120:28, 100:150, 60:40, 50:81, 48:260, 30:29, 25:52, 24:53 |
| 2.35:1 8K | 30:213, 25:212, 24:219 |
| 2.35:1 4K | 120:433, 100:434, 60:435, 50:436, 48:437, 30:438, 25:439, 24:440 |
| **1:1 3K (3072x3072)** | 60:**446**, 50:**447**, 48:**448**, 30:**121**, 25:**120**, 24:**119** |
| 9:16 4K | 30:124, 25:125, 24:126 |
| 9:16 3K | 60:450, 50:451, 48:452, 30:453, 25:454, 24:455 |
| 9:16 2.7K | 60:441, 30:**443**, 25:**444** (443/444 not in the pinned schema) |
| 9:16 1080P | 60:68, 25:71 |

Switching ratio or resolution lands on that geometry's 25 fps cell (so the
first write after "1:1" is 120, after "9:16" is 125).

Preview (8234) follows the record geometry and rate: 16:9 1280x720, 2.35:1
1280x544, 1:1 720x720, 9:16 720x1280, photo 4:3 1280x960; 24/48 fps records
preview at 24, 25/50/100 at 25, 30/60/120/240 at 29.

Other modes: timelapse (mode 2) 4K30 24, 2.7K30 246, 1080p30 29. TimeShift
(12) 4K30 24, 1080p30 29. Slow motion (21) 4K120 214, 4K100 220, 1080p120 28
(ratio 16:9 or 2.35:1). PureVideo (27) 4K 60/50/48/30/25/24 with 9:16 option;
30:24, 25:48 captured.

## Filters and colour (05, 06)

Filter row (video, Standard colour): cmd 9 `[18]` `{18:v}`, mode 7.

| filter | 18 |
| --- | ---: |
| Standard | omitted (0) |
| Leica Natural | 15 |
| Leica Vivid | 16 |
| Leica Chrome | 36 |
| Positive Film | 34 |
| GR-F | 26 |
| NC Film | 24 |
| Fresh | 38 |
| Cinematic | 37 |
| CC Film | not captured (tile not reached) |

Each write is followed by 8334 `{1:18, 1:104, 2:{18:v, 104:strength}, 3:7}`.
The Low / Medium / High strength buttons did not commit under automation;
tapping them sent the whole-panel SET below with 104 unchanged (2).

Colour (Pro panel colour chip): cmd 9 `[35]` `{35:1}` Standard, `{35:2}` I-Log,
`{35:5}` Dolby Vision. Reply 200 arrives about **1.25 s** later, after the
camera restarts the preview (8234). 8334 reports 104 = 3 for Dolby and 2 for
I-Log / Standard. In I-Log the Pro row drops contrast / saturation / sharpness.
There is **no Color Recovery control** anywhere in the capture UI; with I-Log
selected the only extra is the `capture controlBar reset` button.

## Exposure panel (06, 08, 15)

Normal tab: EV slider only. Drag of one full stop sent cmd 9 `[7]` `{7:20}`
(zigzag 10 = +1.0 EV; +0.3 EV is 6, as before). Reset button sends a burst:
`[21,24,100]` `{21:{1:1}, 24:3200, 100:1}`, whole-panel SET, `[35]` `{35:1}`,
`[6]` `{6:1}`, `[21,24,100]` with 100:2, whole-panel SET, `[7]` omitted,
`[39]` omitted, whole-panel SET. So Reset = Standard colour, Medium sharpness,
EV 0, WB auto, auto exposure, ISO ceiling 3200.

Pro tab, video (mode 7). Exposure writes always list types `[21, 24, 100]`
(packed `15 18 64`), with 24 omitted unless it is the value being set:

| control | nested |
| --- | --- |
| Shutter 1/x | `21:{1:2, 3:seconds}`, `24:3200`, `100:2`. Seen: 1/6400 0.00015625, 1/5000 0.0002, 1/3200, 1/1600, 1/1000, 1/800, 1/640, 1/400, 1/320, 1/200, 1/160, 1/100, 1/60, 1/50, 1/40, **1/25 (longest offered at 25p)** |
| Shutter Auto | `21:{1:1}`, `24:3200`, `100:2` |
| ISO fixed | `21:{1:1, 2:iso}`, `100:2`, no 24. Seen 125, 200, 250, 400, 500, 640, 800, 1000, 1250, 1600, 2500, 6400; far end writes `21:{}` (Auto) |
| ISO "MAX" ceiling | `21:{1:1}`, `24:v`, `100:2`. Seen 400, 1600, 3200, 6400 |
| EV | `[7]` zigzag tenths (+0.3 = 6, 0 omitted) |
| WB | `[39]` kelvin 2000, 2200, 2400 (200 K steps), Auto omitted |
| Sharpness | `[6]` Low omitted (0), Medium 1, High 2 |
| Colour | `[35]` as above |
| Metering Face / Matrix | **no write at selection time** |
| AF-C / AF-S / Product Showcase | picker did not commit under automation; no per-option write |
| BC On / Off, Contrast, Saturation | whole-panel SET (below) |

**Whole-panel SET** (sent on BC / contrast / saturation / strength
selections and inside Reset), mode 7, types in this order:
`31, 63, 21, 24, 100, 7, 39, 72, 18, 104, 6, 46, 53, 91, 35, 93, 101, 3, 4`
(I-Log drops 6, 3, 4). Body example (Standard):
`{3:3, 4:3, 6:1, 20:{}, 21:{1:1}, 24:3200, 31:48, 35:1, 46:1, 53:1.0, 88:1,
91:{4:2}, 93:3, 100:2, 104:2}`. The reply echoes every type. So contrast is
option **3**, saturation **4**, metering **46** (Face = 1), AF mode **93**
(AF-C = 3), and "BC" is most likely **101 `FOVC_SWITCH`** (0 = Off; the only
remaining type in the list; On was not committed, so unconfirmed).

Photo mode (mode 6) Pro shutter writes **both** still and video exposure:
types `[20, 21, 100]` `{20:{1:2, 3:s}, 21:{1:2, 3:s}, 100:2}`. Range seen
1/8000 (0.000125) to **1/30** (end of ruler). Photo EV writes types `[7, 77]`
`{7:v, 77:1}` (PHOTO_HDR_TYPE rides along).

No 1/15 to 1/5 in the official UI for either mode (OpenInstaCine's long
shutters remain beyond what the official app offers).

Quick EV on preview: tap on preview shows a focus box and sends only the AF
trigger (94); a vertical drag at the box sent nothing. Not present in this
app version.

## Zoom and gimbal (07)

| UI | wire |
| --- | --- |
| Preset 2 / 3 / 6 / **15** / 1x | cmd 9 `[53]` `{53: 2.0 / 3.0 / 6.0 / 15.0 / 1.0}` (fixed64 double) |
| Zoom-bar swipe | a stream of `[53]` SETs, one per UI frame, **10 to 25 ms apart**, each acknowledged; two-decimal values (1.04, 1.09 ... 4.14, then 4.10 on settle; down 3.60 ... 2.17, 2.20) |
| Recenter | cmd **238** `{}` then cmd 226 `{1:2, 2:{}}` |
| Flip | cmd 226 `{1:3, 2:{}}` (no 238) |
| Gimbal mode Roll & Tilt / FPV / FPV-V / Roll Lock | cmd 9 `[91]` `{91:{4:3}}` / `{4:1}` / `{4:4}` / `{4:2}` |
| Joystick drag | cmd 226 `{1:1, 2:{…}, 4:4}` every **50 ms**; saturates at zigzag 197/198 (±99); release `{1:1, 2:{}, 4:4}` |
| Tap focus | cmd 9 `[94]` `{94:{1:1, 2:x, 3:y, 4:w, 5:h}}` floats. Box is now **w 0.0869, h 0.1545** in 16:9 video, 0.1159 x 0.1545 in 4:3 photo (square on the sensor). Camera answers with 8317 |
| Long press 1.5 s | a second AF trigger only; no 237 in this take |

Joystick axes followed the phone screen with the camera lying on its side
(drag right put the value in VirtualRC field 1, drag up in field 2): the app
appears to rotate the stick by `CAMERA_POSTURE` (option 93 is polled while the
preview settles). The tap-focus ROI is likewise in the sensor frame, not the
portrait screen frame (tap at screen 0.30, 0.35 gave x 0.27, y 0.62).

8302 PTZ_STATE seen only as `{5:1}` (sleep) and all-zero; unchanged meaning.

## Photo mode panels (08)

| UI | wire (mode 6) |
| --- | --- |
| Ratio / size 1:1, 16:9, 9:16, 3:4, 4:3 | cmd 9 `[40, 63, 30]`: `{30:1, 40:30}`, `{40:29}`, `{30:2, 40:54}`, `{30:6, 40:56}`, `{30:4, 40:34}` (54, 56 not in the pinned PhotoSize table) |
| UHD (4:3) | `[40, 63, 20, 21, 100]` `{20:{1:5}, 21:{1:5}, 40:33, 100:1}` (7040x5288) |
| STD (4:3) | `[40, 63]` `{40:34}` (3520x2644) |
| JPG+RAW / JPG | `[25]` `{25:1}` / omitted |
| Live Photo on / off (confirm sheet) | `[85]` `{85:{2:2}}` / `{85:{2:1}}`; camera 8298 `{1:0, 2:3}` then `{1:0, 2:2}` (on) / `{2:1}` (off) |
| Self-timer 3 s / 5 s / off | `[26]` `{26:3}` / `{26:5}` / omitted |
| Beautify: skin retouch step, smooth 3, Reset | `[90]` `{90:{1:1.0}}`, `{90:{2:3.0}}`, `{90:{}}`; camera 8334 `{89:0, 90:{…}}` |
| Shutter | see exposure section |
| EV | `[7, 77]` |

The photo bank's original still exposure read `20:{1:5}` with `100:1`; the
Auto restore through the Pro ruler wrote `20:{}` / `100:2` and the final STD
tap wrote only 40, so program 5 vs 0 in the photo bank may differ from the
start (both display as Auto). The video bank was verified identical.

## Timelapse / TimeShift panels (10)

| UI | wire |
| --- | --- |
| Timelapse interval 2 s / 1 s | **cmd 18 SET_TIMELAPSE_OPTIONS** `{1:{1:4294967295, 2:2000 / 1000}, 2:1}`; GET 17 `{1:1}` returns `{1:{1:0, 2:1000}}` |
| Timelapse duration 3 min / No limit | cmd 9 `[54]` `MAX_REC_TIME` `{54:180}` / omitted, mode 2 |
| TimeShift duration | same `[54]` panel (not changed) |

## Album, player, download, delete (11 to 14, 17)

| UI | wire |
| --- | --- |
| Album grid | cmd 13 `{1:2|3|6, 3:INT32_MAX, 4:2|3}` pairs, 38, 11 `{path, 2:2}` thumbnails (NV12 via UCD2, not HTTP) |
| Open a clip | 118 `{1:1}` (already set on leaving preview), HTTP `GET /storage_internal/DCIM/Camera01/VID_….mp4` and `LRV_….lrv` with `User-Agent: Lavf/60.3.100` and several `Range:` requests (0-, tail for moov, mid) |
| Player like / album Favorite | nothing on TCP 6666 (app-local, as on v1.0.288) |
| Player LUT / AquaVision toggles | nothing (app-side rendering) |
| Save sheet open | nothing |
| Photo Download | **cmd 173 DOWNLOAD_INFO** `{1:1, 2:1, 4:4}` then `{1:1, 2:1, 3:0.027, 4:1, 5:1}` around an HTTP `GET …/IMG_….jpg` |
| Delete video | cmd 12 with **two** URIs (MP4 and its LRV); reply `{1: LRV uri}` |
| Delete photo | cmd 12 one URI; reply `{}` |
| Multi-select delete of 3 videos | one cmd 12 with 5 URIs (3 MP4 + 2 LRV); reply lists the 2 LRVs |

The delete reply lists URIs that were **not** deleted by that request (the LRV
is removed together with its MP4 first). OpenInstaCine sends only the MP4,
which v1.1.15 accepts and which removes the LRV.

## Me > Device Settings (12)

Camera Storage page: cmd 8 `[20]` and `[176]` (several). Format dialog
opened and **cancelled**: nothing sent. Set Camera Region: list shown, backed
out, nothing sent. Device Information, Accessory Settings, Feature Settings:
app-local. No audio / power / auto-off / language / Color Recovery items are
exposed for Luna in this app version.

## Notifications seen

8195 battery `{1:{1:1, 2:94}}`, 8198 storage `{1:0, 2:2}`, 8208 capture
state (above), 8234 live params, 8248 export status, 8275 submode change,
8298 live-photo status, 8302 PTZ state, 8308 detachable-screen battery,
8317 AF scene change (empty), 8334 photography changed (zoom reset on mode
switch, filter / strength, beauty).

## Gaps in OpenInstaCine, prioritized

Checked against `Adapters/Insta360Protocol` (`LunaProtocol.swift`,
`LunaControl.swift`), `Adapters/Insta360Apple/.../LunaCameraBackend.swift`,
`ios/OpenInstaCine/CameraSessionControls.swift` and `LunaShellMapping.swift`.

1. **Mode-correct record start/stop (breaks recording outside Video).**
   Timelapse must use cmd 22 `{1:1}` / cmd 23 `08 01 12 19 6a 02 30 01 …` (`{1:1, 2:X}`); TimeShift cmd 4
   `08 04`, slow motion cmd 4 `08 09`, both stopped with cmd 5
   `{1:X, 2:<same mode>}`. OpenInstaCine sends cmd 4 `08 01` / empty cmd 5 in
   every mode (untested whether the camera tolerates it in those modes).
2. **Stop-capture body to get the URI back.** Send cmd 5
   `0a 19 6a 02 30 01 9a 01 00 aa 01 00 ba 01 00 d2 01 00 e2 02 00 ba 04 00 82 0a 00 10 01`
   (captured verbatim; last byte is the mode: `01`, `04`, `09`)
   (that is `{1:{13:{6:1},19:{},21:{},23:{},26:{},44:{},71:{},160:{}}, 2:1}`)
   and read the path from reply field 1.1 instead of diffing the file list.
   Photo: accept the unsolicited 200 with `{1:{1:uri}}`.
3. **Keep-alive and poll cadence.** Official: no phone heartbeat, polls every
   10 s (`8 [11,20,85,180]`, `8 [65,128]`, `10 [99]`), no cmd 15 poll. Ours: type
   5 every 2 s, cmd 15 every 1 s. Not proven harmful, but it is 10x the
   official request rate; consider dropping the heartbeat after connect and
   polling at 10 s, relying on 8208 / 8198 / 8195 / 8334 notifications.
4. **Gimbal modes.** Add FPV-V (91 field 4 = 4) as a selectable mode; drop
   or hide "direction lock" (5): the official app never offers it.
5. **Joystick field 4.** Official MOVE / release always add `20 04` (field 4 = 4).
   Ours omit it. Add it (cheap parity) and consider rotating axes by
   `CAMERA_POSTURE` like the official app.
6. **Resolution table.** Add 1:1 3K (119, 120, 121, 448, 447, 446) and 9:16
   2.7K 30 / 25 (443, 444). For 1080p 240 write `[31, 63, 35]` with `35:1`
   (the official app forces Standard colour there).
7. **Photo mode exposure.** In mode 6 write `[20, 21, 100]` with the same
   `ExposureOptions` in 20 and 21. Ours writes only 21, so the still exposure
   likely does not change. Photo EV should include `77:1`.
8. **Filters and look.** Filter (18) values above, contrast (3), saturation (4)
   and sharpness (6: 0/1/2) are writable and in the official UI; OpenInstaCine
   writes none of them. Contrast / saturation / metering (46) / AF mode (93) /
   BC (101?) only move through the whole-panel SET, so implement them by
   sending the full type list with the current values.
9. **Photo-mode options** not implemented: size (40 + 30 pairs above), RAW
   (25), Live Photo (85 `{2:2}` / `{2:1}`), self-timer (26), beauty (89 / 90),
   Pano selection (cmd 7 `[40]` `{40:8}`; our shell maps photo to single only).
10. **Timelapse settings.** cmd 18 interval (ms in 1.2, 1.1 = 0xFFFFFFFF) and
   `[54]` duration are missing.
11. **Grid.** cmd 7 `[128]` if an on-camera grid is wanted (the official toggle
    writes the camera option, not just an overlay).
12. **Zoom.** Official preset chips are 1 / 2 / 3 / 6 / 15 (ours 1 / 2 / 4 / 8 / 15)
    and the zoom bar streams SETs every 10 to 25 ms; our 80 ms throttle is
    fine. Expect zoom to reset to 1.0 on every mode change (8334 field 53).
13. **Tap-focus box size.** Official box is 0.0869 x 0.1545 (16:9) /
    0.1159 x 0.1545 (4:3), ours 0.15 x 0.27. Coordinates are sensor-frame.
14. **Audio, stabilization, Stage Mode, Color Recovery, quick EV:** not in the
    official iOS app on v1.1.15, so no phone-protocol reference exists.
    Colour Recovery stays on the detached-screen RPC path
    ([luna-recovery-toggle-capture-2026-09-17.md](luna-recovery-toggle-capture-2026-09-17.md));
    OpenInstaCine's audio no-ops are consistent with the official app.
