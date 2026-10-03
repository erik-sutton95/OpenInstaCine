# OpenCine integration candidate

Branch `opencine/integration` combines every local OpenCine candidate for OpenInstaCine so it
can be reviewed and device-tested once. Local only: nothing is pushed, and it cannot build in
CI until the OpenCine repository is published (see the end of this page).

Since 2026-10-02 every shared package lives in one platform repository, OpenCine (`../OpenCine`,
pinned by one line in `opencine-pins.txt`): one `OpenCine` path package in `ios/project.yml` and
`Package.swift`, one Android included build `../../../OpenCine/Android` named `opencine`. The
sections below record the work packages as they landed; the repository names they cite
(OpenCineUI, OpenCineCore, OpenCineInsta360 and their `opencinecore`/`opencineinsta360` builds) are
the former repositories, now areas of OpenCine with the same product names and coordinates.

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
| SHELL-01 step 6: live monitor laid out from the Luna integration's capability projection | `opencine/shell-01` | see `git log` |

### Merged branches

Merged into `opencine/integration` with `--no-ff` on 2026-10-02, in this order:

- `opencine/motion` 1b67ba7 (merge c5c70da)
- `opencine/relay` 0aaac91 (merge 32aef1b; `Package.swift`, the Android Swift staging inputs,
  `ios/project.yml` and pins merged as a union)

- `opencine/core-api-shared` 9f5ee09 (merge cc9de6f; only `opencine-pins.txt` conflicted, resolved
  to each sibling's current main; `settings.gradle.kts` includes `opencinecore`,
  `opencineinsta360` and OpenCineUI once each; build identity hashes the union)

Pins then (before the consolidation into OpenCine): OpenCineUI 54bcbb3, OpenCineCore 23adfdf
(motion, relay, Apple runtime, harness fixes, `:vulkan`; README-only on top of 7a17350), OpenCineInsta360 f8f4c27 (Swift
products plus `Android/` shell contract and Luna adapter, harness fixes).

Base is `opencine/state-01-luna`; the other two are merged with `--no-ff`. Pinned siblings
(`opencine-pins.txt`): OpenCineUI 54bcbb3, OpenCineCore 8c2415c (contains the MEDIA-01
commit 248b858 the media branch pinned). `ios/project.yml` names both packages by path;
Android included the OpenCineUI and OpenCineCore Android builds (the latter named
`opencinecore`). The root `Package.swift` took OpenCineMedia from the same OpenCineCore checkout
the app project named, so Xcode saw one package identity. `tools/build-identity.py` hashed both siblings on both platforms
(OpenCineCore `Package.swift` and `Sources`, plus `Android` for Android builds).

### Shared native bridge helpers (SHELL-04)

The Android Swift facade now imports OpenCineJNISupport for JNI strings, arrays
and method lookup. The app-local CJNI header target is removed. Native class
names, exported methods and runtime-library packaging stay compatible. Native
staging and build identity include the helper sources, so a shared helper edit
rebuilds the app library. This changes no saved data or credential namespace.

Automated Android native probes cover strings, null/empty arrays, LUT bytes and
float arrays; exported Java symbol sets are compared with the prior app binary.
Camera transport and live-picture checks remain in the device checklist.

### Shared Frame.io client (SHELL-03 I5c, first increment)

The iOS app directly consumes OpenCineFrameIO for PKCE and token exchange/refresh, response
models, account/workspace/project requests, upload parts and completion polling. The copied
FrameioService is removed. The app supplies its Info.plist identity, browser presentation,
Keychain adapter, destination preferences and internet-hop lifetime.
The Keychain service `OpenInstaCine.frameio`, account `oauth-token`, accessibility and existing
saved-token JSON remain unchanged. Progress still reaches callers on MainActor. API/upload
requests retain the 12-second timeout without waiting for connectivity; browser token exchange
retains URLSession.shared. The common client also preserves an existing refresh token when IMS
omits its replacement and rejects invalid resource identifiers/file inputs before HTTPS.

Both-architecture simulator build-for-testing, the actual saved-token JSON compatibility test
and the two existing delivery-hop lifetime tests pass. This is a local candidate; real Adobe
sign-in, upload, camera network return and physical-device behavior remain untested. Frame.io
remains an iOS-only feature in this app. Shared delivery batch composition is still a subsequent
increment; adopting this client does not complete the full delivery migration.

### Shared native exporter (SHELL-03 I5c, second increment)

The iOS app now consumes `OpenCineApple.MonitorMediaExporter` for native encoding, full-raster
LUT baking, preset/fallback selection, progress, output readiness and optional JSON sidecars.
The identical Pocket/Insta exporter donor is replaced here by the existing Documents/exports
filename adapter and source-curve/metadata mapping. Initial preparation remains at 2%; native
progress and sidecar naming/JSON policy remain unchanged. The shared module receives a sampled
cube and explicit metadata key/value instead of importing a camera integration.

