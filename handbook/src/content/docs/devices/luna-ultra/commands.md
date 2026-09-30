---
title: Luna Ultra command comparison
description: Index of Luna Ultra command families and the differences from the DJI Osmo protocol.
---

Use this index with the [survey scope and evidence levels](../) and the
[shared command catalog](../../../protocol/commands/). Follow each evidence
link for payloads, replies, readbacks and remaining limits. A schema name does
not establish that the Luna implements the command.

## Captured command families

Command codes are UCD2 `MessageCode` values; option numbers are fields of
`PhotographyOptions` (cmd 9 SET, cmd 10 GET) or device `Options` (cmd 7 SET,
cmd 8 GET).

| Family | Commands | Luna Ultra evidence |
| --- | --- | --- |
| Session and approval | 8, 39, 86, 240, 241 | [BLE pairing](../../../protocol/ble/); encrypted credential read over BLE, plain authorization check on TCP |
| Live view | 1, 2, 118 | [Live view](../../../protocol/live-view/); 118 `{1:5}` wakes the gimbal before every live start |
| Shooting mode | 7 options 40, 41 | [Mode switch and banks](../modes/#shooting-modes) |
| Record resolution | 9 types 31, 63 | [Accepted resolution list](../modes/#formats) |
| Record, photo | 3, 4, 5, 22, 23 | [Per-mode record and stop](../media/#recording-and-photos) |
| Exposure and EV | 9 types 7, 20, 21, 24, 77, 100 | [ISO, shutter and EV](../settings/#exposure) |
| White balance | 9 type 39 | [Kelvin and auto](../settings/#white-balance); applies 3.5 to 3.9 s later |
| Color, sharpness, filter | 9 types 6, 18, 35, 104 | [Color and look](../settings/#color-sharpness-and-filters) |
| AF mode, metering, tap focus | 9 types 46, 93, 94 | [Focus and metering](../settings/#focus-and-metering) |
| Zoom | 9 type 53 | [Zoom](../controls/#zoom); 1.0 to 15.0 |
| Gimbal mode and speed | 9 type 91 | [Gimbal options](../controls/#gimbal-mode-and-speed) |
| Gimbal motion | 226 actions 1, 2, 3, 5, 6 | [Stick, recenter, flip, absolute angle](../controls/#gimbal-motion) |
| Deep Track | 237, 238, 244, 245, notice 8315, media subtype `0x85` | [Deep Track](../controls/#deep-track) |
| Clock and timecode | 7 options 12, 13, 175; 214 | [Timecode](../settings/#timecode) |
| Status polls | 8 options 11, 20, 85, 176, 177, 180; 10 type 99; 15 | [Battery, storage and remaining time](../media/#battery-storage-and-remaining-time) |
| Media | 11, 12, 13, 38, 118, 173, HTTP 80 | [File list, thumbnails, download and delete](../media/#files-thumbnails-and-downloads) |
| Audio | 7 options 108, 109; 251 | [No phone-protocol audio control](../settings/#audio) |

## Differences to preserve

| Area | Luna boundary |
| --- | --- |
| Framing | UCD2 frames with protobuf bodies, not DUML. Success is message code **200**, rejection **500**. See [UCD2 frame](../../../protocol/ucd2-frame/). |
| Transport | TCP `192.168.42.1:6666` for control and live view, HTTP port 80 for files. No UDP datalink. |
| Settings | ISO, color, resolution and zoom are fields of one options message, not separate opcodes. A 200 reply that echoes the type can still be a wrong bank. |
| Mode banks | On v1.1.15 the `FunctionMode` field is ignored: GET and SET act on the bank of the current shooting mode. |
| Omitted zeros | Proto3 omits zero values, so an absent field is not proof of Off. Some SETs need an explicit zero (FOV 33, AF 93). |
| Read quirk | A GET that lists type 13 after type 39 makes the camera report white balance Auto. Read 39 alone or before 13. |
| Timed gimbal moves | No DJI-style timed angle move; firmware 1.1.15 has an absolute SET/GET angle instead. |
| Favorites | No camera write. The official app keeps favorites on the phone; cmd 176 is never sent. |

The [coverage and implementation reference](../coverage/) records what still
needs qualification.
