# Luna Ultra command catalog

Updated: 2026-09-25 (firmware v1.1.15 section added). This is the Insta360-app equivalent of OpenPocketCine’s
DUML command handbook. Luna does **not** use DUML. Phone control is UCD2 frames
carrying a 16-bit `MessageCode` plus protobuf. ISO, colour, resolution, zoom and
most “settings chips” are not top-level opcodes; they are fields of
`PhotographyOptions`, read with command **10** and written with command **9**,
always scoped by a `FunctionMode`.

Evidence labels match [protocol-notes.md](../protocol-notes.md): **Observed**
means this Luna Ultra v1.0.288 plus Insta360 iOS 2.33.0; **Source-backed** means
the pinned community protobuf; **External measurement** means Ripwords’ Luna
desktop calibration on v1.0.238 / v1.0.283.

Primary sources:

- Community schema `iliakonnov/insta360-nas`
  `b78dddb9cd9bc2cf632871646c6f5af238e582d4` (`insta360_messages.proto`)
- Official-app reconnect take
  `captures/20260910T215020587215Z-luna-reconnect-01/`
  ([report](luna-reconnect-2026-09-11.md))
- Ripwords feature map / protocol gap (firmware 1.0.238 / 1.0.283)
- Local number tables: `tools/luna_message_codes.json`,
  `tools/luna_photography_options.json`, `tools/luna_device_options.json`,
  `tools/luna_function_modes.json`

## Framing (not DUML)

| Layer | Luna Ultra | Pocket / DUML |
| --- | --- | --- |
| Frame magic | `UCD2` (`55 43 44 32`) | `55` DUML |
| Control socket | TCP `192.168.42.1:6666` | UDP `192.168.2.1:9004` |
| Body | protobuf | packed command payload |
| Command identity | 16-bit little-endian `MessageCode` | `cmdSet` / `cmdId` |
| Success | same 16-bit field = **200** | ACK flags / status byte |
| Rejection | same field = **500** | nonzero status |
| Notify | codes ≥ 8192 | unsolicited `cmdSet/cmdId` |
| Request bit | message-id `OR 0x80000000` on **both** request and reply | DUML `isResponse` |

Do not treat code 200 as `PHONE_COMMAND_CTRL_BATCH_FAVORITE`. That name exists
in the enum, but camera replies use 200 as **RESPONSE_OK**. Distinguish by TCP
direction (camera `192.168.42.1` vs phone) and by correlating the 30-bit
message id.

Live video is UCD2 type **01**, subtype **0x20** HEVC, not a DUML `pktType 0x02`
enable.

## Official-app commands actually sent

Reconnect + first live picture, Insta360 2.33.0 on this Luna v1.0.288. Phone
stream only (requests). Replies were 200 except command 83, which got **500**.

| code | name | count | what the take did |
| ---: | --- | ---: | --- |
| 1 | `START_LIVE_STREAM` | 1 | starts type-01 HEVC; body below |
| 7 | `SET_OPTIONS` | 2 | phone local time / timezone / activate time |
| 8 | `GET_OPTIONS` | 26 | device identity, storage, posture, offsets |
| 10 | `GET_PHOTOGRAPHY_OPTIONS` | 18 | per-mode ISO/colour/res/zoom/gimbal reads |
| 13 | `GET_FILE_LIST` | 16 | media index |
| 15 | `GET_CURRENT_CAPTURE_STATUS` | 2 | |
| 17 | `GET_TIMELAPSE_OPTIONS` | 2 | |
| 38 | `GET_FILEINFO_LIST` | 5 | |
| 39 | `CHECK_AUTHORIZATION` | 1 | status 0, already paired |
| 83 | `PREPARE_GET_FILE_PACKAGE` | 3 | **response 500** |
| 118 | `SET_ACCESS_CAMERA_FILE_STATE` | 1 | |
| 151 | `PREPARE_GET_FILE_SYNC_PACKAGE` | 1 | |
| 152 | `GET_FILE_PACKAGE_SYNC_FINISH` | 1 | |
| 157 | `DARK_EIS_STATUS` | 2 | |
| 160 | `GET_CLOUD_STORAGE_UPLOAD_STATUS` | 1 | |
| 172 | `GET_DOWNLOAD_FILE_LIST` | 1 | |
| 217 | `SET_CLOUD_TAB_SHOW` | 3 | |
| 225 | `SET_CLOUD_PROMPT_INTERVAL` | 1 | |
| 242 | `GET_FIRMWARE_VERSIONS` | 1 | |
| 265 | unnamed | 1 | empty body; not in the pinned enum |

Notifications seen from the camera in the same window: **8198** storage,
**8234** live-stream params (1280×720 @ 25), **8248** data-export status,
**8298** live-photo switch.

The reconnect take had no record/SET/gimbal. Those are in the
2026-09-16 official-app survey below.

### Live start (command 1)

Observed protobuf:

```text
10 01 20 80 f7 02 38 2b 50 0e 60 01
```