The same five native export regression tests pass against both the original and migrated
both-architecture products, including actual encoded pixels and embedded curve metadata.
Shared copy/sidecar fixtures, the full shared Swift suite and strict concurrency checks pass.
This is a local candidate, with the published/canonical app pin unchanged. Physical-device
export and cloud delivery remain untested; batch, route and delivery UI ownership remain
subsequent increments.

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
- Capability-driven layout (SHELL-01): the live monitor shows what the connected Luna declares
  through OpenCine (`LunaCameraSession.layout`): gimbal and head tracking from its motion,
  host-derived timecode, no audio levels, no iris. The app keeps only clip delete, clip star and
  the internet hop. Differences: the Clean view settings no longer offer an AUDIO pin (Luna
  reports no audio levels); with no camera connected, Settings shows no gimbal, joystick,
  head-tracking, zoom chip or timecode rows on iPhone (nothing is declared yet; Android already
  behaved this way). No
  Multiview entry: the app qualifies no multicam budget.
- Shared connection flow (SHELL-02): the cameras page, the pair page, connect progress and
  failures come from OpenCine's app shell (`OpenCineAppKit` `CamerasScreen` / `PairScreen` /
  `CamerasModel`, Android `:appkit`) over the Luna integration (`LunaIntegration`, which connects
  through the app's session). Saved cameras move to a versioned document (iOS UserDefaults
  `OpenInstaCine.Cameras`, Android prefs `openpocketcine.cameras`/`document`) merged on every
  launch with the old records (`OpenInstaCine.SavedCameras`, `openpocketcine.saved-cameras`/
  `records-json`), which stay mirrored so an older build still reads current cameras. Keychain,
  Keystore, approval identity, media and EV keys are untouched. Visible differences: the pair
  page rail is "Find your camera" then the four connect-card steps (was four Luna pages), with the
  step name as title, one instruction card per prompt and no per-step Luna body text, check list
  or VPN banner during an attempt (the pre-check, still-looking and VPN tips and a Bluetooth
  problem show while choosing); Pair on a nearby card opens the pair page with it selected
  (Continue starts it); a nearby card reads "Ready to pair" with "Luna Ultra · nearby" on iOS
  (was "Insta360 · nearby") and "Insta360 Luna Ultra · nearby" on Android (was "Pocket · ...");
  Android's offline card copy is the shared "Not found. Power it on to reconnect"; the
  connecting card's caption is the prompt ("Tap Join when iOS asks...") instead of the phase
  label; iOS now offers Open Settings when Bluetooth is off or not allowed; one undecodable saved
  record no longer empties the list on the next save; Android forget also drops the camera's
  saved Wi-Fi (as iOS always did); iOS "on the camera network" now tests the Luna's
  192.168.42.x (Pocket's 192.168.2.x test never matched).

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
14. SHELL-01 (iPhone and Android, against `opencine/integration` without `opencine/shell-01`):
    the joystick, gimbal sheet, motion overlay and head tracking (iPhone) appear and move the
    head; no AUDIO tile, assist, meter or Clean view pin anywhere live; the live timecode runs
    time of day and matches the camera clock after connect; zoom chip and FOCUS tile as before,
    no APERTURE; record start and stop from the record button with and without confirmation.

15. SHELL-02 (iPhone and Android): first pair from an empty install (approve on the camera, join
    its Wi-Fi, picture); reconnect a saved camera with no new approval; quick join from saved
    Wi-Fi (camera powered on after a while, Bluetooth advert not seen yet); Bluetooth off and
    Bluetooth not allowed show the Bluetooth card with Open Settings, and the list fills after
    returning; Cancel during each step; forget (the camera's Wi-Fi password goes with it, the
    approval stays: re-pair without a new Allow); a failed connect shows the same copy as before
    ("The camera didn't respond in time..."). Upgrade from the current TestFlight or Play build
    keeps every camera, name and Wi-Fi; downgrade to it shows them too, an edit there (rename,
    forget) survives the next upgrade.

16. SHELL-03 I-1 (iPhone and Android): connect a saved camera from the cameras page: the monitor
    appears with the picture; open Settings, then Media, and close each: the picture is still
    there and live (no reconnect, no black frame, no second "Starting the picture"); ISO, shutter,
    white balance (Auto and Kelvin) and EV edits from the drums confirm as before; record start
    and stop from the record button with and without confirmation (the lamp waits for the camera);
    rotate the phone with Settings open and closed; background the app and return (the picture
    comes back once); Disconnect from Settings returns to the cameras page and the camera keeps
    recording if it was; connect a second camera after closing the first (replace camera): no
    note or edit from the first appears; close the app while recording: the camera keeps
    recording.

17. Cameras-page follow-up (iPhone and Android, physical check untested): press and hold
    the Luna's Camera Wi-Fi chip, rename only that setup, relaunch, and reconnect without
    another approval or password prompt. Clear the setup name and confirm the default label
    returns. Open Privacy and Terms from both an empty first-pair screen and the saved-camera
    screen; close each and confirm the same page remains. An older build has no setup-name
    field: installing it, editing the camera name, and upgrading again must keep the new
    setup name, saved Wi-Fi, favorites and approval identity.

Known limits: two Luna cameras at once cannot be tested (LunaWiFi joins one camera access point,
192.168.42.x); the two-session gate is simulated only. Android reports no serial on this path,
so EV keys use the connected camera id.

## SHELL-02 candidate verification

The candidate pins OpenCine `399c3c7` for the shared connection flow. Automated checks on
2026-10-02 pass: `just check`, 595 root Swift tests, `just android-check` (695 monitor tests,
including six saved-camera migration cases), and the iOS suite on private iPhone 16 Pro and
iPad Pro 13-inch simulators (500 tests each: 499 pass, one existing missing D-Log2 cube skip).
The handbook builds with 27 pages.

The migration fixtures exercise import, repeated import, legacy decoding after edits,
downgrade edits merged on upgrade, malformed record preservation and an unknown future
document version. The iOS model test also reconnects a saved camera without a fresh discovery
advertisement. Simulator installation of the previous and new binaries preserves saved
records across upgrade, downgrade and another upgrade after legacy edits.

Before/after simulated camera and pairing screens cover saved plus nearby cameras, empty,
connecting, approval, network join, video link and failure states on iPhone and Android, with
saved cameras and approval on iPad. The visible differences are listed above; Android's
optional iOS appearance switch remains unchanged. The shared connection model's Android
scope is cancelled when the activity closes so its discovery and connection collectors end
with the monitor. Physical pairing, reconnect, cancellation, recovery and credential
preservation remain **untested**, pending checklist item 15.

## SHELL-03 slice I-1: shared root, monitor lifetime and common controls

The app root is OpenCine's `AppShell` over `ShellModel` (Swift and Compose): the cameras and pair
pages, the monitor, and the Settings and Media covers. The shell owns the connected camera's
common session: `LunaIntegration`'s attempt session is bound when it connects, closed once when
the operator leaves the monitor (never a camera command, so a recording continues) and replaced
cleanly by the next camera. ISO, shutter, white balance and record go through the shared
`MonitorControlModel` (the one snapshot subscription, coalesced edits, record start or stop from
a fresh report, late outcomes of a previous camera dropped). The app's own reconnects of the same
camera (foreground, internet hop, saved Wi-Fi) keep that session. Scene activity reaches the
session once per change.

Deleted from the app: the session's own Core subscription, pending edits and record operation
(iOS `CameraSessionCore`, Android `PocketCameraSession`/`CoreControl`), `homePanel`,
`liveOperatorPanel`, the pairing flag, the enter/leave-live cleanup and duplicated scene
handlers. Temporary until later slices: the existing `LiveViewScreen` is the shell's monitor slot
and still draws Settings and Media over itself; the capture drums map this app's values
(`IsoIndex`, shutter denominators, Kelvin) through the session's adapters into the shared model;
the shared readouts are still projected into `CameraStatus` for the views that read it; the
Android launcher still installs its backend factory (`MonitorConfiguration.install`).

Simulated review: `OPV_UI_REVIEW_SCREEN=sequence` (iOS) and the debug `ShellReviewActivity`
(Android) step cameras, live, Settings, live, Media, live, cameras in one launch and log the
monitor host count: one host for the whole live period, disposed once on close. Physical
behavior is **untested** (checklist item 16).

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
  post-integration `main` commit. Frame.io's iOS client now comes from OpenCineFrameIO;
  app-specific credential storage and browser presentation remain here.
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
(the OpenCineInsta360 Android build, pinned with the Swift package; now OpenCine `Android/`). `:monitor` depends on the
contract, `:app` on the adapter. `BrandIdentity` is app-owned and now lives next to
`MonitorConfiguration`; the legacy `CameraSession` seam (phase/startScan/disconnect) is retired.
The SharedPreferences name `openinstacine.client-identity` stays the `LunaBackend` default (pinned
by a package test). The library builds with compileSdk 37 and needs no AAR-metadata exemption.
Device check: a phone that approved the camera with the previous build reconnects without a new
approval on the camera screen.

## SHELL-01: common lens commands

Luna zoom and AF-S/AF-C now reach the connected `LunaCameraSession` through
OpenCine's common setting commands. The configured connection ceiling describes
zoom; the iOS pinch still coalesces latest values at its existing 80 ms cadence.
Product Showcase stays in the typed Luna extension. Camera reports alone populate
the shared lens observations; acknowledgement does not confirm a write.

Physical checks on iOS and Android remain **untested**: pinch/slider/chip zoom
ramps and settles at every offered stop, configured maximum refuses values above
the ceiling, AF-S/AF-C match camera readback, Product Showcase keeps its dedicated
label, recovery rejects old queued controls, and disconnect never stops recording.
Repeat with a saved camera installed before this change. Simulator/manual-clock
tests establish admission and receipt behavior only.

## Publishing prerequisite

The OpenCine repository must exist before CI, Xcode Cloud or another machine can build this
branch: `scripts/checkout-opencine.sh` fetches the pinned SHA from it. Follow
`OpenCine/atlas/docs/PUBLISH.md`, then replace the path package and included build with a url +
version pin and Maven coordinates.
