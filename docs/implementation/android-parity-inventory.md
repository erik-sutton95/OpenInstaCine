# Android baseline inventory and extraction plan

Inspected 2026-09-11. Baseline: OpenPocketCine `9c4e7334ca4d935c5d467abecaf8f968f7927d84`, including its current working tree. This is a read-only investigation of that sibling repository; none of its existing modifications were changed. The inventory describes source evidence, not a completed Android port or a hardware-verification claim.

## Finding

The existing Android app can supply the complete Compose presentation baseline, but it is not currently a reusable monitor library. It contains 114 production Kotlin files (1,705,839 bytes), 46 Kotlin test files, 18 C++/CMake/shader files, 90 asset files, and 107 resource files. `AppModel` constructs `PocketCameraSession` directly. The published `core-api` is only 28 lines: connection phases plus `startScan()` and `disconnect()`. It does not define the camera identity or monitoring contract described aspirationally in `ANDROID.md`.

Preserve the existing screen implementation once in a shared Android library, inject a backend and brand identity, and make each brand application a thin launcher. A second copied `LiveViewScreen`, `OperatorSetup`, or assist implementation would fail the shared-engine design's success criterion even if it looked correct on day one.

Source references are relative to `/Users/eriksutton/Work/OpenPocketCine/`. The normative baseline is `AGENTS.md`, `ANDROID.md`, `docs/ARCHITECTURE.md`, `docs/PARITY.md`, and `docs/SHARED-MONITOR-ENGINE.md`.

## Operator surface inventory