| field | value | schema name | this take |
| ---: | ---: | --- | --- |
| 2 | 1 | `enableVideo` | video on |
| 4 | 48000 | `audioSampleRate` | |
| 7 | 43 | `resolution` | enum `RES_1280_720P30`; **measured** HEVC 1280×720 @ **25 fps**, BT.709 |
| 10 | 14 | `resolution1` | enum `RES_960_480P30`; second stream not decoded here |
| 12 | 1 | `enableRotate` | |

Stop is command **2**. Not sent in the reconnect window.

### Function modes the official app probes

Command 10 is **mode-scoped**. On connect the app reads several modes, not just
the one on screen:

| mode | schema name | used as |
| ---: | --- | --- |
| 2 | `FUNCTION_MODE_MOBILE_TIMELAPSE` | photography GET |
| 6 | `FUNCTION_MODE_NORMAL_IMAGE` | photo settings |
| 7 | `FUNCTION_MODE_NORMAL_VIDEO` | video settings (also selfie-mirror GET) |
| 12 | `FUNCTION_MODE_TIMESHIFT` | |
| 21 | `FUNCTION_MODE_SLOWMOTION_VIDEO` | |
| 27 | `FUNCTION_MODE_PURE_VIDEO` | PureVideo |
| 67 | `FUNCTION_MODE_GIMBAL_PANO_IMAGE` | gimbal pano stills |

A SET that omits the mode, or uses the wrong one, writes a different bank.
Ripwords hit this: settings are stored per function mode.

## Photography options (the settings “opcodes”)

Read: command **10**, field 1 = option type numbers, field 2 = `FunctionMode`.
Write: command **9**, field 1 = types being set, field 2 = nested
`PhotographyOptions`, field 3 = mode.
Reply to SET lists success types in field 1; transport 200 is not enough.

Proto3 omits default zeros/false. An absent field is **not** proof of Off.

### Values this camera returned (official app GET)

Firmware v1.0.288, reconnect take. Colour mode **2** on every probed mode.
Ripwords re-measured colour as Standard=1, i-Log=2, Dolby Vision=5 on v1.0.238.
Schema names 2 `COLOR_MODE_LOG`. Treat 2 as this body’s current colour, not as
a universal “i-Log opcode” until a controlled Standard ↔ i-Log SET is captured
on this firmware.

| type | name | video-family value | photo-family value | notes |
| ---: | --- | --- | --- | --- |
| 6 | `SHARPNESS` | 1 | (not in photo GET reply) | colour writes rewrite this (external) |
| 7 | `EXPOSURE_BIAS` | 0 | 0 | EV; external: ±4 EV in 1/3 stops |
| 13 | `WHITE_BALANCE` | requested | | Auto=0 in schema |
| 18 | `VIDEO_GAMMA_MODE` | 0 | | Filter picker, not a gamma curve (external). 0 = `STANDARD` |
| 20 | `STILL_EXPOSURE_OPTIONS` | | program 0, iso 0, shutter 0.0 | Auto |
| 21 | `VIDEO_EXPOSURE_OPTIONS` | program 0, iso 0, shutter 0.0 | | **This** is ISO/shutter, not legacy `exposure_manual` (external) |
| 24 | `VIDEO_ISO_TOP_LIMIT` | `4294964096` | same | sentinel-sized; do not display as ISO |
| 31 | `RECORD_RESOLUTION` | **48** = `RES_3840_2160P25` | | 4K 25p record; preview is a different stream |
| 33 | `FOV_TYPE` | 0 `FOV_WIDE` | | |
| 35 | `COLOR_MODE` | **2** | **2** | see colour paragraph |
| 39 | `WHITE_BALANCE_VALUE` | 0 | 0 | kelvin when custom |
| 40 | `PHOTO_RESOLUTION` | | 29 `Size_3840_2160` | |
| 43 | `FLOWSTATE_LEVEL` | requested | | EIS level |
| 53 | `ZOOM_SCALE` | **1.0** | **1.0** | 1×–12× (external). Dedicated commands 170/171 also exist |
| 72 | `I_LOG_SWITCH` | **0** | not in photo reply | separate from `COLOR_MODE` |
| 73 | `COLOR_RECOVERY_SWITCH` | requested, **omitted in reply** | | proto3 default-false; not proven Off |
| 91 | `GIMBAL_OPTIONS` | `(2,2,3,2)` | same | nested; not the stick |
| 92 | `GIMBAL_STATUS` | all-zero flags | | limits/stall/sleep |
| 93 | `AF_MODE_TYPE` | 3 `AF_MODE_CONTINUOUS_VIDEO` | 3 | |
| 98 | `GIMBAL_PANO_TYPE` | | 1 `GIMBAL_PANO_TYPE_360` | pano mode only |
| 104 | `GAMMA_MODE_LEVEL` | 3 | | filter strength (external field 104) |

Video-family GETs also asked for contrast, saturation, FOV, dark EIS, beauty,
macro, P3, Action View, initial perspective, and PTZ FOV. Several of those were
omitted in the reply (unsupported or default).

