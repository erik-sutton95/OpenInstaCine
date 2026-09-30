---
title: Media
description: File list and metadata over UCD2, NV12 thumbnails, HTTP file fetch with an open session, .lrv proxies and delete.
---

Once the phone is on the camera [network](../wifi/), clips and stills are
fetched over HTTP. Listing, metadata, thumbnails and delete stay on
[UCD2](../commands/).

## File fetch

```text
GET http://192.168.42.1<uri>
```

| | |
| --- | --- |
| Paths | `/storage_internal/DCIM/Camera01/VID_<stamp>.mp4`, `LRV_<stamp>.lrv`, `IMG_<stamp>.jpg` |
| Proxy | `LRV_<stamp>.lrv` is the 720p proxy for `VID_<stamp>.mp4` |
| Ranges | Supported (206); the official player reads the head, the `moov` at the tail, then the middle |
| Session | **Required.** With no TCP control session open the server returns 401 |

The official app sends cmd 118 `{1:1}` before opening a clip and cmd 173
`DOWNLOAD_INFO` around a download. OpenInstaCine keeps the control session open
and downloads the `.lrv` for playback, then the original on request, into a
per-camera cache. On iOS, AVPlayer never gets a camera URL: it plays the local
copy.

Do not put camera paths or filenames that include secrets into issues.

## List

| code | meaning | notes |
| --- | --- | --- |
| 13 | `GET_FILE_LIST` | Media type 2, 3 or 6; limit `INT32_MAX`; location 2 internal or 3 SD |
| 38 | `GET_FILEINFO_LIST` | Per file: creation time, size, duration, dimensions, fps, gamma, sub-media type, codec |
| 11, extra type 1 | `GET_FILE_EXTRA` metadata | The clip's `ExtraMetadata` (same shape as cmd 38) |
| 11, extra type 2 | thumbnail | Content type 1 (raw): a 40-byte header plus NV12. 1280×720 video, 1024×768 photo, 1920×960 pano |

The official app fetches no HTTP thumbnail. Render the NV12 frame with BT.709
limited range (`LunaThumbnailImage.swift` on iOS; a JPEG conversion on Android).

## Delete and star

| code | meaning | notes |
| --- | --- | --- |
| 12 | `DELETE_FILES` | Field 1 = the full URI. The camera removes the MP4's `.lrv` too. The reply lists URIs that were **not** deleted |
| 176 | `SET_FAVORITE` | In the schema, never sent. The official app keeps favorites on the phone, and so does OpenInstaCine |

UCD2 playback commands (89 to 99: enter, play, pause, seek) are never used; the
official player plays over HTTP.
