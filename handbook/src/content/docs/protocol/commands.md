---
title: Command catalog
description: UCD2 MessageCode values and option numbers used on the connection spine, camera control, media and live view.
---

Commands we know for the connection spine, status, camera control, media and
live view. Framing is in [UCD2 frame](../ucd2-frame/). This is not a complete
vendor dictionary: only what OpenInstaCine has confirmed or relies on.
Model-specific values, restrictions and evidence are in the
[Luna Ultra reference](../../devices/luna-ultra/commands/).

Luna does **not** use DUML. A command is a 16-bit `MessageCode` with a protobuf
body. ISO, color, resolution, zoom and most settings chips are not top-level
commands: they are fields of `PhotographyOptions`, read with command **10** and
written with command **9**.

The full enums (447 message codes, 113 photography types, 193 device options, 68
function modes) are in
[`tools/luna_message_codes.json`](https://github.com/erik-sutton95/OpenInstaCine/blob/main/tools/luna_message_codes.json),
[`luna_photography_options.json`](https://github.com/erik-sutton95/OpenInstaCine/blob/main/tools/luna_photography_options.json),
[`luna_device_options.json`](https://github.com/erik-sutton95/OpenInstaCine/blob/main/tools/luna_device_options.json)
and [`luna_function_modes.json`](https://github.com/erik-sutton95/OpenInstaCine/blob/main/tools/luna_function_modes.json).

## Phone commands

| code | name | notes |
|---:|---|---|
| 1 | `START_LIVE_STREAM` | Body `10 01 20 80 f7 02 38 2b 50 0e 60 01` ([live view](../live-view/#enable)) |
| 2 | `STOP_LIVE_STREAM` | |
| 3 | `TAKE_PICTURE` | Empty; field 1 = 5 for a gimbal pano |
| 4 / 5 | `START_CAPTURE` / `STOP_CAPTURE` | Start field 1 = mode (1, 4, 9); stop field 2 = mode |
| 7 / 8 | `SET_OPTIONS` / `GET_OPTIONS` | Device options (below) |
| 9 / 10 | photography SET / GET | Types in field 1; options in field 2 (SET); `FunctionMode` in the last field |
| 11 | `GET_FILE_EXTRA` | Extra type 1 metadata, 2 NV12 thumbnail |
| 12 | `DELETE_FILES` | Field 1 = URI; the reply lists URIs not deleted |
| 13 | `GET_FILE_LIST` | |
| 15 | `GET_CURRENT_CAPTURE_STATUS` | State, sub-mode, elapsed seconds |
| 17 / 18 | timelapse options GET / SET | Interval in ms |
| 22 / 23 | timelapse capture start / stop | |
| 38 | `GET_FILEINFO_LIST` | Per-file metadata |
| 39 | `CHECK_AUTHORIZATION` | Plain; status 0 authorized, 1 needs approval |
| 86 | request authorization | Body `08 01`; the owner answers on the camera |
| 118 | `SET_ACCESS_CAMERA_FILE_STATE` | `{1:5}` shooting view (wakes the gimbal), `{1:1}` media |
| 173 | `DOWNLOAD_INFO` | Sent by the official app around HTTP downloads |
| 214 | `SYNCTIME_ACCURATE` | Clock to the millisecond |
| 226 | `GIMBAL_CONTROL` | Actions 1 MOVE, 2 center, 3 flip, 5 SET_ANGLE, 6 GET_ANGLE |
| 237 / 238 | `OPEN_TRACKING_WITH_RECT` / `CANCEL_TRACKING` | Deep Track |
| 240 / 241 | encryption capabilities / key exchange | BLE, plain |
| 244 / 245 | set / get preset composition | Deep Track framing |

## Photography options (cmd 9 / 10)

| type | name | notes |
|---:|---|---|
| 6 | `SHARPNESS` | 0 Low, 1 Medium, 2 High |
| 7 | `EXPOSURE_BIAS` | sint32 tenths of a stop |
| 13 | `WHITE_BALANCE` | Preset; a GET of 13 clears 39 in the reply |
| 18 | `VIDEO_GAMMA_MODE` | The filter picker, not a gamma curve |
| 20 / 21 | still / video `ExposureOptions` | `program`, `iso`, `shutter_speed` (seconds) |
| 24 | `VIDEO_ISO_TOP_LIMIT` | ISO ceiling; a sentinel value breaks manual ISO |
| 31 | `RECORD_RESOLUTION` | Resolution, fps and aspect in one enum; SET with types `[31, 63]` |
| 33 | `FOV_TYPE` | Needs an explicit 0 |
| 35 | `COLOR_MODE` | 1 Standard, 2 I-Log, 5 Dolby Vision |
| 39 | `WHITE_BALANCE_VALUE` | Kelvin; 0 = Auto |
| 40 | `PHOTO_RESOLUTION` | |
| 46 | `metering_enable` | 0 Matrix, 1 Face Priority |
| 53 | `ZOOM_SCALE` | Double, 1.0 to 15.0 |
| 73 | `COLOR_RECOVERY_SWITCH` | Accepted, never stored |
| 91 | `GIMBAL_OPTIONS` | Field 2 speed, field 4 mode |
| 92 | `GIMBAL_STATUS` | Limit, stall and sleep flags |
| 93 | `AF_MODE_TYPE` | 1 AF-S, 3 AF-C, 6 Product Showcase |
| 94 | `AF_TRIGGER_PARAMS` | Tap focus: type 1 plus a float ROI |
| 99 | remaining record time | Seconds per storage location |
| 104 | `GAMMA_MODE_LEVEL` | Filter strength |

## Device options (cmd 7 / 8)

| option | meaning |
|---:|---|
| 11 | Battery: field 2 percent, field 1 power type |
| 12, 13, 175 | Local time, GMT offset, zone name (SET only; not readable) |
| 15, 30, 48 | Serial, firmware, model |
| 20 | Active storage free and total bytes |
| 36, 37, 43 | Wi-Fi credential read over BLE, encrypted: 36 carries SSID and password |
| 40, 41 | Photo and video sub-mode: the shooting mode |
| 128 | Grid |
| 176, 177 | Storage per location, active location |
| 180 | Detachable screen battery and connection |

## Camera notifications

| code | meaning |
|---:|---|
| 8198 | Storage changed (no byte counts) |
| 8201 | Capture stopped |
| 8208 | Capture status (state, pano progress) |
| 8209 | Authorization result |
| 8215 | Wi-Fi started (BLE, firmware 1.1.15) |
| 8234 | Live stream parameters (1280×720 at 25) |
| 8275 | Shooting mode changed |
| 8293, 8334 | Photography options changed |
| 8302 | Gimbal (PTZ) state flags |
| 8308 | Detachable screen battery |
| 8315 | Deep Track cancelled |
| 8317 | AF scene change (empty) |

## AE and AWB lock

The Luna reports only the exposure and white balance *settings* (ISO 0 and
shutter 0 in Auto, kelvin 0 in AWB), never the applied auto values. There is
nothing to pin, so OpenInstaCine does not offer AE or AWB lock.

## Camera-metered EV

The Luna sends no metered EV. The EV meter reads the decoded picture instead
(median against 18% gray, less the learned auto-exposure placement).