Exposure nested message (`ExposureOptions`):

| field | name | Auto in this take |
| ---: | --- | --- |
| 1 | `program` | 0 `AUTO` (1 ISO_PRIORITY, 2 SHUTTER_PRIORITY, 3 MANUAL) |
| 2 | `iso` | 0 |
| 3 | `shutter_speed` | 0.0 seconds |

### How to SET one control

Example shape only, from the schema plus standard protobuf encoding — **not** a
captured official-app SET on this body:

| action | command | mode | types | nested field |
| --- | ---: | ---: | --- | --- |
| Read video colour + ISO | 10 | 7 | 35, 21 | |
| Set colour | 9 | 7 | 35 | field 35 varint |
| Set ISO/shutter | 9 | 7 | 21 | field 21 `ExposureOptions` |
| Set zoom | 9 | 7 | 53 | field 53 double, **or** command 170 |
| Set filter | 9 | 7 | 18 | field 18 `GammaMode` |
| Set filter strength | 9 | 7 | 104 | field 104 |

Confirm on the camera screen. A 200 reply that echoes the type can still be a
wrong bank or a stale enum.

## Dedicated commands for live controls

These are **not** photography options. Ripwords parked gimbal/track/focus after
looking only in the options namespace. Numbers below are from the pinned
schema; **none of the SET/stick forms were in the official-app reconnect take**.

| code | name | payload (schema) | role |
| ---: | --- | --- | --- |
| 3 | `TAKE_PICTURE` | | stills shutter |
| 4 / 5 / 6 | `START/STOP/CANCEL_CAPTURE` | | record |
| 9 / 10 | photography SET/GET | mode + option mask | chips |
| 12 | `DELETE_FILES` | | |
| 13 | `GET_FILE_LIST` | observed | gallery |
| 89 / 90 | `ENTER/EXIT_PLAYBACK` | | on-camera playback |
| 93–99 | playback play/stop/pause/seek/next/prev/del | | |
| 105 | `IFRAME_REQUEST` | | IDR analogue |
| 122 / 123 | `START/STOP_PRE_REC` | | |
| 164 | `PAUSE_RECORDING` | | |
| 170 / 171 | `SET/GET_ZOOM` | | alongside option 53 |
| 176 | `SET_FAVORITE` | | star |
| 226 | `GIMBAL_CONTROL` | `GimbalAction` + `VirtualRC` up_down/left_right | stick / center / flip / cali |
| 230 / 231 | `OPEN/CLOSE_TRACKING` | | Deep Track |
| 237 | `OPEN_TRACKING_WITH_RECT` | rect | tap to track |
| 238 | `CANCEL_TRACKING` | | |
| 243 | `SWITCH_TRACK_TARGET` | | |
| 246 | `START_TRACK_AUTO_DETECT` | | |

`GimbalControl` schema:

| field | name |
| ---: | --- |
| 1 | `GimbalAction`: 1 MOVE, 2 BACK_CENTER, 3 FLIP, 4 CALI |
| 2 | `VirtualRC.up_down`, `VirtualRC.left_right` (sint32) |
| 3 | `GimbalCaliType` |
| 4 | `cali_id` |

Unsolicited **8302** `CAMERA_NOTIFICATION_PTZ_STATE` is the measured gimbal
limit notify (external, 18-byte 9-varint; fields 2/3 drop 1→0 at pan ends).

## Device options (command 7/8)

Not photography. Official-app GET types in the reconnect take included serial
(15), firmware (30), model (48), storage (20, 176), detachable-screen battery
(180), camera posture (93), video encode (66), selfie (68), media offsets,
and unnamed **11**, **198**, **203** (beyond the pinned `OPTIONS_NUM = 195`).

SET 7 in that take wrote local time (12), timezone (13), geographic timezone
(175), and activate time (19). Do not replay those timestamps.

## Colour, ISO, resolution cheat sheet

What the Insta360 app is talking to, given current evidence:

