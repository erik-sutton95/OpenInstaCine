# Luna iOS status

State of the iOS app on branch `feat/openpocketcine-parity`: the OpenPocketCine
shell (commit `c1e8f94`) with a yellow accent and a Luna Ultra backend, camera
firmware v1.1.15. Rows are derived from the code; live results are listed
separately below.

Parity values:

- **Same**: OpenPocketCine UI and behavior unchanged; only the camera's value
  lists differ.
- **Luna-adapted**: same UI, behavior mapped or changed for Luna.
- **Hidden-not-supported**: Luna's phone protocol has no equivalent; the control
  is hidden or refuses with a reason.
- **Not yet**: possible, not implemented.

## Features

| Feature | Parity with OpenPocketCine | Luna implementation (where) |
| --- | --- | --- |
| Connect / pairing | Luna-adapted | BLE scan, owner approval on the camera, encrypted Wi-Fi credential read, then camera AP join and TCP 6666. Bluetooth first whenever the camera advertises (it wakes the AP); saved Wi-Fi is the fallback. Join retries for 60 s, alternating persistent and join-once configs, and continues as soon as the phone is on 192.168.42.x (`LunaCameraBackend.swift`). Camera named "Luna Ultra XXXXXX" (`LunaCameraNames`) |
| Live view | Luna-adapted | 1280x720 HEVC, 25 fps, 2 s keyframe interval, UCD2 subtype 0x20 over TCP. I-Log preview treated as flat log by default (`OperatorPrefs.lunaFlatPreview`, `previewColorMode`) |
| ISO | Same | Auto plus 100, 160, 200, 400, 800, 1600, 3200, 6400 (`LunaShellMapping.isoValues`) |
| Shutter | Same | 1/8000 to 1/5 (`shutterDenoms`); manual exposure sends program, ISO and shutter in one message |
| White balance | Luna-adapted | Auto or kelvin 2000 to 10000; no tint (sent as 0). Camera applies kelvin 3.5 to 3.9 s after the SET, pinned for 5 s |
| EV | Same | Exposure bias in thirds |
| Format drum | Same | Table of every RecordResolution fw 1.1.15 stored: 8K, 8K 2.35:1, 4K, 4K 2.35:1, 2.7K, 1080p, and 9:16 4K/3K/2.7K/1080 (`videoFormatValues`) |
| Color modes incl. I-Log | Luna-adapted | Standard, I-Log, Dolby Vision (`colorModes`). Vivid and HDR are refused by the camera and not offered |
| Shooting modes | Luna-adapted | Video, Timelapse, TimeShift, Slow Motion, PureVideo, Photo (shared drum with Luna labels); Live Photo has no Luna mode. Pano reads back as Photo |
| Zoom chip + pinch | Luna-adapted | Chips 1x, 2x, 4x, 8x, 15x; digital zoom to 15.0 (fw 1.1.15 max) |
| Gimbal stick | Luna-adapted | Streams Luna gimbal stick commands |
| Gimbal mode | Luna-adapted | Follow = roll lock, Tilt locked = roll and tilt lock, FPV, Direction lock = lock |
| Gimbal speed | Luna-adapted | Slow, Default = medium, Fast |
| Gimbal recenter / flip | Same | Luna recenter and flip requests |
| Gimbal Level (double tap) | Hidden-not-supported | Refuses with "no level data": Luna reports no gimbal attitude |
| Programmed moves (A/B/C) | Hidden-not-supported | Controls show the reason ("Luna does not report gimbal position"); waypoints cannot be set |
| Tap focus | Luna-adapted | ROI 0.15 x 0.27 of the preview centred on the tap (official app geometry) |
| Deep Track | Luna-adapted | Drag or tap a face box opens Luna tracking (cmd 237) with the drawn rectangle; cancel supported |
| Record + timer | Luna-adapted | Start/stop and photo; lamp waits for camera capture status. REC timer is elapsed time from capture status (no timecode) |
| Lock | Same | Interface lock blocks every control |
| DISP clean view | Same | DISP 1/2, clean mode, chrome editor |
| LUT incl. Insta360 I-Log look | Luna-adapted | Camera LUTs: Auto and the official Insta360 I-Log to Rec.709 cube (`Luna_I-Log_to_Rec709_BT1886_s33_v2.cube`); Creative and Custom unchanged |
| Peaking | Same | |
| False color | Same | |
| Zebra | Same | |
| Waveform | Same | |
| RGB parade | Same | |
| Histogram | Same | |
| Vectorscope | Same | |
| Traffic lights | Same | |
| ND / EV meters, de-squeeze | Same | |
| Level assist overlay | Luna-adapted | Tool present; shows "No level data" (no camera attitude) |
| Guides | Same | |
| Grid | Same | |
| Crosshair | Same | |
| Mirror | Same | |
| Settings tabs | Same | Link, Sharing, View Assist, Controls, Display, Storage, System; head-tracking section hidden by capability |
| Media grid / list | Luna-adapted | Shared library; list from the camera, thumbnails are camera NV12 frames converted with BT.709 (`LunaThumbnailImage.swift`) |
| Playback (.lrv proxy) | Luna-adapted | Shared player downloads the 720p `.lrv` sidecar over HTTP from 192.168.42.1 (needs an open control session) and plays the local copy; the original is the fallback. Not a progressive stream: AVPlayer never gets a camera URL. Cached clips play offline |
| Download | Same | Original over HTTP into the per-camera cache |
| Delete | Same | Luna delete command; removes the MP4 and its LRV |
| Favorites | Luna-adapted | Stored on the phone; Luna has no favorite write |
| Disconnect / reconnect | Luna-adapted | Reconnect uses the BLE-first path above |
| Recovery card | Same | Shared bounded session recovery after a drop |
| Audio (setting, meters) | Hidden-not-supported | `supportsAudio` false: AUDIO tile, AUDIO assist and meter overlay hidden |
| AF mode (AF-S/AF-C) | Hidden-not-supported | `supportsFocusMode` false; Luna video AF is continuous |
| Aperture | Hidden-not-supported | `supportsAperture` false; fixed iris |
| Head tracking | Hidden-not-supported | Needs gimbal attitude; capability false |
| Multiview | Hidden-not-supported | Entry removed from the camera list (`SavedCamerasView.swift`); stages DJI bodies over RTMP |
| Wi-Fi / Hotspot setups | Hidden-not-supported | `canAddSetup: false`; Luna only connects over its own AP |
| Color Recovery | Not yet | Screen protocol code exists (`LunaScreenRecovery.swift`, [luna-color-recovery.md](luna-color-recovery.md)); not exposed in the UI |
| Android | Not yet | `Apps/Android` is the pre-rebase shell, not synced to this one |

