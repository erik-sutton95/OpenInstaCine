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
| ISO | Luna-adapted | Auto plus 100, 160, 200, 400, 800, 1600, 3200, 6400 (`LunaShellMapping.isoValues`). No auto ISO ceiling or native-ISO hop (`supportsIsoLimit` false): the Auto tab shows a read-only Auto stop, holding the tile in Auto offers the manual ISO drum |
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
| Programmed moves (A/B/C) | Hidden-not-supported | Motion Control opens with waypoints, loop and Start dimmed and the reason ("Luna does not report gimbal position"); `supportsProgrammedMoves` false |
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
| Audio (setting, meters) | Hidden-not-supported | `supportsAudio` false: AUDIO tile, live AUDIO assist and meter overlay hidden (playback audio meters stay) |
| Timecode | Hidden-not-supported | `supportsTimecode` false: status-bar timecode and its DISP toggle hidden; the REC chip carries elapsed time |
| AF mode (AF-S/AF-C) | Hidden-not-supported | `supportsFocusMode` false; Luna video AF is continuous |
| Aperture | Hidden-not-supported | `supportsAperture` false; fixed iris |
| Head tracking | Hidden-not-supported | Needs gimbal attitude; capability false |
| Multiview | Hidden-not-supported | Entry removed from the camera list (`SavedCamerasView.swift`); stages DJI bodies over RTMP |
| Wi-Fi / Hotspot setups | Hidden-not-supported | `canAddSetup: false`; Luna only connects over its own AP |
| Color Recovery | Not yet | Screen protocol code exists (`LunaScreenRecovery.swift`, [luna-color-recovery.md](luna-color-recovery.md)); not exposed in the UI |
| Android | Not yet | `Apps/Android` is the pre-rebase shell, not synced to this one |

## Verified live (2026-09-25)

Run from the iOS Simulator (DEBUG build) connected to the real camera over the
Mac's Wi-Fi (camera AP 192.168.42.x), fw v1.1.15. Driven with the DEBUG remote
(`tools/oic_remote.py`) and the opt-in XCUITest
`OpenInstaCineUITests/LunaLiveWalkthroughTests` (real taps; screenshots in
`.local/live-walkthrough/`, not committed). The room was dark, so picture
content was checked against a recorded clip rather than by eye. Every camera
setting changed was restored.

| Area | Result | How |
| --- | --- | --- |
| Connect, live feed | Pass | ~24 fps; after the Simulator fixes the feed is the real camera (matches a recorded clip) |
| ISO / shutter / EV / WB / exposure mode | Pass | Remote set and readback, sheets opened; manual 400 and 1/100, EV +0.7, 4300K |
| Format / color / shooting mode | Pass | 1080p 30p and back, Normal and back to I-Log, Photo and back |
| Photo mode readouts | Fixed, pass | Was "M" with an empty shutter and a `0xDF` format |
| Zoom chip + pinch | Pass | 1x to 2x chip, pinch to 6x, back to 1x |
| Gimbal mode / speed / recenter / flip / stick | Pass (command accepted) | Remote; gimbal sheet tabs Mode, Speed, Ramp, Double-tap by UI |
| Programmed moves | Fixed, pass | Reason shown; waypoints were live-looking no-ops, now dimmed |
| Tap focus | Pass | UI tap moves the focus box; control accepted |
| Deep Track | Partial | Drag sends Track (camera "ok"); no lock on a uniform dark scene, box clears as designed |
| Record with confirmation, REC timer | Pass | UI confirm popover; REC 00:02 with red frame; 5 s clip on the camera |
| Lock, DISP clean view | Pass | UI taps; locked tiles ignore taps; long-press unlock |
| Assists (all 16) | Pass | Toggled each by remote, screenshots; LEVEL shows "No level data" |
| LUT Auto and I-Log look | Pass | Options sheet: Insta360 tab, "Applying official I-Log to Rec.709"; LUT off shows the flat I-Log preview |
| Settings, 7 tabs | Pass | Link, Sharing, View Assist, Controls, Display, Storage, System |
| Media grid / list / favorites | Pass | Favorites tab shows the starred clip; 8K clip labelled 4K (fixed) |
| Playback from the camera | Pass | Proxy plays while the original caches, then "Original · on phone" |
| Download / delete own clip | Pass | Download by remote; deleted the clip recorded in this run from the player |
| Disconnect / reconnect | Pass | Camera list, then reconnect to live in ~15 s |
| Link loss and recovery card | Pass | Mac Wi-Fi off: "Reconnecting" pill, then "Connection keeps dropping" card at ~45 s; Retry connection restores live |
| Landscape | Pass | Live, ISO sheet, format sheet, gimbal sheet, settings |

### Physical iPhone (07:40)

iPhone 16 Pro Max, iOS 27.0, Luna fw 1.1.15: BLE consent (already approved) → camera Wi-Fi → TCP
6666 → live at 25 fps, battery 95 %. ISO 800 → Auto, zoom 4× → 1×, gimbal stick and recenter,
Standard ↔ I-Log, record start/stop with the timer, media list, delete of the test clip: all pass
and read back from the camera.

## Known issues

1. **Physical iPhone hotspot join (transient).** Overnight, `NEHotspotConfiguration` apply returned
   internal error 8 on every attempt while the camera AP was up. At 07:39 the same build joined on the
   first attempt and the phone went live (see below), so it was environmental. The app retries for
   up to 120 s, drops the stale config between attempts, and after the third attempt tells the
   operator to join the camera network in Settings, then continues on its own once the subnet appears.
2. **XCUITest on the phone** needs Face ID or the passcode to re-enable
   automation mode, so official-app capture on fw 1.1.15 is still pending
   (`just luna-official-xc`).