| App chip | Wire | Verified on this v1.0.288? |
| --- | --- | --- |
| Live view | cmd 1 / 2 | **Observed** start and **stop** (cmd 2 on album) |
| Record | cmd **4 / 5** | **Observed** start field 1=1, stop ~18 s later |
| Photo | cmd **3** | **Observed** `TAKE_PICTURE` |
| ISO | cmd 9 field **21** | **Observed** SET iso=160, program=1 ISO_PRIORITY |
| Shutter | field **21** `program=2` + double seconds | **Observed** 1/50 = 0.02; wheel also wrote 1/5000…1/40 |
| EV | field **7** | **Observed** SET 6 = UI +0.3 EV |
| Colour | field **35** | **Observed** SET 1 Standard, **2 I-Log**, **5 Dolby Vision** |
| I-Log extra switch | field 72 | GET 0; colour chip is field 35 |
| Colour Recovery | field 73 | GET requested, reply omitted |
| Sharpness | field **6** | **Observed** SET 2 = High (Medium GET 1) |
| Filter | field 18 `gamma_mode` | GET 0 |
| Res / fps / ratio | field **31** | **Observed** 52=1080p25, 48=4K25, 24=4K30, 454=9:16 3K25 |
| Zoom | field **53** double | **Observed** 1.0 / 2.0 / 3.0 / **6.0**; not cmd 170 |
| WB kelvin | field **39** | **Observed** SET 2000 and 2400 |
| Shooting mode | cmd **7** option **41** | **Observed** 2/4/9/11 + FunctionMode 2/12/21/27 |
| Gimbal stick | cmd **226** action **1** + `VirtualRC` | **Observed** MOVE; sint32 zigzag ~±99; empty RC = release |
| Gimbal recenter | cmd **226** action **2** | **Observed** |
| Gimbal flip | cmd **226** action **3** | **Observed** |
| Gimbal follow speed | field 91 nested field 2 | **Observed** SET 3 Fast |
| Gimbal mode | field 91 nested field **4** | **Observed** FPV=1, Roll Lock=2, Roll&Tilt=3, **FPV-V=4** |
| Tap focus | field **94** | **Observed** START + ROI floats |
| Deep Track | cmd **237** | **Observed** `OPEN_TRACKING_WITH_RECT` ROI; cmd **238** with recenter |
| Pano 360 | cmd 7 option **40**=8 + cmd **3** | **Observed** 19-frame sweep + stitch |
| Media list | cmd 13 | observed |
| Clip open / download | cmd 11 + HTTP :80 | **Observed** `GET /storage_internal/DCIM/Camera01/VID_….mp4` and `.lrv` |
| Delete | cmd **12** | **Observed** field 1 = full URI of the jpg |
| Star | cmd 176 schema | **Not emitted** by iOS Favorite/like on camera Wi-Fi |
| Filter | field 18 `gamma_mode` | GET on connect; **no live-UI SET** (colour is field 35) |

## Official-app SETs captured 2026-09-16

Take: `captures/20260916T101132Z-luna-official-control-survey/` (RVI `rvi0`,
Insta360 2.33.0, Luna v1.0.288, XC driver on es_iphone16). Phone→camera TCP
6666 only: 593 UCD2 requests, including **12 photography SETs**, **1 gimbal
control**, **take picture**, **start/stop capture**.

Every photography SET used **function_mode 7** (`NORMAL_VIDEO`). The app’s SET
body often serializes extra nested defaults (empty exposure messages,
`RECORD_RESOLUTION=1`, `MACROLENS_SWITCH=1`). **Apply only the types in field 1.**

| UTC tap | UI | Wire | Nested value |
| --- | --- | --- | --- |
| 10:37:37 | Gimbal Follow Speed **Fast** | cmd **9**, types **91** | `GIMBAL_OPTIONS` field 2 = **3** (GET Medium was 2) |
| 10:39:38 | ISO wheel → **160** | cmd **9**, types **21, 100** | `video_exposure.program=1` (ISO_PRIORITY), `iso=160`; `IQ_3A_MODE=2` |
| 10:40:13 | EV **+0.3** | cmd **9**, types **7** | `EXPOSURE_BIAS=6` (UI +0.3 ⇒ 20 units/EV) |
| 10:40:50 | **Standard Color** | cmd **9**, types **35** | `COLOR_MODE=1` (was GET 2 / I-Log) |
| 10:41:30 | zoom **2×** | cmd **9**, types **53** | `ZOOM_SCALE` double **2.0** |
| 10:41:34 | zoom **3×** | cmd **9**, types **53** | `ZOOM_SCALE` double **3.0** |
| 10:41:42 | Recenter | cmd **226** | `GimbalAction=2` `BACK_CENTER`; also cmd **238** `CANCEL_TRACKING` |
| 10:42:20 | Photo shutter | cmd **3** | `TAKE_PICTURE` |
| 10:42:30 | Record start | cmd **4** | field 1 = **1** `Capture_MODE_NORMAL` |
| 10:42:52 | Record stop (~18 s clip) | cmd **5** | `STOP_CAPTURE` |
| 10:43:57 | **1080P** | cmd **9**, types **31, 63** | `RECORD_RESOLUTION=52` `RES_1920_1080P25` |
| 10:44:08 | **4K** | cmd **9**, types **31, 63** | `RECORD_RESOLUTION=48` `RES_3840_2160P25` |
| 10:44:19 | **30FPS** | cmd **9**, types **31, 63** | `RECORD_RESOLUTION=24` `RES_3840_2160P30` |
| 10:44:30 | **25FPS** | cmd **9**, types **31, 63** | `RECORD_RESOLUTION=48` |
| 10:44:37 | **9:16** | cmd **9**, types **31, 63** | `RECORD_RESOLUTION=454` `RES_1728_3072P25` (HUD 3K) |
| 10:44:44 | **16:9** | cmd **9**, types **31, 63** | `RECORD_RESOLUTION=211` `RES_7680_4320P25` |

