# OpenCine integration candidate

Branch `opencine/integration` combines every local OpenCine candidate for OpenInstaCine so it
can be reviewed and device-tested once. Local only: nothing is pushed, and it cannot build in
CI until the shared repositories are published (see the end of this page).

## What it combines

| Work package | Source branch | Head |
| --- | --- | --- |
| CORE-02 Luna: ISO, shutter, white balance and record through OpenCineCore `CameraSession` | `opencine/core-02-luna` | 04f6413 |
| STATE-01 Luna: per-session ownership, profile, zoom ceiling and EV calibration; CORE-01b adoption | `opencine/state-01-luna` (contains core-02-luna) | 7353aa7 |
| UI-03: design system from OpenCineUI (`MonitorUI`, `MonitorPresentation`, Android `monitor-ui`) | `opencine/ui-03-shared-ui` | ede16d7 |
| MEDIA-01: LUT, curve, scope, shutter angle and frame timing math from OpenCineMedia | `opencine/media-01` | f579e8f |
| OPTIONAL-02: gimbal programs and head-track math from OpenCineMotion (`MotionCapabilities.lunaUltra`) | `opencine/motion` | 1b67ba7 |
| OPTIONAL-02: watcher relay wire v1, control lease and pacing from OpenCineRelay | `opencine/relay` | 0aaac91 |
| MEDIA-02 step 4: VideoToolbox decoder runtime and decoded-frame leases from OpenCineApple (stacked) | `opencine/apple` | see `git log` |
| CORE-API: Kotlin shell contract and Luna adapter from OpenCineInsta360 `Android/` | `opencine/core-api-shared` | 9f5ee09 |
| MEDIA-02 step 3: Android Vulkan renderer from OpenCineCore `:vulkan` | on this branch | e3e03ce |
| RELEASE-01: sync narrowed to the iOS shell; three unreachable core types dropped | on this branch | 705d316, 764da0e |

### Merged branches

Merged into `opencine/integration` with `--no-ff` on 2026-10-02, in this order:

- `opencine/motion` 1b67ba7 (merge c5c70da)
- `opencine/relay` 0aaac91 (merge 32aef1b; `Package.swift`, the Android Swift staging inputs,
  `ios/project.yml` and pins merged as a union)

- `opencine/core-api-shared` 9f5ee09 (merge cc9de6f; only `opencine-pins.txt` conflicted, resolved
  to each sibling's current main; `settings.gradle.kts` includes `opencinecore`,
  `opencineinsta360` and OpenCineUI once each; build identity hashes the union)

