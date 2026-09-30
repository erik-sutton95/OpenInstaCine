---
title: Luna Ultra original media
description: Record and photo commands, file lists and metadata, NV12 thumbnails, HTTP originals and .lrv proxies, delete, battery and storage.
---

Part of the [Luna Ultra reference](../).
Read the overview for firmware, survey scope and evidence levels.

## Recording and photos

| Step | Sent | Reply | Observed on v1.1.15 |
| --- | --- | --- | --- |
| Record start | cmd 4 `08 01` | 200, empty, after about 1 s | Notification 8208 state 1 at +0.25 s |
| Capture status | cmd 15 | 200 | State 1 while recording; `capture_time` counts seconds |
| Record stop | cmd 5 | 200 | 8208 state 0 after about 1.9 s |
| Photo | cmd 3 (photo mode) | 200, empty, after about 3.3 s | 8208 state 4, then 0 |

An empty stop body gets an empty reply. The official app's stop body (a
metadata stub plus the mode in field 2) gets the new file's URI back in reply
field 1.1. For a photo the URI arrives in a separate, unmatched 200 reply
`{1:{1:uri}}`. Otherwise, diff the file list. Per-mode start and stop codes are
in [Shooting modes](../modes/#recording-per-mode). During capture the official
app uploads phone GPS every second (cmd 53); OpenInstaCine does not.

A verified 4K 25p clip was HEVC 3840×2160, 25 fps, recorded with a `.lrv` proxy
beside it. Remaining record time on internal storage read 4630 s at 4K 25p,
which implies a budget of about 86 Mbit/s.

## Files, thumbnails and downloads

| Step | Wire | Notes |
| --- | --- | --- |
| File list | cmd 13, cmd 38 (`GET_FILEINFO_LIST`) | Media type 2, 3 or 6; storage location 2 (internal) or 3 (SD). cmd 38 carries creation time, size, duration, dimensions, fps, gamma, codec |
| Metadata | cmd 11 `GET_FILE_EXTRA`, extra type 1 | The clip's `ExtraMetadata`, including `audio_mode` (field 61) and `first_frame_timestamp` (field 24) |
| Thumbnail | cmd 11, extra type 2 | 40-byte header plus raw **NV12**: 1280×720 for video, 1024×768 for photos, 1920×960 for pano. Convert with BT.709 |
| File access | cmd 118 `{1:1}` | The official app sends it before opening a clip; `{1:5}` when returning to live |
| Download | HTTP `GET http://192.168.42.1<uri>` with `Range` | Camera nginx; the official app also sends cmd 173 around the GET |
| Proxy | `LRV_<stamp>.lrv` beside `VID_<stamp>.mp4` | 720p proxy; the official player fetches it for playback |
| Delete | cmd 12 `DELETE_FILES`, field 1 = URI | Deleting the MP4 removes its `.lrv` too; the reply lists URIs *not* deleted |
| Favorite | none | The official app stores favorites on the phone; cmd 176 is never sent |

Files live under `/storage_internal/DCIM/Camera01/` as `VID_<date>_<time>_<n>.mp4`,
`LRV_….lrv` and `IMG_….jpg`.

:::caution[HTTP needs an open control session]
With no TCP control session, a file GET returns **401**. With a session open (and
cmd 118 state 1 sent) the same Range request returns 206. Whether 118 itself is
strictly required was not isolated.
:::

The official player plays over HTTP; the UCD2 playback opcodes (89 to 99) are
never used. OpenInstaCine downloads the `.lrv` over HTTP, plays the local copy
with the same scopes and assists as live view, and falls back to the original.
Cached clips play offline.

## Battery, storage and remaining time

| Quantity | Source on v1.1.15 | Notes |
| --- | --- | --- |
| Camera battery | cmd 8 option **11** field 2 | Percent. Field 1 (`powerType`) is 1 on power; "0 = on battery" is not yet verified |
| Detachable screen battery | option 180; notification 8308 | Fields 1 and 2, connection field 3 |
| Storage, active location | option **20** fields 2 and 3 | Free and total bytes |
| Storage per location | option **176** (repeated), 177 = active | Card state per location (for example a full SD card reports NOSPACE) |
| Storage change | notification 8198 | No byte counts; re-poll 20 and 176 |
| Remaining record time | photography option **99**, repeated | Seconds per location |
| Battery notifications 8195 / 8196 | never seen | Poll option 11 instead |

The official app polls every 10 s: cmd 8 `[11, 20, 85, 180]`, cmd 8 `[65, 128]`
and cmd 10 `[99]`.