Dolby Vision and I-Log restore taps did **not** produce a SET (chip stayed
Standard Color). Colour Recovery was not on the exposure bar.

Ratio / resolution / fps are one enum (`record_resolution`), not three opcodes.
The unlabeled live-view chip at ~ (0.64, 0.09) opens that picker.

## Official-app SETs captured 2026-09-16 remaining take

Take: `captures/20260916T105725Z-luna-official-remaining/`. Same phone/camera.
XC died after opening the 6K player; album HTTP still completed.

| UTC | UI | Wire |
| --- | --- | --- |
| 10:58:36 | WB **2000K** | cmd 9 types **39** `WHITE_BALANCE_VALUE=2000` |
| 10:59:27 | WB **2400K** | cmd 9 types **39** `WHITE_BALANCE_VALUE=2400` |
| 11:01:05 | Sharpness **High** | cmd 9 types **6** `SHARPNESS=2` (Medium GET was 1) |
| 11:02:32 | zoom **6×** | cmd 9 types **53** `ZOOM_SCALE=6.0` |
| 11:02:36 | zoom **2×** | `ZOOM_SCALE=2.0` |
| 11:02:42 | zoom **1×** | `ZOOM_SCALE=1.0` (label becomes `1` after 2×/3×/6×) |
| 11:05:01 / :05 | tap-to-focus | cmd 9 types **94** `AF_TRIGGER_PARAMS` type=1 START, ROI floats (first: x=0.42 y=0.054 w=0.15 h=0.27) |
| 11:05:12 | Flip | cmd **226** `GimbalAction=3` |
| 11:05:19 | Recenter | cmd **226** action **2** + cmd **238** cancel tracking |
| 11:05:33 | Gimbal **FPV** | cmd 9 types **91** `GIMBAL_OPTIONS` field **4=1** |
| 11:05:51 | **Roll Lock** | field **4=2** |
| 11:06:00 | **Roll & Tilt Lock** | field **4=3** (HUD button became `capture stabilizer pitch lock`) |
| 11:06:30 | **Timelapse** | cmd **7** option **41** `VIDEO_SUB_MODE=2`; photo GETs use `FunctionMode=2` |
| 11:06:35 | **TimeShift** | option 41 = **4**; FunctionMode **12** |
| 11:06:39 | **Slow Motion** | option 41 = **9**; FunctionMode **21** |
| 11:06:43 | **PureVideo** | option 41 = **11**; FunctionMode **27** |
| 11:07:22 | **Video** restore | option 41 omitted (NORMAL=0); FunctionMode **7** |
| 11:07:25 | leave live / open clip | cmd **2** `STOP_LIVE_STREAM`; cmd **11** `GET_FILE_EXTRA` path `/storage_internal/DCIM/Camera01/VID_…` and `IMG_…`; cmd **118** access-state 1 |
| 11:07:25+ | player fetch | HTTP `GET /storage_internal/DCIM/Camera01/VID_20260916_124229_002.mp4` and `.lrv` preview |

`VideoSubMode`: 0 Normal, 2 Timelapse, 4 TimeShift, 9 Slow Motion, 11 Pure. Shooting-mode switch is **device option 41**, not photography option 31.

AF-S / Product Showcase / Matrix metering / Dolby / Colour Recovery produced **no** photography SET in this take. Virtual-joystick drags produced **no** `GimbalAction=1` MOVE (Show Joystick row tap did not expose a stick). Cmd **170** still unused; zoom is option 53 at 1/2/3/6.

## Official-app SETs captured 2026-09-16 remaining-2

Take: `captures/20260916T112725Z-luna-official-remaining-2/`. These controls are
Wi-Fi UCD2 / HTTP; the nRF BLE sniffer is not required for them.

| UTC | UI | Wire |
| --- | --- | --- |
| 11:30:00 | player open | cmd **118** access-state **5** |
| 11:30:52–11:31:04 | shutter wheel | cmd 9 types **21, 24, 100**; `program=2` SHUTTER_PRIORITY; double seconds 1/5000…1/40 |
| 11:31:09 | shutter **1/50** | `shutter_speed=0.02` |
| 11:32:26 | **I-Log** | cmd 9 types **35** `COLOR_MODE=2` |
| 11:33:33 | gimbal **FPV-V** | cmd 9 types **91** field **4=4** |
| 11:34:15 | long-press preview **Deep Track** | cmd **237** `OPEN_TRACKING_WITH_RECT` ROI floats |
| 11:34:26 | **Pano** | cmd **7** option **40** `PHOTO_SUB_MODE=8` |
| 11:34:49 | 360 pano shutter | cmd **3** field 1=5 (19-frame sweep + stitch) |
| 11:35:18 | **Video** restore | cmd **7** option **41** omitted (NORMAL) |

Player like showed “Added to Favorites” with no cmd 176 on TCP. Dolby was listed and not written. Colour Recovery is not on the iOS exposure bar. Center-preview drags sent no MOVE; the stick is the bottom-right pad.

