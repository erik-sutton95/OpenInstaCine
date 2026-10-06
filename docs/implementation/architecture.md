# Implemented architecture and migration boundary

Date: 2026-09-11. The ownership table and diagram were updated on 2026-10-01
(OpenCineUI adoption, UI-03) to name the current paths and products; the rest of
this page is the 2026-09-11 extraction review. The
[shared-engine standard](../SHARED-MONITOR-ENGINE.md) is the long-term contract;
the older [integration inventory](../shared-engine-integration.md) and platform
inventories describe the baseline and planning inputs, not completed sibling
migrations.

The shell was extracted from OpenPocketCine commit
`9c4e7334ca4d935c5d467abecaf8f968f7927d84`, preserving the existing native screen
and renderer implementations. [Baseline provenance](baseline-provenance.json)
records original paths and source hashes. OpenPocketCine and OpenZCine were
read as references and were not modified by this extraction.

## Shared settings migration, 2026-10-03

The actual operator page now uses OpenCine's `MonitorSettingsPage`, common settings controls,
touch/safety section and HDR panel section on SwiftUI and Compose. Common stored choices
forward through `MonitorOperatorPreferences` with the existing app domains and keys intact.
Swift preference code moved from `LiveAssists.swift` to `OperatorPreferences.swift`; the
remaining assist values retain their original storage behavior. The Pocket sync script, since
retired, excluded these migrated files so a sync could not restore the deleted implementations.

Cache presentation, app information, project/legal, support and diagnostics sections also
use the shared settings views. Cache IO/confirmation, legal routes, reporting consent,
diagnostic export/deletion and privacy policy remain app callbacks. Android app information
now receives this app's actual protocol and theme copy. Native input/action/display controls
are shared rather than copied implementations.

Remaining display, assist, link/controller and delivery sections still live in this app and
will migrate separately. The ownership table below records the earlier extraction baseline.
The settings migration preserves Android's existing Sharing placeholder and iOS's existing
sharing support. Simulator rendering and automated checks do not qualify physical devices.

## Ownership and dependencies