Pins now (`opencine-pins.txt`, each sibling's `main`): OpenCineUI 54bcbb3, OpenCineCore 4a421fe
(motion, relay, Apple runtime, harness fixes, `:vulkan`; README-only on top of 1c648a6), OpenCineInsta360 e90a11a (Swift
products plus `Android/` shell contract and Luna adapter, harness fixes).

Base is `opencine/state-01-luna`; the other two are merged with `--no-ff`. Pinned siblings
(`opencine-pins.txt`): OpenCineUI 54bcbb3, OpenCineCore 28a0196 (contains the MEDIA-01
commit 4d001e4 the media branch pinned). `ios/project.yml` names both packages by path;
Android includes `../../../OpenCineUI/Android` (default name `Android`) and
`../../../OpenCineCore/Android` (named `opencinecore`). The root `Package.swift` takes
OpenCineMedia from `../OpenCineCore`, the same checkout the app project names, so Xcode sees
one package identity. `tools/build-identity.py` hashes both siblings on both platforms
(OpenCineCore `Package.swift` and `Sources`, plus `Android` for Android builds).

## What changes for users

Nothing is meant to look different. Underneath:

- Command path: ISO, shutter, white balance and record go through one OpenCineCore session per
  camera. A change shows as confirmed only after the camera reports it; a refused, unapplied or
  timed out write says so instead of reverting silently.
- Session isolation: each connection owns its backend, labels, media route, zoom ceiling (15x
  on Luna, previously clamped to 12x in readouts) and learned picture EV calibration. Old v1 EV
  offsets seed the new per-camera keys and are never rewritten.
- Shared UI and media: theme, Sora, icons and page layouts come from OpenCineUI; LUT, I-Log
  curve, scope and false-colour math come from OpenCineMedia. Screenshots matched before and
  after on the simulator.

## Physical device checklist (Luna Ultra, iOS and Android)

Nothing below has run on hardware.

1. Install over a build that learned an I-Log picture EV: the meter starts at the old value,
   then learns per camera; it keys separately for Matrix/Face metering and I-Log/Standard.
2. Look: yellow accent with dark text on yellow, Sora, Lucide icons on first launch, cameras,
   pair, settings, live and media screens. Mode, colour and gimbal names are Luna names
   (TimeShift, Standard, Roll Lock).
3. ISO Auto, 400, 800 confirms in under 4 s; shutter then ISO quickly (and the reverse) neither
   reverts; a manual ISO the camera drops shows "not applied".
4. WB Kelvin confirms within 6 s; WB Auto confirms; AE Lock and AWB Lock work.
5. Record start and stop: the lamp waits for capture status; stop with file save under 10 s;
   start on the camera button, then app Record sends Stop; a fresh connect before capture status
   refuses; timelapse record; watch and watcher-relay record.
6. Mode change, then ISO/WB lands in the new bank.
7. Wi-Fi drop mid-write shows "link dropped", recovers, and controls work; reconnect makes old
   controls stale; a stream restart (album return, stall repair) during an ISO write still
   confirms it.
8. Zoom chip and dial reach and show 15x.
9. Media album thumbnails, playback and download from 192.168.42.1; LUT preview, false colour,
   waveform/parade and I-Log display match the previous build.
10. Live View diagnostics copy works before and after connect.
11. OPTIONAL-02 motion: gimbal programs, head tracking and joystick moves behave as on the
    previous build (head tracking keeps the inherited reach, pan -48 to 225, tilt -44 to 70).
12. OPTIONAL-02 relay: a watcher on the previous build watches this build and the reverse, on two
    iPhones; a version mismatch is denied with the usual copy. Wire bytes are unchanged (golden v1
    tests).
13. MEDIA-02 step 4 (iPhone): first connect shows a picture; LUT, scopes, zebra, false colour,
    HDR panel and upscaler toggles never black the well; background return keeps the picture;
    Face AF tracks. Compare glass-to-glass latency, memory over 30 min live with LUT and WAVE, and
    thermal state after 20 min against `opencine/integration` without this branch.

Known limits: two Luna cameras at once cannot be tested (LunaWiFi joins one camera access point,
192.168.42.x); the two-session gate is simulated only. Android reports no serial on this path,
so EV keys use the connected camera id.

## MEDIA-02 step 4: Apple runtime

Branch `opencine/apple` (on this candidate) runs `HevcDecoder` on OpenCineCore's `OpenCineApple`
`VideoToolboxDecoder` (display layer, format, VT session, sample buffers, error ledger, generation
fence). `HevcDecoder` keeps the presentation policy; its only API change is `onSourceFrame`, which
lends a `DecodedFrameLease`. The refactor is identical to OpenPocketCine's, so the sync script
carries it. App-side: the log subsystem, `SimulatorLiveFeed.isConfigured` and the watch preview guard.
Pins OpenCineCore on its `apple` branch until that merges to Core main.

## MEDIA-02 step 3: Android Vulkan renderer

`libopc_vulkan.so` (C++, CMake, 15 shaders) and its JNI facade `feed.OpcVulkan` come from
OpenCineCore's `:vulkan` module (`com.opencapture.opencine:vulkan`, substituted from the
`opencinecore` included build), as in OpenPocketCine a76488ad. The deleted `:monitor` copy was
byte-identical to OpenPocketCine's pre-move renderer (with the #482 upright-raster fix); the
facade keeps its fully qualified name. Debug APK before and after: same 22 native libraries, one
`libopc_vulkan.so` of the same size with the same 786 dynamic symbols (21 `Java_` exports) and
the same NEEDED list. `LiveVulkanSession`, the present gate, crash guard and window attach stay in
`:monitor`. The present-batch regression runs in OpenCineCore
(`scripts/android-vulkan-sync-test.sh`); this app never had a recipe for it.