## Official-app stick MOVE 2026-09-16

Take: `captures/20260916T114216Z-luna-official-joystick/` (48 cmd **226** frames).
On-screen pad: `Other` {{246,522}×194} with inner knob {{311,587}×64} (`sticker_optimize_circle`). Settings row **Show Joystick** (cell {{20,299}×400×60}); switch is not an AX Switch.

cmd **226** while dragging:

| field | value | meaning |
| ---: | --- | --- |
| 1 | **1** | `GIMBAL_ACTION_MOVE` |
| 2 | `VirtualRC` | empty = released/center |
| 2.1 | `up_down` sint32 zigzag | **up +, down −**, saturates ~**±99** |
| 2.2 | `left_right` sint32 zigzag | **right +, left −**, saturates ~**±99** |
| 4 | **4** | present throughout this FPV-V take (same as mode 4); do not treat as proven `cali_id` |

Examples: right-end `left_right` zigzag 99 (`10 c6 01`); left-end 197 → −99 (`10 c5 01`); up `up_down` 198 → 99 (`08 c6 01`); down 197 → −99 (`08 c5 01`). Diagonal sets both fields. Release is action 1 with **empty** VirtualRC, not action 2.

Osmo analogue is DUML `0x04/0x01` u16 axes centered at 1024. Luna is protobuf sint32 ~±99, 0 omitted.

## Still uncaptured vs Osmo handbook

- Colour Recovery (field 73) — **not in the iOS Insta360 capture UI**; mapped on the detached screen as `iq_ilog_lut.enable` (see luna-recovery-toggle-capture)
- Filter (`gamma_mode` 18) SET — not in the iOS live chip row (only Standard / I-Log / Dolby as `COLOR_MODE`)
- UCD2 PLAY/PAUSE/SEEK (89–99): iOS player used HTTP GET of the MP4, not those opcodes
- `SET_FAVORITE` cmd **176** — album Favorite / player like did not emit it on camera Wi-Fi

## Official-app delete / favorite / filter 2026-09-16

Take: `captures/20260916T120504Z-luna-official-filter-star-delete/`.

**Delete (observed):** cmd **12** `DELETE_FILES`, protobuf field 1 = URI  
`/storage_internal/DCIM/Camera01/IMG_20260916_133503_003.jpg`  
(the 360 pano still this survey created). UI: player trash → “Confirm deletion?” → **Delete**. Album count 3 → 1.

**Star:** player like and album Choose → All → **Favorite** produced **no** cmd 176 / 200 request on TCP 6666. Favorite is app-local (or cloud), not a camera UCD2 write in this iOS app.

**Filter:** live Pro/Normal chip rows end at colour (Standard / I-Log / Dolby). No Vivid/Film/Vintage tile. Photo `capture controlBar setting` is Timer 3s/5s, not filters. 360 editor **Filter** is in-app edit, not photography option 18. The official app still **GETs** option 18 on connect; it did not **SET** it in any of these takes.

## Official-app Dolby + playback 2026-09-16

Take: `captures/20260916T115046Z-luna-official-dolby-playback/`.

| UTC | UI | Wire |
| --- | --- | --- |
| 11:51:12 | 4K | cmd 9 types 31,63 `RECORD_RESOLUTION=48` |
| 11:51:52–11:52:01 | shutter wheel → Auto | cmd 9 types 21,100 (program Auto / IQ_3A) |
| 11:52:35 | **Dolby Vision** chip selected | cmd 9 types **35** `COLOR_MODE=5` |
| 11:55:22 | leave live / open album media | cmd **2** `STOP_LIVE_STREAM` |
| 11:55:23 | player access | cmd **118** state 1; cmd **11** `GET_FILE_EXTRA`; HTTP `GET /storage_internal/DCIM/Camera01/VID_….mp4` |

Dolby required Auto shutter (not 1/50) and a visible picker tap on the Dolby tile ({{289,763}×52×62} in that layout). Colour Recovery never appeared as an iOS label in capture settings, gimbal settings, or the I-Log/Dolby picker. Playback transport on this app is **HTTP file fetch**, not cmd 93–99.

XC driver: `just luna-official-xc 00008140-001A09A43453001C`. Live preview
requires skipping XCTest quiescence. Mark taps in `events.tsv`.

## Color Recovery and motion control (vs OpenPocketCine)

These are the two controls OpenPocketCine exposes that Luna does **not**
mirror 1:1 from the Insta360 iOS capture UI.

### Color Recovery on/off