| Surface | Existing implementation | Preserve for OpenInstaCine | Adapter seam / caveat |
| --- | --- | --- | --- |
| Launch and routing | `MainActivity.kt`, `AppModel.kt`, `AppPanels.kt` | Launch splash, permission flow, automatic discovery, saved-camera routing, modal panels, wake lock, immersive monitor | Inject session factory; move hard-coded app resources and title to brand identity |
| Pairing | `pairing/PairingExperience.kt`, `StartupDesign.kt`, `StartupGlyphs.kt`, `FoundCameraIdentity.kt` | Portrait and landscape cards, scan list, approval stage, Wi-Fi stage, live-start stage, diagnostics action, progress/failure presentation | Discover BE80 Luna devices and show Luna-specific instructions; no Pocket pairing token or FFF0 assumption |
| Saved cameras | `SavedCamerasExperience.kt`, `SavedCameraRecords.kt` | Saved list, reconnect, rename/remove, empty state, add camera | Per-brand storage namespace and generic camera descriptor |
| Landscape monitor | `LiveViewScreen.kt`, `LiveChrome.kt` | Feed well, complete status deck, capture strip, bottom assist rail, record well, right rail, lock, DISP 1/2, toasts, layout metrics | Neutral status/capability model; no DJI ordinal supplied as a Luna setting |
| Portrait monitor | `LivePortraitChrome.kt` | Fit/fill aspect toggle, portrait top/system bars, capture strip, rail, record options placement | Same capability gate as landscape; preserve minimum clearances |
| Editable chrome | `ChromeEditChrome.kt`, `OperatorPrefs.kt` | Per-DISP section maps, edit overlays, reset, clean-view pinned tools, return to Display settings | Shared preference schema under app-specific namespace |
| Capture popovers | `LiveControlSheets.kt` | Drum wheels, fade masks, picker anchoring, close buttons, sheet/keyboard behavior | ISO, shutter, WB/tint, format, color, focus and audio are disabled/unavailable until Luna supports them; split `CaptureLists` DJI tables from reusable picker widgets |
| Record / camera actions | `LiveChrome.kt`, `LivePortraitChrome.kt`, `LiveControlSheets.kt` | Baseline record button and options shell, confirmation presentation | No camera write until capability/command is implemented; unknown record state is not a simulated recording |
| Zoom and gimbal | `LiveZoomChrome.kt`, `GimbalCluster.kt`, `GimbalGamepad.kt`, `GamepadOperator.kt` | Geometry and accessible controls can remain in shell with unavailable state; gimbal cluster must be capability-driven | Disable camera actions for Luna initially; no DUML, D-Log2 hop, Pocket zoom stops, or Pocket stick math dispatched to Luna |
| Tracking | `LiveTrackingOverlay.kt`, `session/LiveFaceDetector.kt`, `TrackingBox.kt` | Reusable face/box rendering only if enabled by an explicit capability | Do not imply live camera AF/tracking control from local ML detection |
| Assist toolbar | `assists/LiveAssistBar.kt`, `LiveAssistTool.kt`, `AssistToolCell.kt`, `AssistGestures.kt` | LUT, PEAK, FALSE, ZEBRA, WAVE, PARADE, HISTO, VECTOR, LIGHTS, AUDIO, GUIDES, GRID, CROSS, MIRROR; tap and hold behavior | Image-based assists are shared; audio meter requires an actual audio source |
| Assist options / persistence | `LiveAssistState.kt`, `AssistOptionsPopup.kt`, `AssistGeometry.kt`, `LiveAssistLayer.kt` | Thresholds, colors, scope guides, draggable/scalable scopes, clean-view pins, persisted options | Keep scope signal colors semantic; only brand accent changes |
| Scopes | `ScopePanels.kt`, `ScopeTraceRaster.kt`, `feed/PocketScopeSampler.kt`, `LiveScopeSampleBus.kt`, `GpuOverlayBus.kt` | Histogram, parade, waveform, vectorscope, traffic lights; native-scale rulers and reusable raster sampling | Rename ownership, not algorithms; input transfer comes from backend metadata, not a camera-brand guess |
| LUT | `lut/LUTPicker.kt`, `LutCatalog.kt`, `LutExposureCompensation.kt`, `PlaybackLutColor.kt`; `feed/LutLookResolver.kt` | Picker categories, import, favorites, intensity/exposure, split comparison, playback independence | Remove DJI built-ins from Luna catalog; shared creative/imported cubes work; Auto follows confirmed Rec.709 preview rather than applying D-Log normalization |
| Operator Setup | `OperatorSetup.kt`, `settings/SettingsComponents.kt` | Seven tabs: Link, Sharing, View Assist, Controls, Display, Storage, System; complete row/chrome/help layout | Camera controls unavailable; manufacturer/app links injected; Sharing is already a Coming soon surface on Android baseline |
| Media browser | `media/MediaLibraryScreen.kt`, `MediaLibraryCells.kt`, `MediaChrome.kt` | Categories, filter/sort, list/grid, selection, item menus, empty/cache states | Neutral catalog backend; do not show fabricated clips or issue Pocket media commands |
| Playback | `MediaPlaybackScreens.kt`, `MediaPlaybackGlass.kt`, `PlaybackFeedView.kt`, `PlaybackGestures.kt`, `PlaybackZoom.kt`, `PlaybackAudio.kt` | Transport, next/previous, audio, gestures, separate assist rail, grading on proxy, selected clips | Local compatible media can use existing player; Luna camera catalog/download pending |
| Media storage / delivery | `MediaCache.kt`, `MediaTransfer.kt`, `MediaShare.kt`, `MediaDeliveryPopup.kt`, `ConformPreview.kt` | Cache progress, original/proxy distinction, export UI, system Share/Photos, conform preview | Camera path resolution and catalog protocol in adapter; directory names follow identity; Frame.io OAuth/export bake is an iOS-only baseline exception, not existing Android functionality |
| Recovery / diagnostics | `MonitorRecoveryOverlay.kt`, `diagnostics/DiagnosticCenter.kt`, `PrivacyRedactor.kt` | Held-frame recovery overlay, explicit failure, share diagnostics, private local journal | Luna recovery policy owns UCD2 heartbeat/reconnect; Pocket UDP enable-once policy is inapplicable |
| Theme / icons | `Theme.kt`, `GlassChrome.kt`, `glass/*`, `OpcIcon.kt`, `LegalScreens.kt` | Dark neutrals, Sora titles, IBM Plex body, mono camera readouts, Lucide glyphs, glass fallbacks, legal pages | Inject yellow accent and app identity; preserve fonts/licenses and neutral geometry |
| OS integration | `ImmersiveSystemBars.kt`, `OperatorHaptics.kt`, `PhoneBatteryReadout.kt` | System bar lifecycle, phone power chip, haptics preference, overlay behavior | Android platform library responsibilities, independent of camera protocol |

## Concrete dependency obstacles