3. **Android** is not synced to the new shell.
4. **Color Recovery** (screen protocol) is not exposed in the UI.
5. **Simulator crash, not reproduced on device**: `HevcDecoder.publishWatchPreview`
   crashed wrapping the VT buffer in a `CIImage` (bad colour attachments). It now
   runs only with a paired watch; the root cause in the Simulator decoder is open.
6. **Unit tests with Osmo assumptions still fail** (pre-existing):
   `FormatCeilingNoteTests`, `MediaCacheSchedulingTests` (proxy streaming stubs),
   `CapturePreviewTrafficTests` (expects peer commands) and the `.focus` case of
   `CapturePanelRenderComparisonTests`.

## Next steps

- Watch for a repeat of the transient hotspot error 8 and capture `nehelper` logs if it returns.
- Capture official-app traffic on fw 1.1.15 once automation is re-enabled.
- Repeat the Simulator walkthrough on the phone (hotspot join, thermal, real-light picture, Deep Track lock).
- Port or drop the Osmo-assumption unit tests listed above.
- Android: map Luna status and photography options into the shared chrome (see Android below).
- Decide how to expose Color Recovery.

Sources: `ios/OpenInstaCine/CameraSession*.swift`, `CameraMedia.swift` (Luna
extension), `LunaShellMapping.swift`, `OsmoMonitorPresentation.swift`,
`OsmoCameraPageAdapter.swift`, `Adapters/Insta360Apple`,
[fw 1.1.15 verification](../research/luna-fw-1.1.15-verification.md).

## Unit test deltas vs OpenPocketCine

Removed as Osmo-only (listed in `OSMO_ONLY` in `scripts/sync-openpocketcine.sh`): session internals
(DUML handshake, recovery lifecycle, dial reconciliation), multiview, per-format zoom ceiling notes,
and DJI dual-storage media retries. Two inherited UI tests still fail by design:
`CapturePanelRenderComparisonTests` (Luna hides the AF mode panel) and `CapturePreviewTrafficTests`
(Luna controls only change state while the camera link is live).

## Android

Updated 2026-09-25. `Apps/Android` now carries the current OpenPocketCine Android shell
(upstream `c1e8f94`, the same commit as the iOS sync) with OpenInstaCine identity, the yellow
`0xFFCF00` accent and the Luna adapter driving it. Emulator only: there is no physical Android
device, so nothing below is hardware-verified on Android.

### Done

- `:monitor` is upstream `Apps/Android/app/src` as a library; `:monitor-ui` is upstream verbatim
  except the accent, which is a brand-assigned `MonitorPalette.accent`.
  `:app` stays the thin launcher (`com.opencapture.openinstacine`) that installs the brand, the
  I-Log camera look and `LunaBackend` through `MonitorConfiguration`.
- `session/PocketCameraSession.kt` is replaced (like iOS `CameraSession.swift`) by a Luna session
  with the same public surface over `core-api` `CameraBackend`. The upstream top-level helpers in
  that file are kept verbatim so tests and callers still compile.
- Controls through a new optional `core-api` `CameraControls`, implemented by `LunaBackend`:
  gimbal rate stick (iOS shaping, 20 Hz), recenter, flip, zoom 1..15 (chips 1, 2, 4, 8, 15),
  tap focus (0.15 x 0.27 ROI) and Deep Track open/cancel. Request bytes are ports of
  `Adapters/Insta360Protocol` and are pinned to the Swift fixtures in `LunaControlTest`.
- Gating matches iOS: no AF mode, no aperture, no multiview (button hidden), no programmed moves,
  no audio controls. The Android shell has no Wi-Fi/Hotspot setup choice or head tracking to hide.
- I-Log to Rec.709 sits in the camera LUT tab (`MonitorTransfer.ILOG`, camera looks in the DJI
  category so upstream tab logic and tests hold). DJI LUT assets are not bundled.
- Brand copy: legal bodies, pairing steps, wordmarks, links (`openinstacine.app`, GitHub repo)
  mirror the iOS text. Launcher and splash logo are the yellow monitor mark.
- `./gradlew :app:assembleDebug testDebugUnitTest lintDebug` passes: 989 monitor, 121
  monitor-ui and 13 luna-adapter JVM tests. Test edits vs upstream: the source-contract test reads
  `monitor/` instead of `app/`, and legal/link assertions name OpenInstaCine and Insta360.
- Emulator (`OpenInstaCine_API35`, landscape): pairing, live chrome in local replay (zoom chip,
  Deep Track button, gimbal stick, lock, DISP, LUT/assist rail) and Operator Setup render with the
  yellow accent. Shots in `.local/android-shots/` for comparison with `.local/parity-shots/oic/`.

### Remains

- Status mapping: iOS fills ISO, shutter, WB, EV, storage, battery and REC from Luna settings and
  device status; Android shows dashes. The Kotlin adapter does not read photography options or
  device status yet, and the zoom/focus requests always use function mode 7 (normal video).
- Capture and exposure controls (record, shutter, ISO, shutter speed, EV, WB, color profile,
  format), gimbal mode/speed, camera media and delivery: iOS has them, Android shows
  "not available on the Luna Ultra yet".
- Live decode on the emulator: the goldfish HEVC decoder returned a solid frame for the Luna replay
  in this run (the 2026-09-11 review got a moving picture); needs a real device.
- Real Luna over Android BLE, Wi-Fi and TCP, reconnect/background recovery and all controls:
  untested on hardware.
- There is no Android equivalent of `scripts/sync-openpocketcine.sh`; the resync was manual
  (upstream `app/src` into `monitor/src`, then the brand, I-Log and session seams re-applied).