| Owner / location | Responsibility and current dependencies |
| --- | --- |
| `ios/OpenInstaCine` | iOS app: app-owned code on the shared OpenCine shell (`OpenCineAppKit`), no longer synced from OpenPocketCine, plus Luna presentation adapters (`CameraSession*.swift`, `LunaShellMapping.swift`, `OpenInstaCineBrand.swift`, assets). `OpenInstaCineBrand.apply()` sets `MonitorTheme.accentRGB = 0xFFCF00` before any view is built. Links `OpenInstaViewCore`, `OpenCineAppKit`, `Insta360Protocol`, `Insta360Apple` and OpenCineUI `MonitorUI` / `MonitorPresentation` |
| OpenCineUI `MonitorUI`, `MonitorPresentation` | Shared SwiftUI design system (theme, Sora, Lucide/assist icons, canvas, pages, controls) and Foundation-only presentation/layout policy. Part of the OpenCine platform repository, a sibling checkout at `../OpenCine` that `ios/project.yml` names as a path package (candidate until a versioned release). No camera, vendor or app dependency. Its tests run in OpenCine |
| `ios/OpenInstaCineWatch` | watchOS remote over WatchConnectivity; depends on `OpenInstaViewCore` |
| `Sources/OpenInstaViewCore` | Portable core, forked from OpenPocketCine and OpenInstaCine-owned since RELEASE-01 (no longer synced; upstream's copy depends on OpenCineDJI), with Luna hooks (I-Log, Luna resolutions, `.lrv` proxy, per-session `CameraProfile`): color science, LUTs, media manifest, saved cameras, plus the inherited Osmo models and DUML codecs |
| OpenCine `Sources/Insta360Protocol` | OpenCine package product for UCD2, bounded reassembly/checksum, protobuf, scheme-3 envelopes and verified Luna read/live commands. Foundation only, no network/BLE/crypto implementation |
| OpenCine `Sources/Insta360Apple` | CoreBluetooth, CryptoKit, Keychain, hotspot join, Network.framework TCP and Luna session lifetime. `LunaCameraSession` implements OpenCineCore `CameraSession` for ISO, shutter, white balance and record (settle and readback included). An OpenCine package product linked by `ios/project.yml`; depends on `Insta360Protocol`, `CKcp`, OpenCineCore, OpenCineMotion and OpenCineMedia |
| `Apps/Android/app` | Thin branded activity, app manifest and DEBUG replay selection. Installs the brand identity (accent `0xFFFFCF00`) and Luna backend factory through `MonitorConfiguration` |
| `Apps/Android/monitor` | App-owned Compose code on the shared OpenCine shell (`appkit`), no longer synced from OpenPocketCine: MediaCodec, Vulkan/GLES, assists, library/player, local delivery and Android integration. Depends on OpenCine `appkit`, OpenCineInsta360 `insta360-shell`, OpenCineUI `monitor-ui`, OpenCineCore `media` and `vulkan` (`libopc_vulkan.so` and its JNI facade `feed.OpcVulkan`) and staged native libraries |
| OpenCineUI `Android/monitor-ui` | Compose design language (theme with brand-assigned `MonitorPalette.accent`, Sora, icons, page scaffolds). Coordinate `com.opencapture.opencine:monitor-ui`, substituted from the included build `../../../OpenCine/Android` (named `opencine`) in `Apps/Android/settings.gradle.kts` |
| OpenCineInsta360 `Android/insta360-shell` | Kotlin/JVM backend discovery/lifecycle/state/capability/frame contract (was `Apps/Android/core-api`). Uses coroutines/flows; no Compose or Android platform types. Recording, ISO, shutter and WB are not on `CameraControls`: a `CoreSessionSource` backend opens an OpenCineCore `CameraSession` for them. Coordinate `com.opencapture.opencine:insta360-shell` |
| OpenCineInsta360 `Android/insta360-luna` | Android GATT, JCA cryptography, Wi-Fi/network-bound socket lifecycle and a Kotlin UCD2 implementation; `LunaCameraSession` is the OpenCineCore session (port of the Apple one). Was `Apps/Android/luna-adapter`. Both come from the same included build `../../../OpenCine/Android` (named `opencine`), which also builds OpenCineCore `:core` |
| `Sources/OpenInstaCineAndroidFacade` | Swift JNI exports, using OpenCine `OpenCineJNISupport`. Dynamic product `OpenInstaCineAndroid` imports `OpenInstaViewCore` |

```mermaid
flowchart TD
    Apple[iOS app] --> UI[OpenCineUI MonitorUI]
    UI --> Presentation[OpenCineUI MonitorPresentation]
    Apple --> LunaApple[Insta360Apple adapter]
    Apple --> Core[OpenInstaViewCore]
    LunaApple --> OCCore[OpenCineCore]
    LunaApple --> Protocol[Insta360Protocol]
    Android[Android app] --> Monitor[Compose shell :monitor]
    Android --> LunaAndroid[Luna Android adapter]
    Monitor --> Compose[OpenCineUI monitor-ui]
    Monitor --> API[OpenCineInsta360 insta360-shell]
    LunaAndroid --> API
    Monitor --> JNI[Swift JNI and native renderer]
    JNI --> Core
```

The Apple and Android backend contracts express the same live-connection seam,
but are not one generated cross-language API. Apple already includes optional
semantic control/media operations. Android's new neutral contract currently
covers the live path; its inherited control/media view models remain staged
compatibility code. Kotlin Luna framing is a separately tested implementation,
not a call through the Swift Luna package. Adding controls/media should extend
the neutral contract before implementing camera commands.

## Luna feed path

1. Discover BE80, subscribe to BE82 and issue BE81 writes with acknowledgment.
2. Check the model and negotiate scheme 3 using ephemeral P-256 ECDH,
   HKDF-SHA256 and AES-128-GCM. Use an installation-owned authorization UUID.
3. Check authorization. If required, request approval and wait for the camera's
   touchscreen result. Read the encrypted Wi-Fi response only after approval.
4. Associate with the camera AP and open TCP `192.168.42.1:6666` on its network.
   The Apple adapter compares BLE/TCP serials to detect a different camera at
   the same private address.
5. Send the observed prefix, wait for the camera greeting, start two-second
   heartbeats, read model/auth/status and issue the verified live-start command.
6. Validate frame length/checksum, interpret media subtype `0x20`, remove its
   eight-byte little-endian timing prefix, and deliver Annex-B HEVC to the
   shared native decoder. Scope/assist work uses real decoded pixels.
7. Disconnect with a best-effort live stop, cancel outstanding work and discard
   transport/key state. Recovery is bounded and returns to operator action
   rather than running an endless retry loop.

The observed packet counter advances by 40 at a 25 fps preview cadence. Its
absolute epoch is not established, and it must not be presented as camera
timecode. Preview dimensions, frame rate and Rec.709 transfer do not establish
capture mode, recording rate, recording color profile or media metadata.

The Apple adapter correlates requests by transport generation plus unique
operation ID. A request completes only after both a valid response and the
write completion, covering notification-before-ATT-ack ordering. Approval is
scoped to its active request. Decode generation is checked before assist work
and presentation. The [review](apple-adapter-review.md) explains these fixes and
the remaining deterministic race-test coverage.

## Shared shell behavior retained

The source retains the baseline native monitor rather than constructing a
second set of similar screens. This includes both orientation layouts, the
status/assist/control rails, DISP modes and editor, lock, saved-camera/setup
flow, settings and recovery chrome. Image tools include LUT, peaking, false
color, zebras, waveform, parade, histogram, vectorscope, traffic lights, guides,
grid, crosshair and mirror. Audio UI and gimbal/head-tracking input components
remain reusable but cannot control or measure unsupported Luna features.

The media library/player/cache and delivery surfaces remain shared. Apple's
facade maps optional backend media descriptors to the inherited presentation
model and protects work across camera switches. Luna advertises no camera-media
capability, so this does not claim a working Luna catalog/download/delete path.
Local footage review and explicit replay can exercise the shared player. Apple
retains its Frame.io delivery and LUT bake implementations; configuration is
absent by default. Android retains its existing system-share/delivery scope;
Apple-only baseline features were not invented as Android parity claims.

The palette changes app accents to `#FFCF00` while retaining charcoal neutrals,
fonts, Lucide icons and semantic image-analysis colors. The exact surface
inventory is preserved in [iOS parity](ios-parity-inventory.md) and
[Android parity](android-parity-inventory.md). Retaining source does not by
itself certify every interaction on every device; test and visual review
evidence must be reported separately.

## Session ownership and per-session configuration

Each camera connection has exactly one owner. On iOS the composition root
(`AppModel.makeBackend()`) creates one `LunaCameraBackend` per owner and injects
it with `CameraSession(backend:)`; a borrowed or controls-only session is a
lease that never rebinds the owner's callbacks or connects. On Android each
`PocketCameraSession` creates its own backend. Mode, colour, gimbal and focus
labels, the camera media route (host and path rules) and the zoom ceiling are
per-session values (`CameraProfile`, `zoomCeiling`), not launch-time globals.
The learned picture EV calibration is one meter per session, keyed by device,
recording profile/transfer and metering, and is always image-estimated; a
camera-reported EV wins. Its v1 per-transfer values are read only and seed new
keys of the same transfer. The control epoch moves only when the control link
is (re)established; a stream restart or picture format change does not touch it.

Qualification limit: `LunaWiFi` assumes one joined camera access point
(192.168.42.x) per phone. Two simultaneous Luna connections are not supported
until that is lifted and qualified on hardware.

## What remains staged

1. **Sibling adoption:** the design system (`MonitorUI`, `MonitorPresentation`,
   Android `monitor-ui`) is now one implementation in OpenCineUI, consumed by
   OpenPocketCine and OpenInstaCine candidate branches. Media, motion, relay,
   the Apple decode runtime and the Android Vulkan renderer come from OpenCineCore.
   The former Pocket source-sync workflow has been retired (see
   `openpocketcine-foundation.md`). Remaining legacy app owners migrate through
   reviewed OpenCine contracts and actual app adapters.
2. **Compatibility models:** `MonitorLUT`, `MediaFile`, status/control enums,
   saved-camera records and several rendering bridges still use inherited
   names/types. Native view facades translate where needed. Osmo wire bytes
   are isolated from the new Luna adapter; type-name cleanup is incomplete.
3. **Portable versus platform:** Foundation math is extracted. VideoToolbox,
   Metal, CoreVideo, Android renderers, native media storage and delivery
   services remain platform implementations. The complete delivery queue has
   not been moved into Foundation-only code.
4. **JNI compatibility:** The old `com.opencapture.openinstacine.monitor` internal
   package, JNI symbols and `OpenInstaCineAndroid` library name remain so the
   inherited decoder/LUT/assist calls load correctly. The installed brand app
   ID is `com.opencapture.openinstacine`. Rename both sides together later.
5. **Profiles/assets:** Some inherited color/profile catalog machinery and DJI
   LUT resources remain compatibility material. Luna uses authoritative
   Rec.709 metadata, without the old scene-brightness D-Log inference. Brand
   configuration now injects camera LUT descriptors (stable ID, filename,
   input transfer), including official I-Log → Rec.709. Actual preview metadata
   stays separate from the selected LUT and recording settings. See
   [I-Log integration](i-log.md) for source/profile and HDR boundaries.
6. **Camera commands:** Every capability beyond live video requires research,
   strict codec tests, a native adapter mapping and real-camera validation
   before enabling its shared UI operation.

The superseded shared-core [extraction report](shared-core-extraction.md) recorded
the 2026-09-11 file-level debts. The current
Gradle module split and inherited dependency metadata workaround remain
visible in build files rather than hidden in generated binaries.

## Validation boundaries and repeatable commands

| Evidence | What it establishes |
| --- | --- |
| Python Mac live viewer, [measured report](../mac-preview.md) | Real own-client BLE/auth/Wi-Fi/TCP live preview on Luna firmware v1.0.288, including acknowledged stop and reconnect |
| `swift test` | Shared portable behavior, compatibility/JNI facade helpers and module-boundary checks; 609 passed at extraction |
| `swift test --package-path Adapters/Insta360Protocol` | 24 sanitized fixture, malformed frame, fragmentation, checksum and protobuf/envelope tests |
| Android JVM tests/build/lint | 462 inherited monitor tests and 9 Luna tests reported passing; arm64 APK/native staging and lint. Does not exercise physical Android radio/network permissions |
| Apple UI suite and native builds | 413 UI tests completed, one optional fixture skip, no failures. Simulator Debug, unsigned iOS Release and Catalyst Debug builds succeeded; private replay review does not prove native camera association |
| Apple Simulator / Android emulator LOCAL REPLAY | Decoding, real-image scopes, presentation and shared UI from private recorded footage. Does not connect to a camera |
| Native physical-device run | Still required for first-install Bluetooth/Local Network/Wi-Fi consent, feed startup and sustained reconnect. No phone actions were performed during this implementation review |

See the root [README](../../README.md#build-from-source) for commands. Apple uses
`just ios-generate`, `just ios-build` and `just ios-test`, with OpenCine checked
out at `../OpenCine`. Android uses `just android-check`: `:app:assembleDebug`,
`:monitor:testDebugUnitTest` and each module's `lintDebug` (the Luna adapter's tests run in
OpenCine: `cd ../OpenCine/Android && ./gradlew :insta360-luna:test`). The final [acceptance report](acceptance.md) records verification
after subsequent integration changes. The completed Apple test run is logged
privately in `.local/apple-ui-tests-final.log`.

Apple replay is selected explicitly through the DEBUG `OPENINSTA_REVIEW_INDEX`
entrypoint; Android uses a DEBUG-only `local_replay` launch flag. Private
recordings/indexes are neither committed nor shipped. Both display LOCAL
REPLAY, and neither should be cited as hardware streaming. All build/launch
review helpers select simulators explicitly, leaving the connected phone alone.

The separate real-camera Python lab remains available for authorized hardware
work. Captures, HCI/BLE logs, SSIDs/passwords, client identifiers and raw camera
images remain private. Apple saves its approval identity and Wi-Fi credentials
in Keychain. Android saves its own installation identity and holds session
keys/Wi-Fi passwords only in memory. Frame.io configuration is supplied locally
or by CI. Platform-specific implementation and review details are in
[Apple session](apple-session.md) and [Android shell](android-shell.md).