1. `AppModel.kt:32` creates the 4,150-line `PocketCameraSession`. Almost every screen reaches through `model.session`, including decoder, status, camera model, focus/gimbal state, recovery and media. Replacing only `core-api/CameraSession` does not make those screens backend-neutral.
2. `session/Models.kt` mixes `CameraModel`, `FoundCamera`, `CameraStatus`, `DumlFrame`, and `DumlCodec`. `CameraModel` embeds UDP 9004, Pocket pairing token, live-view receiver, DJI zoom stops, and name-based policy. Split display models from Osmo wire data. Unknown camera fields should remain absent/unavailable; they must not adopt Pocket defaults.
3. `LiveControlSheets.kt` mixes generic picker widgets with DJI capture catalogs, raw color/exposure values and ISO-hop behavior. Move command/catalog policy into `OsmoAdapter`; keep display widgets shared. The Luna MVP need not implement those commands.
4. `media/MediaSessionLink.kt` is not a generic media backend. It exposes `sendDuml`, raw `DumlFrame`, and reflects into `PocketCameraSession`'s private `datalink`. `MediaManifest` parses Pocket records and `MediaModels` includes DJI HTTP storage rules. Replace that dependency with list/download/thumbnail/delete capability methods, generic clip descriptors and progress. Keep its cache/player/chrome in shared ownership.
5. `HevcDecoder.decode()` immediately rejects frames if `SwiftCore.isAvailable` is false; it calls JNI for NAL types, keyframe classification and CSD. A Kotlin Luna TCP client alone therefore cannot feed the existing decoder without the shared media JNI product or a consciously extracted decoder parser. Do not silently remove JNI and expect the screen to work.
6. `FeedEffectsRenderPlanFactory` uses JNI for imported/creative LUT cubes, false-color paint/weight and assist scalars. `LutCatalog` validates imports through JNI. `ConformPreview` uses JNI in production with a Kotlin test fallback. These functions belong to shared monitor/media modules, not a required Osmo camera adapter.
7. `SwiftCoreJNI.swift` hard-codes `Java_com_opencapture_openinstacine_monitor_bridge_SwiftCore_*` exported names, and Kotlin loads `OpenInstaCineAndroid`. The Vulkan C++ JNI names similarly match the existing class package. Changing `applicationId` is safe; blindly renaming Kotlin package declarations without coordinated JNI exports breaks native loading. Preserve an internal compatibility package temporarily or rename both sides atomically.
8. `ANDROID.md` says the Swift facade owns the Android session, but current implementation keeps BLE/Wi-Fi/socket orchestration in Kotlin `PocketCameraSession`, `BleLink`, `CameraApJoiner` and `DatalinkDriver`. The Swift facade supplies pure wire/policy helpers. Build the new design from current source, not the older documentation claim.

## Buildable shared-library shape

```text
Packages/MonitorAndroid/
  monitor-api/       # generic capabilities, identity, status, encoded frames, media contracts
  monitor-ui/        # existing Compose screens/model, resources, preference policy
  monitor-platform/  # MediaCodec, Vulkan/GLES, haptics, diagnostics, storage, OS integration
  monitor-native/    # Swift monitor JNI facade + runtime staging; no DUML dependency
Adapters/Insta360/
  Android/           # Android GATT/Wi-Fi/TCP I/O driving portable UCD2 logic
Adapters/OsmoDUML/
  Android/           # existing Pocket session + wire/media adapter
Apps/Android/app/     # thin OpenInstaCine activity, branding, package ID, launch assets
```

Gradle included projects can point to these local directories; a dedicated external shared checkout can instead be included with a strictly pinned revision. `monitor-ui` and `monitor-platform` are Android libraries (`com.android.library`) because they own resources/native code; `monitor-api` can remain Kotlin/JVM. Preserve the version catalog and wrapper initially. Move source ownership once, then have both thin brand apps depend on it. A source extraction manifest should record baseline commit, original path, new owner and license.

For the first compilable extraction it is practical to keep UI and platform implementation in one `monitor-android` Android library and split further only once the backend seam is proven. This avoids broad `internal` visibility churn across many files. The thin app can use a stable public `MonitorHostActivity`/`MonitorApp` entry point plus `BrandIdentity` and `CameraBackend` factory. Package identity, prefs namespace, legal copy, wordmark, icons, accent, diagnostics name and export folder come from that identity. It must not contain copied screen bodies.

The backend must expose the data actually consumed today: observable phase/error/discovery/status/recovery; camera identity and capabilities; lifecycle and connection actions; encoded HEVC frames with timing/format metadata; optional control actions; and optional media operations. The shared Android runtime owns the decoder and gives the UI presentation statistics. Avoid making the portable core depend on Compose `State`, Android `Surface`, or `Context`.