| Path | Evidence | Use |
| --- | --- | --- |
| Detached-screen RPC `iq_ilog_lut.enable` + `lut_type` | **Verified write**: On=`true`/`kILogStandard`, Off=`false`/`kStandard`; camera reply 0; preview pixels change. [toggle capture](luna-recovery-toggle-capture-2026-09-11.md) | Working switch. Lab client: `tools/luna_screen_live.py` (experimental KCP). Requires I-Log (`iq_color_mode.color_mode` = `kIlog`). |
| Phone photography option **73** `COLOR_RECOVERY_SWITCH` via cmd 9/10 | Official app **GETs** 73 on connect; reply **omits** the field. **Two independent labs on v1.0.288:** Mac TCP `captures/20260916T124158018635Z-luna-set73/` and phone TCP over RVI `captures/20260916T125431Z-luna-set73-phone/` (Mac stayed on LAN). Cmd 9 type 73 is **accepted** (200, echo `08 49`). GET 10 still omits field 73 after SET 1 and SET 0. Color mode 35 readback works on the same sessions. | **Not a working Recovery toggle.** Do not ship SET 73 as On/Off. |

**Official iOS app (2026-09-16 RVI take `captures/20260916T130950Z-luna-color-recovery-official/`):**
with I-Log selected, the only bottom-left control is accessibility-labeled `capture controlBar reset`. Tapping it **SET color_mode 35 back to 1 (Standard)** — it is a settings reset, not Recovery. No cmd 9 type 73 appears in the whole take. Insta360’s own I-Log tutorial splits two features: **Preview LUT / Color Recovery on the camera screen** (swipe in from the right → Pro → I-Log, bottom-left toggle) versus **restore colors in the phone app** (album editor LUT on a recorded I-Log file).

The Insta360 **phone** app does not SET live Recovery. SET 73 is a no-op on v1.0.288. OpenInstaCine should drive the **screen RPC** (`iq_ilog_lut.enable`) for the live toggle. Phone-side lab `--set73-lab` exists so the Mac can stay on internet.

**2026-09-16 detached-screen radio take** `captures/20260916T133643Z-luna-recovery-toggle-screen/`: operator toggled Color Recovery ~10 times. Monitor-mode capture on **channel 9** (this body is no longer on channel 3) recorded camera beacons and 52,602 data frames. **EAPOL was absent** — the screen was already associated — so the take cannot be decrypted.

**2026-09-16 home ethernet take** `captures/20260916T192525Z-luna-recovery-toggle-home/`: camera AP was on **5 GHz channel 36**. Capture recorded 1,489 camera beacons and 145 broadcast data frames, **zero unicast stations, zero EAPOL**. Powering the detached display off also powers the camera off. Color Recovery toggles in this take did not traverse Wi-Fi. Next recapture: screen physically unclipped with live picture (unicast data present), then toggle without powering the display off.

**2026-09-16 Mac TCP live vs Recovery** `captures/20260916T210803Z-luna-phone-vs-recovery/`: Mac joined camera AP on en0, ethernet stayed default (`en19`). TCP live in I-Log (`color_mode=2`; option 73 omitted). 61 decoded HEVC frames, 1280×720, ~190s. Mean luma **65.37–65.61** (range 0.24), no contrast jumps. Two unique I-frame hashes. Phone-protocol live did not show a Recovery-like encode change in this window. Operator “Done” was not received before stop; if toggles occurred in-window they did not move this feed.

**2026-09-16 sequential ON then OFF** (`captures/20260916T212333Z-luna-phone-recovery-ON/`, `…T212510Z-…-OFF/`): cannot toggle Recovery while Mac live is up — screen shows “App connected, will automatically close the preview to save power.” Operator set Recovery on the detached screen, then Mac grabbed 25s. **ON** 5 frames YAVG **67.83**, YDIF **0.17**. **OFF** 23 frames YAVG **84.87**, YDIF **0.088**. ΔY **−17**, ON has ~2× local contrast and more chroma. Same direction as screen-feed Recovery On/Off. Not locked-exposure; still strong evidence the I-Log LUT is **upstream of the phone live encoder**, not screen-only. OpenInstaCine live is not a hidden pre-LUT tap while Recovery is On.

### Gimbal joystick and aimed directions

OpenPocketCine motion control is DUML `0x04/0x14` (yaw/pitch i16 tenths + duration) closed on `0x04/0x05` attitude ~10 Hz, plus analog stick `0x04/0x01` (u16 center 1024).

| Pocket | Luna (v1.0.288, official app) |
| --- | --- |
| Stick `0x04/0x01` | **cmd 226 action 1** `VirtualRC` sint32 zigzag **±99**; empty RC = release. Captured. Encoders: `LunaProtocol.gimbalMove` / `tools/luna_wire.gimbal_control`. |
| Recenter `FE 08` | **cmd 226 action 2**. Captured. |
| Rotate 180 `FE 09` | **cmd 226 action 3** flip. Captured. |
| Timed angle `0x04/0x14` | **No such command** in `GimbalControl` (only MOVE / CENTER / FLIP / CALI). |
| Attitude `0x04/0x05` | Notify **8302** is pan-**limit** flags, not pose; it did **not** fire during 48 MOVE frames. Media `0x30` is IMU (u64 + 6 doubles), not fused yaw/pitch. Device option 93 `CAMERA_POSTURE` is enum `1`, not angles. |

