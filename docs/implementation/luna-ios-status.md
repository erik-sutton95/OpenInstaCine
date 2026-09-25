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

### Official-app parity pass (fw 1.1.15, 10:47 on the iPhone)

From [the official app capture](../research/luna-official-fw1115-capture.md). Each item was run on
the physical iPhone against the camera; test files were deleted, and the camera was restored
(Video, 4K 25p, I-Log, Roll Lock, 1x, photo bank auto exposure program 5 / 100 = 1).

| Change | Result on the camera |
| --- | --- |
| Record per mode: cmd 4 field 1 (1 Video/PureVideo, 4 TimeShift, 9 Slow Motion), Timelapse cmd 22/23, official stop body | All five modes recorded a file and stopped |
| Photo mode shutter writes still (20) and video (21) exposure | GET read back 1/1000 in both |
| Photo EV adds type 77 = 1 | +0.7 stored, restored to 0 |
| Gimbal: shell's fourth mode is FPV-V (91 field 4 = 4); names Roll Lock / Roll & Tilt / FPV / FPV-V | Stored 4, restored Roll Lock |
| Stick moves and releases carry field 4 = 4 | Sent without error; the camera faced a blank surface, so movement was not visible for either encoding |
| Zoom presets 1 / 2 / 3 / 6 / 15 | 3x and 6x read back |
| Tap focus box 0.0869 x 0.1545 (0.1159 wide in photo) | Unit-tested only |
| Formats: 1:1 3K (119/120/121/446/447/448), 9:16 2.7K 30/25 (443/444); 1080p 240 also writes Standard colour | 3K 1:1 25p, 2.7K 9:16 30p and 1080p 240 (colour went to Standard) stored |

Not done, because the shared shell has no control for them: filters (18), sharpness,
contrast/saturation/metering/AF via the whole-panel SET, photo size/RAW/Live Photo/self-timer/beauty,
timelapse interval (cmd 18) and duration (54). The official app does not poll as often (no
heartbeat, 10 s status) as we do (2 s heartbeat, 1 s capture status); left as is because the
record timer needs it and nothing showed a cost.

A reinstall resets iOS's approval to join the camera network, so the first connect after an
install shows the system "Join Wi-Fi Network" alert and waits for the tap.

## Known issues

1. **Physical iPhone hotspot join (transient).** Overnight, `NEHotspotConfiguration` apply returned
   internal error 8 on every attempt while the camera AP was up. At 07:39 the same build joined on the
   first attempt and the phone went live (see below), so it was environmental. The app retries for
   up to 120 s, drops the stale config between attempts, and after the third attempt tells the
   operator to join the camera network in Settings, then continues on its own once the subnet appears.
2. **XCUITest on the phone** needs Face ID or the passcode to re-enable
   automation mode, so official-app capture on fw 1.1.15 is still pending
   (`just luna-official-xc`).
3. **Android** is synced to the new shell but only partly wired (see Android below).
4. **Color Recovery** (screen protocol) is not exposed in the UI.
5. **Simulator crash, not reproduced on device**: `HevcDecoder.publishWatchPreview`
   crashed wrapping the VT buffer in a `CIImage` (bad colour attachments). It now
   runs only with a paired watch; the root cause in the Simulator decoder is open.

## Next steps

- Watch for a repeat of the transient hotspot error 8 and capture `nehelper` logs if it returns.
- Repeat the Simulator walkthrough on the phone (hotspot join, thermal, real-light picture, Deep Track lock).
- Android: map Luna status and photography options into the shared chrome (see Android below).
- Decide how to expose Color Recovery.

Sources: `ios/OpenInstaCine/CameraSession*.swift`, `CameraMedia.swift` (Luna
extension), `LunaShellMapping.swift`, `OsmoMonitorPresentation.swift`,
`OsmoCameraPageAdapter.swift`, `Adapters/Insta360Apple`,
[fw 1.1.15 verification](../research/luna-fw-1.1.15-verification.md).