A Luna feed travels `BE80 GATT → encrypted credential read → WifiNetworkSpecifier camera network → TCP 192.168.42.1:6666 UCD2 → validated video subtype 0x20 → HEVC Annex-B → shared MediaCodec → existing Vulkan/GLES/present/scopes → unchanged monitor chrome`. Decoder output surface should be ready before starting preview. The verified Mac transport packet and authorization order belong in the Luna adapter, not Compose. Camera settings and record remain capability-disabled without optimistic writes. Cached library shell remains usable even when the camera-media capability is absent.

The shared-engine migration document orders Delivery/Media before scopes/layout and backend wrappers. Follow that order within the extraction, and record any deliberately staged migration gap; merely publishing a new OpenInstaCine copy does not migrate OpenPocketCine/OpenZCine.

## Yellow identity audit

The blue accent is duplicated today in `Theme.kt` (`BrandColors.accent`, `accentSoft`, `LiveDesign.accent`, `accentDim`), `pairing/StartupDesign.kt` (`StartupColors.accent`, `backdropGlow`), resource color `opc_gold`, and launch/image assets. Replace their ownership with one injected palette. A suitable initial yellow is `#FFD500`, described as an inspired app color rather than an official brand specification. Keep dark-on-yellow active fills, subdued yellow washes, the existing charcoal neutrals, red recording/destructive states, green connection success, and the semantic false-color/scope palettes. Do not globally replace every blue pixel: vector/scopes and focus aids carry signal meaning.

Retain resource/font licenses: Sora and IBM Plex OFL assets, Lucide license/source metadata. Camera-specific DJI LUT assets belong to the Osmo adapter/catalog rather than the common Luna resource bundle.

## Local build readiness (inspected; no build run)

| Component | Observed local state |
| --- | --- |
| Gradle | Wrapper `9.7.1`; cached distributions `9.7.1` and `9.6.1` |
| Android Gradle plugin | Baseline `9.4.0`, already in local Maven/Gradle cache |
| Kotlin / Compose plugin | `2.4.10`, already cached |
| Java | `/opt/homebrew/opt/openjdk/bin/java`, OpenJDK `26.0.1`; project source/target JVM 17 |
| Android SDK | `/opt/homebrew/share/android-commandlinetools`; platform 36, build-tools 36.0.0 |
| Native tools | NDK `28.2.13676358`, CMake `3.22.1`; Vulkan shaders use NDK `glslc` |
| Swift | `/Users/eriksutton/Library/Developer/Toolchains/swift-6.3.3-RELEASE.xctoolchain/usr/bin/swift` present |
| Swift Android SDK | `swift-6.3.3-RELEASE_android` installed/configured for `aarch64-unknown-linux-android29` |
| ABI | Existing app supports arm64-v8a only; minSdk 29, target/compileSdk 36 |
| Libraries | Compose BOM `2026.08.00`, coroutines `1.11.0`, Media3 `1.11.0`, OkHttp `5.5.0`, Kyant backdrop `2.0.1`, shapes `1.2.1`, ML Kit face `16.1.7` |
| SDK metadata caveat | Baseline disables only `check*AarMetadata` because current Compose/core artifacts request compileSdk 37 while installed SDK is 36; retain this documented build workaround if using the same catalog |
| Existing outputs | No `Apps/Android/app/build/generated/swiftCore/jniLibs/arm64-v8a` and no app build outputs in this Pocket checkout |
| Device | `adb devices -l` returned no attached device |
| Emulator images | Android 28 and 35 system-image directories present; 28 is below app minimum and cannot verify this app |

Existing stage task invokes `scripts/android-stage-swift-core.sh`, cross-compiles the Swift dynamic product, strips it, recursively stages the complete runtime `.so` dependency closure, and writes generated jniLibs. New shared native products must retain this runtime closure and generated-output discipline. Reusing ignored stale `.so` files is not a valid build approach.

## Ownership decomposition

| Independent owner | Files / responsibility | Must coordinate |
| --- | --- | --- |
| Shared model / contracts | `monitor-api`, shared `AppModel`, capability/status/identity/media descriptors | Publish contract before screen and adapter edits |
| Android shell extraction | Existing root Compose screens, pairing presentation, setup, prefs, resources, theme | Own all shared UI package moves; avoid conflicting global replacements |
| Media extraction | Generic cache/browser/player/delivery; isolate `MediaSessionLink`, manifest and HTTP adapters | Share clip/media interface with contract owner |
| GPU / assists extraction | `assists`, `feed`, shared decoder, C++/shaders, LUT UI/packing facade | Keep LUT colors/metadata neutral and coordinate native names |
| Luna Android adapter | BE80 GATT, authorization, Wi-Fi join/network-bound TCP, UCD2 video, lifecycle | Consume stable API; no direct Compose or screen edits |
| Osmo adapter / sibling wiring | Existing Pocket BLE/DUML/session/model/wire/media code and thin launcher | Preserve all current user changes and existing physical behavior |
| Build / integration | Gradle module graph, stage script/native products, minimal app manifest, APK and tests | Sole owner of shared build files and exports |