Aimed A→B like Pocket’s motion editor therefore cannot be a single Luna opcode today. The workable analogue is: **recenter or snapshot, drive `gimbalMove` at ±99, stop with empty RC**, then later close the loop if a pose source is found (8302 fields beyond limits, or a fused IMU). Digital `RENDER_VLP_EULER` (option 74) is a 360-render pose, not the mechanical gimbal; the official app did not GET 74 in video mode.

Do not invent a timed-angle packet. Stick + recenter + flip are the verified mechanical controls.

## Firmware v1.1.15: official app capture 2026-09-25

Full per-UI-action record, takes and decoder usage:
[luna-official-fw1115-capture.md](luna-official-fw1115-capture.md)
(`tools/luna_pcap_decode.py`). Everything above still holds on v1.1.15 except
where this table says otherwise.

| Area | v1.1.15 official wire | New or changed vs the sections above |
| --- | --- | --- |
| Keep-alive | one phone type-5 frame after the preface, then none; camera type 5 at 1 Hz | new |
| Polls | every 10 s: cmd 8 `[11,20,85,180]`, cmd 8 `[65,128]`, cmd 10 `[99]`; cmd 15 only around capture | new |
| Live start | cmd 1 `10 01 20 80 f7 02 38 2b 50 0e 60 01` | unchanged |
| Mode switch | cmd 7 `[41]` (video family) or `[40]` (photo family); camera 8275, 8334 `{53:1.0}` (zoom reset), 8234 | 8334 zoom reset new |
| Record | cmd 4 `{1:1}` normal, `{1:4}` TimeShift, `{1:9}` slow motion; timelapse cmd **22** `{1:1}` / **23** `{1:1, 2:X}` | per-mode field 1, cmds 22/23 |
| Stop | cmd 5 `{1:X, 2:mode}`, reply `{1:{1:uri}}` | reply carries the file |
| Photo | cmd 3 `{2:X+GPS}`; reply `{}` then an unmatched-id 200 `{1:{1:uri}}` | new |
| During capture | cmd 53 UPLOAD_GPS every 1 s | new |
| Filter | cmd 9 `[18]`: Leica Natural 15, Leica Vivid 16, Leica Chrome 36, Positive Film 34, GR-F 26, NC Film 24, Fresh 38, Cinematic 37, Standard 0 | first live filter SETs |
| Sharpness | `[6]` Low 0 (omitted), Medium 1, High 2 | Low value |
| Contrast / saturation / metering / AF / BC | one whole-panel SET, types `31,63,21,24,100,7,39,72,18,104,6,46,53,91,35,93,101,3,4` | contrast 3, saturation 4, BC likely 101 |
| Exposure | always types `[21,24,100]`; Auto shutter `21:{1:1}`; ISO ceiling via 24 (400/1600/3200/6400) | ceiling values |
| Photo exposure | `[20,21,100]` same ExposureOptions in both; photo EV `[7,77]` with `77:1` | new |
| Resolution | 1:1 3K 119/120/121/448/447/446; 9:16 2.7K 30/25 = 443/444; 1080p240 also writes `35:1` | new values |
| Photo size | `[40,63,30]`: 1:1 `30:1 40:30`, 16:9 `40:29`, 9:16 `30:2 40:54`, 3:4 `30:6 40:56`, 4:3 `30:4 40:34`; UHD `40:33` | new |
| Photo extras | RAW `[25]`, Live Photo `[85]` `{2:2}`/`{2:1}`, timer `[26]` 3/5, beauty `[90]` | new |
| Timelapse | interval cmd **18** `{1:{1:0xFFFFFFFF, 2:ms}, 2:1}`; duration `[54]` seconds | new |
| Grid | cmd 7 `[128]` `{128:1}` | new |
| Gimbal modes | 91 field 4: Roll Lock 2, Roll & Tilt 3, FPV 1, FPV-V 4 (no 5 offered) | FPV-V confirmed as UI option |
| Joystick | cmd 226 `{1:1, 2:RC, 4:4}` at 50 ms, field 4 = 4 in every gimbal mode | field 4 is not the mode |
| Zoom | presets 1/2/3/6/**15**; bar streams `[53]` every 10 to 25 ms | 15x preset |
| Tap focus | `[94]` box 0.0869 x 0.1545 (16:9), 0.1159 x 0.1545 (4:3) | smaller box |
| Delete | cmd 12 lists MP4 and LRV; reply lists URIs not deleted | reply semantics |
| Download | cmd 173 DOWNLOAD_INFO around the HTTP GET | new |
| Absent from the iOS UI | audio, stabilization / FlowState, Stage Mode, Color Recovery, quick EV on preview | |

## Number index

Full enums are in `tools/luna_*.json` (447 `MessageCode` values, 113 photography
types, 193 device options, 68 function modes). The reconnect take already proves
the official iOS app uses this namespace on Luna Ultra v1.0.288, including
codes **217, 225, 242, 265** that older 164-code extracts lacked.