## Unit test deltas vs OpenPocketCine

Removed as Osmo-only (listed in `OSMO_ONLY` in `scripts/sync-openpocketcine.sh`): session internals
(DUML handshake, recovery lifecycle, dial reconciliation), multiview, per-format zoom ceiling notes,
DJI dual-storage media retries, and `CapturePreviewTrafficTests` (counts frames on the DJI datalink
peer, which the Luna session never uses). `CapturePanelRenderComparisonTests` checks only the ISO and
WB dials because Luna hides the AF mode panel. The full `OpenInstaCineTests` suite passes.

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
  gimbal rate stick (iOS shaping, 20 Hz), recenter, flip, zoom 1..15 (chips 1, 2, 3, 6, 15),
  tap focus and Deep Track open/cancel. Request bytes are ports of
  `Adapters/Insta360Protocol` and are pinned to the Swift fixtures in `LunaControlTest`.
- Status and settings (2026-09-25, second pass): `LunaBackend` polls capture status every 1 s and
  device status every 5 s, reads photography options for the active function mode, and follows
  notifications 8208 (capture), 8293/8334 (settings changed) and 8275/8198/8195 (re-read status),
  like iOS `LunaCameraBackend`. It publishes a neutral `core-api` `CameraReadout`; the Luna session
  maps that onto the shared `CameraStatus` in `session/LunaShellMapping.kt` (port of iOS
  `LunaShellMapping`): ISO (with the Luna 160 stop), shutter, exposure mode, EV, WB (5 s settle
  pin), color (Standard, I-Log, Dolby Vision), format and the fw 1.1.15 format table, battery,
  charging, storage, shooting mode, REC state and timer, zoom, gimbal mode and speed. Optimistic
  pins, the 120 ms exposure coalescer and the 400 ms settings re-read match iOS.
- Controls (same shared sheets as upstream, Luna underneath): record start/stop (per mode, below), photo
  (cmd 3) in Photo mode, ISO / shutter / auto-manual (one exposure message, program chosen as on
  iOS, no ISO top-limit sentinel for manual with ISO), EV, WB auto / kelvin, color profile, format
  (cmd 9 types 31, 63), shooting mode (cmd 7 options 40/41; Luna names TimeShift, PureVideo,
  Slow Motion, Timelapse), gimbal mode and follow speed (option 91), gamepad actions. Zoom and tap
  focus now write the active function mode instead of always 7.
- Official-app parity from the fw 1.1.15 capture (port of commit `4d28629`, unit-tested only on
  Android): record start/stop carry the shooting mode (cmd 4 field 1 / cmd 5 field 2: 1 Video and
  PureVideo, 4 TimeShift, 9 Slow Motion; Timelapse cmd 22 `0801` / cmd 23 `{1:1, 2:metadata}`; stop
  bodies carry the official metadata stub), picked by `LunaBackend` from the active mode. Stick
  moves and the release carry field 4 = 4. Photo mode (function mode 6) exposure writes still (20)
  and video (21) exposure together; photo EV adds type 77 = 1; 1080p 240 (27) also writes colour
  35 = 1 (Standard). The format list gains 9:16 2.7K 30/25 (443/444, added to the schema table)
  and 1:1 3K (119/120/121/446/447/448, shown as the shared 3K 1:1 chip). Gimbal: the shell's
  fourth slot is FPV-V (option 91 field 4 = 4), Luna Lock (5) maps to nothing, and the picker
  reads Roll Lock / Roll & Tilt / FPV / FPV-V through a new `GimbalMode.labelOverrides`. Tap focus
  is the official box 0.0869 x 0.1545 (0.1159 wide in photo), centred on the tap by the backend
  (`CameraControls.tapFocus` now takes the tapped point).