With four available concurrent agents, run contracts/build locally while shell, media/assists, and adapter owners work in bounded directories; serialize integration and final verification. A separate agent per tiny feature would create conflicts in monolithic `LiveViewScreen`/`OperatorSetup` files and would not accelerate this extraction.

## Verification checklist

- Build the Android shared library and OpenInstaCine debug APK, run moved JVM tests and lint. Keep baseline metrics tests rather than recreating dozens of assertions.
- Verify ABI/native library loading, JNI registration and imported LUT/false-color execution; pure Kotlin screenshot success cannot prove these.
- Render/start on a supported emulator for startup, settings, both orientations, empty media, all assist dialogs, chrome editor and unavailable camera actions.
- Compare screenshots to baseline layouts. Record existing Android/iOS exceptions (Frame.io/bake, head tracking, OS APIs), not new accidental omissions.
- Use a fixture or explicit development preview source to verify renderer/scopes without a powered camera; the UI must clearly identify that mode.
- Physical Android BLE, Wi-Fi authorization, HEVC first frame, overlay return and reconnect remain unverified until an Android device is attached. No attached device was available during this investigation.

## Complete production Kotlin file index

All paths below are under `Apps/Android/app/src/main/kotlin/com/opencapture/openinstacine/monitor/` in the baseline. Line counts describe the inspected working tree and are supplied for ownership planning.

### `root/` (23 files)

| File | Lines |
| --- | ---: |
| `AppModel.kt` | 389 |
| `AppPanels.kt` | 31 |
| `ChromeEditChrome.kt` | 291 |
| `GamepadOperator.kt` | 58 |
| `GimbalCluster.kt` | 160 |
| `GimbalGamepad.kt` | 334 |
| `GlassChrome.kt` | 313 |
| `ImmersiveSystemBars.kt` | 147 |
| `LegalScreens.kt` | 170 |
| `LiveChrome.kt` | 2,134 |
| `LiveControlSheets.kt` | 2,184 |
| `LivePortraitChrome.kt` | 874 |
| `LiveTrackingOverlay.kt` | 183 |
| `LiveViewScreen.kt` | 1,659 |
| `LiveZoomChrome.kt` | 319 |
| `MainActivity.kt` | 336 |
| `MonitorRecoveryOverlay.kt` | 99 |
| `OpcIcon.kt` | 107 |
| `OperatorHaptics.kt` | 108 |
| `OperatorPrefs.kt` | 423 |
| `OperatorSetup.kt` | 1,660 |
| `PhoneBatteryReadout.kt` | 102 |
| `Theme.kt` | 173 |

### `assists/` (10 files)

| File | Lines |
| --- | ---: |
| `AssistGeometry.kt` | 801 |
| `AssistGestures.kt` | 79 |
| `AssistOptionsPopup.kt` | 546 |
| `AssistToolCell.kt` | 128 |
| `LiveAssistBar.kt` | 213 |
| `LiveAssistLayer.kt` | 510 |
| `LiveAssistState.kt` | 625 |
| `LiveAssistTool.kt` | 311 |
| `ScopePanels.kt` | 897 |
| `ScopeTraceRaster.kt` | 294 |

### `bridge/` (1 files)

| File | Lines |
| --- | ---: |
| `SwiftCore.kt` | 247 |

### `diagnostics/` (2 files)

| File | Lines |
| --- | ---: |
| `DiagnosticCenter.kt` | 211 |
| `PrivacyRedactor.kt` | 55 |

### `feed/` (21 files)