Device check (Android, Luna): live picture through Vulkan with LUT, scopes, peaking and the glass
backdrop; background return, rotation and surface recreation keep the picture.

## RELEASE-01: sync scope

`scripts/sync-openpocketcine.sh` now copies only the iOS presentation shell and three neutral
tools. The Swift core (`Package.swift`, `Sources/`, `Tests/`), `Apps/Android`, the package graph
(`ios/project.yml`) and everything a shared package owns are never copied, so the STATE-01 core
edits are safe. Details, the first-sync base to use after publishing and the Atlas edge:
`openpocketcine-foundation.md`, "Sync scope".

## Risks before merging

- First sync after publishing: set `openpocketcine-sync-commit.txt` to OpenPocketCine's
  post-integration `main` commit, and decide Frame.io (OpenPocketCine moved its client into
  OpenCineFrameIO; this app keeps its own until it adopts the product).
- The Kotlin `ScopeExposureCeiling` risk listed here before is closed: each feed owns its
  ceiling since 7bdb55c.

## VENDOR-03: Luna integration package

Branch `opencine/vendor-03-luna` (on this candidate) takes `Adapters/Insta360Protocol`,
`Adapters/Insta360Apple` and `Sources/MonitorContracts` (folded into `Insta360Apple`) from the sibling
package OpenCineInsta360 (pinned in `opencine-pins.txt`). The XcodeGen `Insta360Apple` framework
target is gone; the app links the package products. `AppModel.lunaConfiguration` keeps the keychain
service `org.opencine.openinstacine.camera` (saved camera authorization and Wi-Fi stay readable)
and the account names are unchanged. Device check: a phone with a camera saved by the previous
build reconnects over its saved Wi-Fi without new Bluetooth approval.

The Kotlin side moved too (CORE-API): `:core-api` and `luna-adapter` are gone from `Apps/Android`.
OpenCineInsta360 `Android/` builds `com.opencapture.opencine:insta360-shell` (the shell contract:
`CameraBackend`, `CameraControls`, `CameraMediaStore`, `CoreSessionSource`, `ConnectionPhase`,
`CameraReadout` and the other Luna-shaped values, package `com.opencapture.opencine.insta360.shell`)
and `com.opencapture.opencine:insta360-luna` (`LunaBackend`, `LunaCameraSession`, package
`com.opencapture.opencine.insta360.luna`), substituted from the included build `opencineinsta360`
(`../../../OpenCineInsta360/Android`, pinned with the Swift package). `:monitor` depends on the
contract, `:app` on the adapter. `BrandIdentity` is app-owned and now lives next to
`MonitorConfiguration`; the legacy `CameraSession` seam (phase/startScan/disconnect) is retired.
The SharedPreferences name `openinstacine.client-identity` stays the `LunaBackend` default (pinned
by a package test). The library builds with compileSdk 37 and needs no AAR-metadata exemption.
Device check: a phone that approved the camera with the previous build reconnects without a new
approval on the camera screen.

## Publishing prerequisite

The OpenCineUI, OpenCineCore and OpenCineInsta360 repositories must exist before CI, Xcode Cloud or another
machine can build this branch: `scripts/checkout-opencine.sh` fetches the pinned SHAs from them.
Follow `opencapture-atlas/docs/PUBLISH.md`, then replace the path packages and included builds
with url + version pins and Maven coordinates.