- Camera media: `MediaLibraryController` lists through cmd 13 + 38 (proxies hidden), renders
  thumbnails from cmd 11 type 2 NV12 (BT.709 limited range to JPEG), deletes by URI with cmd 12
  (the camera removes the LRV too), and downloads / plays over HTTP at the file's own path on
  `192.168.42.1`. Live video is paused while the album is open and restarted after; the backend
  binds the process to the camera network so the shared OkHttp client reaches the camera.
  Favorites stay local, as in the official app.
- Emulator, local replay with a fixed debug readout (no camera): the live chrome shows 41 GB,
  4K · 25p, I-Log, Video, 66 %, ISO 400, 1/50, M and 5600K; the format sheet lists the readout's
  table and the ISO wheel carries 160. Operator Setup shows the OPENINSTACINE header. Shots in
  `.local/android-shots/` (`live-replay-readouts-landscape.png`, `format-sheet-replay-landscape.png`,
  `iso-sheet-replay-landscape.png`, `settings-header-landscape.png`).
- Kotlin tests pin the new encoders and decoders to the same captured byte vectors as the Swift
  tests (`LunaControlTest`, `LunaStatusTest`) and check the shell mapping round trips
  (`LunaShellMappingTest`).
- Upstream-derived shell files touched for Luna vocabulary (mirroring the iOS core additions):
  `session/CameraCommands.kt` (I-Log / Dolby Vision color ids and labels, ISO 160, mode label
  overrides), `session/Models.kt` (Luna color wheel), `session/VideoFormat.kt` (Luna resolution
  bytes 0xD0 to 0xD6), `media/MediaModels.kt` (direct-path media host, Insta360 file timestamps),
  `media/MediaLibraryController.kt` (Luna list/thumbnail/delete branch).
- Gating matches iOS: no AF mode, no aperture, no multiview (button hidden), no programmed moves,
  no audio controls. The Android shell has no Wi-Fi/Hotspot setup choice or head tracking to hide.
- I-Log to Rec.709 sits in the camera LUT tab (`MonitorTransfer.ILOG`, camera looks in the DJI
  category so upstream tab logic and tests hold). DJI LUT assets are not bundled.
- Brand copy: legal bodies, pairing steps, wordmarks, links (`openinstacine.app`, GitHub repo)
  mirror the iOS text. Launcher and splash logo are the yellow monitor mark.
- `./gradlew :app:assembleDebug testDebugUnitTest lintDebug` passes: 996 monitor, 121
  monitor-ui and 28 luna-adapter JVM tests. Test edits vs upstream: the source-contract test reads
  `monitor/` instead of `app/`, and legal/link assertions name OpenInstaCine and Insta360.
- Emulator (`OpenInstaCine_API35`, landscape): pairing, live chrome in local replay (zoom chip,
  Deep Track button, gimbal stick, lock, DISP, LUT/assist rail) and Operator Setup render with the
  yellow accent. Shots in `.local/android-shots/` for comparison with `.local/parity-shots/oic/`.

### Remains

- Everything above is emulator and unit-test verified only: no status read, control, capture or
  media call has run against a real Luna from Android. Real Luna over Android BLE, Wi-Fi and TCP,
  reconnect/background recovery and all controls: untested on hardware.
- Not ported from iOS yet: gimbal limit pulses (8302 / option 92), Deep Track lock state from
  8315 (the box stays until cancelled), the capture-stopped error note (8201), face priority,
  re-listing media after a capture while the album is open, a decoder flush on album exit, and
  Auto LUT picking the I-Log cube (the shared resolver keeps Auto off for the generic family).
- Shared chrome still shows DJI-only affordances the Luna cannot use: the AUDIO readout (a dash)
  and the "Auto Native ISO" D-Log toggle in the ISO sheet.
- Live decode on the emulator: the goldfish HEVC decoder returned a solid frame for the Luna replay
  in this run (the 2026-09-11 review got a moving picture); needs a real device.
- There is no Android equivalent of `scripts/sync-openpocketcine.sh`; the resync was manual
  (upstream `app/src` into `monitor/src`, then the brand, I-Log and session seams re-applied).