| File | Lines |
| --- | ---: |
| `FacePriorityExposure.kt` | 114 |
| `FeedEffectsCube.kt` | 57 |
| `FeedEffectsCubeAtlas.kt` | 59 |
| `FeedEffectsGlProgram.kt` | 294 |
| `FeedEffectsRenderPlan.kt` | 305 |
| `FeedPresentPolicy.kt` | 130 |
| `FeedUpscale.kt` | 51 |
| `GpuLiveLayout.kt` | 161 |
| `GpuOverlayBus.kt` | 56 |
| `LiveColorScience.kt` | 618 |
| `LiveFeedEffectsSession.kt` | 535 |
| `LiveFeedPlan.kt` | 118 |
| `LiveScopeSampleBus.kt` | 88 |
| `LiveVulkanSession.kt` | 564 |
| `LutLookResolver.kt` | 120 |
| `OesCopyGlProgram.kt` | 87 |
| `OpcVulkan.kt` | 105 |
| `PlaybackLookEffect.kt` | 58 |
| `PocketScopeSampler.kt` | 364 |
| `VulkanPresentGate.kt` | 72 |
| `VulkanWindowAttach.kt` | 25 |

### `glass/` (3 files)

| File | Lines |
| --- | ---: |
| `DampedDragAnimation.kt` | 154 |
| `DragGestureInspector.kt` | 97 |
| `LiquidSlider.kt` | 271 |

### `lut/` (5 files)

| File | Lines |
| --- | ---: |
| `ClipColorProfile.kt` | 202 |
| `LUTPicker.kt` | 857 |
| `LutCatalog.kt` | 227 |
| `LutExposureCompensation.kt` | 37 |
| `PlaybackLutColor.kt` | 31 |

### `media/` (19 files)

| File | Lines |
| --- | ---: |
| `ConformPreview.kt` | 265 |
| `MediaCache.kt` | 204 |
| `MediaChrome.kt` | 574 |
| `MediaDeliveryPopup.kt` | 665 |
| `MediaLibraryCells.kt` | 457 |
| `MediaLibraryController.kt` | 606 |
| `MediaLibraryScreen.kt` | 928 |
| `MediaLiveResume.kt` | 64 |
| `MediaManifest.kt` | 487 |
| `MediaModels.kt` | 534 |
| `MediaPlaybackGlass.kt` | 262 |
| `MediaPlaybackScreens.kt` | 1,257 |
| `MediaSessionLink.kt` | 148 |
| `MediaShare.kt` | 73 |
| `MediaTransfer.kt` | 281 |
| `PlaybackAudio.kt` | 302 |
| `PlaybackFeedView.kt` | 109 |
| `PlaybackGestures.kt` | 265 |
| `PlaybackZoom.kt` | 68 |

### `pairing/` (10 files)

| File | Lines |
| --- | ---: |
| `CameraApJoiner.kt` | 416 |
| `CameraWifiCredentialStore.kt` | 112 |
| `CameraWifiResolution.kt` | 54 |
| `FoundCameraIdentity.kt` | 42 |
| `PairingExperience.kt` | 468 |
| `SavedCameraRecords.kt` | 121 |
| `SavedCamerasExperience.kt` | 297 |
| `StartupDesign.kt` | 752 |
| `StartupGlyphs.kt` | 51 |
| `WifiLowLatencyLock.kt` | 50 |

### `session/` (19 files)

| File | Lines |
| --- | ---: |
| `BleLink.kt` | 478 |
| `CamFov.kt` | 223 |
| `CameraCommands.kt` | 1,077 |
| `ControlHud.kt` | 93 |
| `DatalinkDriver.kt` | 861 |
| `EncoderPresentPath.kt` | 48 |
| `GimbalLimitWatch.kt` | 96 |
| `HevcDecoder.kt` | 606 |
| `LiveFaceDetector.kt` | 152 |
| `LiveHevcCodec.kt` | 31 |
| `LivePictureSps.kt` | 193 |
| `LiveViewPresentTiming.kt` | 24 |
| `LocalVPNFilter.kt` | 58 |
| `Models.kt` | 672 |
| `PocketCameraSession.kt` | 4,150 |
| `SessionRecovery.kt` | 158 |
| `StatusExtras.kt` | 246 |
| `TrackingBox.kt` | 519 |
| `VideoFormat.kt` | 429 |

### `settings/` (1 files)

| File | Lines |
| --- | ---: |
| `SettingsComponents.kt` | 1,034 |

The additional Kotlin API is `core-api/src/main/kotlin/com/opencapture/openinstacine/monitor/core/CameraSession.kt` (28 lines). Swift JNI support is `Sources/OpenInstaCineAndroidFacade/{AndroidSessionWire,FeedEffectsWire,LUTLibraryWire,SwiftCoreJNI}.swift` plus `Sources/CJNI`. Native renderer ownership includes `app/src/main/cpp/{CMakeLists.txt,embed_spv.cmake,opc_vulkan.cpp,shaders/*}` and `app/src/main/assets/shaders/*`.