## Verified live (2026-09-25)

<!-- LIVE-RESULTS -->

## Known issues

1. **Physical iPhone: `NEHotspotConfiguration` apply fails with internal error
   8** for this app even while the camera AP is up (the camera SSID is also
   saved by the Insta360 app). Workaround: join the camera Wi-Fi in Settings;
   the app detects the 192.168.42.x subnet and continues. To test the cause:
   forget "Luna Ultra XBQFN7.OSC" in Settings > Wi-Fi, then retry in the app.
2. **XCUITest on the phone** needs Face ID or the passcode to re-enable
   automation mode, so official-app capture on fw 1.1.15 is still pending
   (`just luna-official-xc`).
3. **Android** is not synced to the new shell.
4. **Color Recovery** (screen protocol) is not exposed in the UI.

## Next steps

- Resolve the hotspot error 8 (test with the Insta360-saved network forgotten).
- Capture official-app traffic on fw 1.1.15 once automation is re-enabled.
- Verify `.lrv` playback, delete and favorites live on the phone.
- Sync `Apps/Android` to the new shell.
- Decide how to expose Color Recovery.

Sources: `ios/OpenInstaCine/CameraSession*.swift`, `CameraMedia.swift` (Luna
extension), `LunaShellMapping.swift`, `OsmoMonitorPresentation.swift`,
`OsmoCameraPageAdapter.swift`, `Adapters/Insta360Apple`,
[fw 1.1.15 verification](../research/luna-fw-1.1.15-verification.md).
