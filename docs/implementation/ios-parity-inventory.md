# OpenPocketCine iOS shell extraction inventory

Date: 2026-09-11. Read-only baseline: `/Users/eriksutton/Work/OpenPocketCine`, commit `9c4e7334ca4d935c5d467abecaf8f968f7927d84`. The SwiftUI source tree has no working-tree modifications; the repository has unrelated user changes to instructions, release tooling, and documentation. Those changes must remain intact. This inventory reads the current `AGENTS.md`, `docs/ARCHITECTURE.md`, `docs/PARITY.md`, `docs/UX.md`, and `docs/SHARED-MONITOR-ENGINE.md`.

## Recommendation and boundaries

The reliable 1:1 route is a **mechanical extraction of the existing native shell**, with its existing internal `AppModel` and `CameraSession`-shaped presentation facade preserved initially. Place that shell in one shared target, expose only a root view and configuration/backend initializer, and adapt Luna behind the facade. A new set of lookalike SwiftUI screens would omit significant behavior and violate the shared-engine contract.

The baseline consists of 42,747 lines across 87 Swift source files in the iOS application directory. The most coupled pieces are `CameraSession.swift` (4,691 lines), `CameraMedia.swift` (1,242), `LiveAssists.swift` (1,799), `MediaPlayer.swift` (1,945), and `MediaLibraryStub.swift` (1,641). Despite its filename, `MediaLibraryStub.swift` is a complete media shell, not a placeholder to replace.

Retaining a legacy-shaped facade is practical; retaining the existing implementation unchanged is not. The old session constructs `BleLink` and `DatalinkDriver`, emits Osmo commands, applies Pocket model rules, drives watchdog recovery, and owns media-transfer policy. Luna must not run any of those Osmo wire operations. The shared facade can continue exposing old view-facing names while dispatching to a portable injected backend and owning shared decoded-frame/presentation state. Legacy type names are migration debt; legacy wire behavior in shared UI is an architectural defect.

The minimum shareable extraction includes views, assist/scope state, settings, playback, delivery, and the iOS rendering implementation. It cannot comprise just files with `View` in their name. UIKit/VideoToolbox/Metal support belongs in the shared **iOS platform target**, not the Foundation-only core. Per-brand app targets retain only entrypoint, identity/assets, entitlements, configuration, and adapter construction.

This overnight scope is the full shell plus live Luna feed. Camera settings, recording, gimbal/zoom/focus, media catalog/transfer, and Luna audio remain capability-disabled until separately proven. Preserve their shared components and recognizable placement, show unknown values as unknown, and communicate unsupported actions clearly. Do not optimistically mutate camera state or show a fake recording state. The existing Sharing page already says “Coming soon...”; parity does not require inventing a watcher relay.

## Exact shell surfaces

All source paths below are relative to `ios/OpenPocketCine/` in the baseline.

| Surface | Files | Behavior to carry over |
| --- | --- | --- |
| App root and lifecycle | `OpenPocketCineApp.swift`, `AppRoot.swift` | Dark root, launch splash, first-run versus saved-camera routing, live overlay routing, transitions, idle timer, session foreground/background callbacks, iPad status-bar hiding, 550 ms live-chrome tap suppression after connection. |
| Brand and typography | `Branding.swift`, `StartupChrome.swift`, `DesignShared.swift`, `LiveType.swift` | Logo/monogram, launch animation, charcoal palette, Sora titles, IBM Plex Sans labels, SF Mono camera values, consistent 16 pt panel radius, minimum 44 pt tap targets, iOS 26 Liquid Glass and older-iOS opaque fallback. |
| First-run connection | `ConnectionSetupView.swift`, `StartupChrome.swift` | Portrait stacked header/progress and wide two-column wizard; discover, approve on camera, join Wi-Fi, open feed; camera rows; prepare/checklist/help cards; error/retry/cancel; Your cameras escape; Share Diagnostics always reachable. Brand/device names and transport copy must be injected. |
| Saved cameras | `SavedCamerasView.swift`, `SavedCameraStore.swift` | Saved row availability, reconnect, nickname editing, forget, Pair new camera, empty-state transition. Credentials remain in platform secure storage rather than saved row data. |
| Live canvas | `LiveViewScreen.swift`, `LiveMonitorLayout.swift`, `LivePortraitModules.swift` | Explicit feed well with independent physical-screen chrome; safe areas and landscape orientations; portrait fit/fill choice and vertical-camera pillarbox; no rail nested inside video; same transitions, panels and anchors. |
| Portrait system/top bar | `LivePortraitSystemBar.swift`, `LivePortraitTopBar.swift`, `LivePortraitModules.swift` | Portrait-specific system/status modules and positioning; phone state remains available even when camera telemetry is unknown. |
| Feed presentation | `HevcDecoder.swift`, `VideoView.swift`, `FeedWorkingRaster.swift`, `FeedPresentScaler.swift`, `FeedUpscale.swift`, `FeedSuperResolution.swift` | HEVC/AVC Annex-B decode, single hardware decoder ownership, last-frame hold, format/orientation changes, drawable readiness, identity/processed-layer handoff, supported-device upscaler choices. |
| Top status/control menus | `LiveTopChrome.swift`, `LiveBatteryCluster.swift` | REC/standby, time readout, format, color, storage, measured live FPS/link bars, camera/phone battery cluster; anchored menus and fixed typography/widths. Capture metadata must not be synthesized from preview raster/frame rate. |
| Assist toolbar | `LiveAssistBar.swift`, `LiveAssists.swift`, `Assists/AssistLongPressChrome.swift` | Ordered tools, grouped audio trailing section, tap-to-toggle, long-press anchored options, help, keyboard avoidance, state persistence, clean-view pins. |
| Image assists | `Assists/LUTAssist.swift`, `Assists/PeakingAssist.swift`, `Assists/FalseColorAssist.swift`, `Assists/ZebraAssist.swift`, `LiveMonitorFx.swift`, `LiveMonitorLooks.swift` | LUT/import/exposure and split comparison; peaking color/sensitivity; false-color scale/reference; independent highlight and midtone zebra thresholds/colors. Preserve correct Rec.709 transfer for Luna preview. |
| Scopes | `LiveScopes.swift`, `LiveFrameSample.swift`, `ScopeTraceMetalView.swift`, `Assists/WaveformAssist.swift`, `Assists/ParadeAssist.swift`, `Assists/HistogramAssist.swift`, `Assists/VectorscopeAssist.swift`, `Assists/TrafficLightsAssist.swift` | Real decoded-image sampling and shared frame analysis, movable scope plates, sizing/persistence, trace rendering, options and reference displays, traffic-light clipping/crush compensation. |
| Overlay assists | `Assists/GuidesAssist.swift`, `Assists/GridAssist.swift`, `Assists/CrosshairAssist.swift`, `Assists/MirrorAssist.swift`, `Assists/AudioAssist.swift`, `LiveOverlaySlots.swift` | Multiple guide aspect ratios/families and mask, thirds/phi/diagonal grid, crosshair, mirror, audio meter overlay, overlay positioning. Luna audio input is not yet connected; no simulated levels. |
| DISP and chrome editor | `LiveDispToggle.swift`, `ChromeEditChrome.swift`, `AppSettings.swift`, `LiveViewScreen.swift` | DISP 1/2, directional feed swipes, independent chrome visibility, edit eyes mounted on actual monitor elements, Done returns to the correct Display section, settings escape if hidden in both modes, clean-view assist pins independent of armed state. |
| Interface lock | `LiveLockButton.swift`, `LiveViewScreen.swift` | Lock disables capture interactions, closes open pickers, remounts lock while locked even in clean view. Does not alter feed or analysis state. |
| Camera value strip and pickers | `LiveCameraControlBar.swift`, `CaptureControlSheets.swift` | ISO, shutter/EV, exposure mode, WB, focus, audio; anchored pickers, drum wheels, auto/manual state and number fields. Keep shell; Luna writes disabled. |
| Recording | `LiveRecordButton.swift`, `LiveViewScreen.swift`, `LiveTopChrome.swift` | Side-rail lamp, bottom action-sheet confirmation, tally/bezel overlay and top REC/readout. Luna cannot trigger recording in this milestone. |
| Zoom/focus/tracking | `LiveZoomControls.swift`, `LiveFaceAF.swift`, `LiveOverlaySlots.swift` | Pinch well also hosts DISP gestures; zoom chip, focus tap, hold-drag track box, reset/cancel brackets. Disable camera gestures without accidentally disabling DISP swipes. |
| Gimbal and auxiliary inputs | `LiveGimbalStick.swift`, `GimbalGamepad.swift`, `HeadphoneMotion.swift`, `LiveHeadTrackAxisDials.swift` | Stick, recenter/flip, sensitivity, gamepad detection/map/limit rumble, optional head tracking/calibration. Keep reusable view/input components; do not attach active camera-command drivers for unsupported Luna capabilities. |
| Recovery/warmup | `MonitorRecovery.swift`, `LiveViewScreen.swift` | Waiting plate until actual picture, bounded reconnect card, held last frame under recovery, retry, exit to operator menu. A connected socket is insufficient to declare a visible live feed. |
| Operator setup container | `SettingsRootView.swift`, `AppSettings.swift` | Seven tabs; wide rail and narrow strip; scroll cues; help popovers; consistent cards, resets, switches, segmented controls, number-pad Done; live overlay keeps the live pipeline mounted. |
| Media library | `MediaLibraryStub.swift` | Category tabs, grid/list and thumbnail sizes, favorites, sort, filters by format/resolution/date, cached/offline grades, listing/download progress, selection mode, share/delete flows, photo/video cell variants, player launch. Empty capability-aware Luna catalog should retain this one shared screen. |
| Media player | `MediaPlayer.swift`, `PlaybackFeed.swift`, `PlaybackEffects.swift`, `PlaybackAudio.swift`, `ClipColorProfileIO.swift` | Previous/next, play/pause/end/restart, scrub/frame-scrub, zoom/pan, clean/chrome swipe, mute/audio, conform preview, cached/proxy/source choice, independent playback assists, LUT ownership across clips, download/share/delete, loading/error/toasts. |
| Delivery | `MediaDelivery.swift`, `MediaDeliveryOverlay.swift`, `MediaDeliveryPopup.swift`, `Frameio/*.swift` | Persistent navigation-independent coordinator, destination popup, system share/Photos, LUT bake/export, Frame.io OAuth PKCE/sign-in and upload, progress/cancel/result, explicit internet-hop consent and camera rejoin. No credentials means Frame.io “Not configured”. |
| Cache/catalog orchestration | `CameraMedia.swift` | Mixed concern requiring a seam: generic local cache, color metadata/favorites/catalog persistence and HTTP downloader are reusable; DUML browse/enter-playback/file semantics stay Osmo-specific. |
| Diagnostics and legal | `DiagnosticCenter.swift`, `ControlLiveLog.swift`, `LegalScreens.swift`, `LocalVPNProbe.swift` | Redacted local diagnostics/share, lifecycle/crash reports, screenshot copy for TestFlight, about/privacy/license/notices/help links, VPN-aware join/first-picture help. Preserve privacy behavior while injecting product identity. |
| Icon/resource system | `OpcIcon.swift`, `LucideSVG.swift`, `Resources/Icons/`, `Resources/Fonts/` | Existing Lucide catalog, custom zebra/battery/Frame.io marks, font resources and licenses. Do not replace with an unrelated SF Symbol theme. |

### Assist set and fine behavior

The baseline live order is LUT, PEAK, FALSE, ZEBRA, WAVE, PARADE, HISTO, VECTOR, LIGHTS, GUIDES, GRID, CROSS, MIRROR, followed by AUDIO in its own trailing section. `LiveAssistTool` also contains LEVEL, EV, DE-SQ, PLAY and MAG, but LEVEL/DE-SQ are omitted in Pocket, EV/PLAY are photography-only, and MAG is retired. Do not make all enum cases visible accidentally during extraction.

`LiveAssistState` holds separate armed state and visibility: DISP 2 filters through `cleanViewPinnedTools`; it does not disable armed assists. Playback has `playbackVisibleTools` separately. The shared graphics pipeline must keep this behavior. LUT is enabled by default in the baseline with `.djiAuto`; that is **not a safe Luna default**. Luna's observed preview is Rec.709, not DJI D-Log or D-Log2. Provide an identity/Rec.709 default and capability-driven source selection while keeping user-imported and creative look workflows.

### Seven Operator Setup tabs

| Tab | Every current row/section |
| --- | --- |
| Link | Link health; Connection: Current Transport, Phase, joined Camera Wi-Fi; Processing: Feed Upscaler when supported; Your cameras rows or Saved: None. |
| Sharing | “Coming soon...” placeholder. |
| View Assist | Resettable False Color, Zebra, Waveform, Parade, Histogram, Vectorscope, Peaking, Traffic Lights option cards; LUT Look readout and Choose look. |
| Controls | Record Confirmation; Haptics; Head Tracking (Experimental); Joystick Sensitivity; Gamepad connected state; Keep Screen Awake. Capability-disable relevant camera input rows. |
| Display | Expandable DISP 1 and DISP 2 with per-mode Reset; Edit view on connected monitor; offline toggles; DISP 2 view-assist pin grid. |
| Storage | Frame.io account/configuration; Full Resolution Caching; Local Media Cache size; Clear Cache confirmation. |
| System | Help & Feedback: Support, Share Diagnostics, Report a Problem, Request a Feature; Project & Legal: Source Code, Privacy, Terms, Licenses, NOTICE; App Information: Theme, Protocol Implementation, App Version. |

The complete configurable chrome sections are: status bar, tool bar, camera values, lock button, batteries, REC readout, timecode, format, color, storage, FPS, rail record, rail media, rail settings, zoom chip, gimbal stick, focus box. Preserve both the live editor and offline settings fallback.

## Concrete seams and implementation order

1. **Extract reusable media/delivery support first** into a shared package/target, keeping the current files and behavior. Split `CameraMedia`'s transport-driven extension from its local cache/download helpers. The root's internet-hop methods must call adapter/platform join hooks, not `WiFiJoiner.isCameraPathReady()` hardcoded to the Pocket subnet. Do not duplicate Frame.io code for Luna.
2. **Extract common monitor support and native UI** to one iOS target. All view types can stay internal. Expose a small public `MonitorAppRoot(configuration:backend:)` entrypoint; keep `AppModel` internal. This avoids making thousands of declarations public. Keep native render I/O in this target or a sibling iOS runtime target, not the portable core.
3. **Provide backend and capability values** in a portable module. Discovery, credential/bootstrap, network path, start/stop feed, reconnect and command support belong to the adapter. The shared facade receives state and Annex-B frames, maps backend errors to connection/recovery presentation, and forwards only supported user commands.
4. **Retain the existing view-facing facade temporarily**, replacing its concrete Osmo internals. Shared `CameraSession` can have a new name later. It owns observed state plus decoder/frame health, local lock/toasts and common media orchestration; the adapter owns UCD2 or DUML. The old `DatalinkDriver`/`BleLink` must live exclusively in the Osmo adapter/runtime.
5. **Inject theme and identity once** at app construction. Centralize `BrandColors`, `StartupColors`, and `LiveDesign` accent through the same theme. Main app supplies yellow, app display name, mark, URLs, legal brand names, credential namespace, diagnostics subsystem and OAuth config. Do not use `if brand == ...` in view trees.
6. **Wire Luna decoded feed** to the existing decoder and sample bus; capability-disable unsupported camera operations. Test both ordinary playback and actual GPU assists, because scopes/looks transition decoder ownership.
7. **Make the baseline app consume the extracted source**, then migrate other brands. A vendored shared module with provenance is useful staging, but if Pocket and Z keep independent screen copies indefinitely, this is not completion of the cross-repository refactor. Record any staged migration explicitly.

### Feed adapter hookup

`HevcDecoder.decode(accessUnit: [UInt8]) -> Bool` already accepts Annex-B access units, gathers parameter sets, selects HEVC/AVC and presents. Luna's UCD2 video-body demultiplexer can deliver compatible Annex-B access units here. It is not necessary to rewrite the decoder, shader stack, scope sampling or feed views.

`LiveViewScreen.onAppear` attaches `model.frameSamples`, live effect and transfer providers. Its layout directly reads `decoder.pictureAspect` and `decoder.isVerticalPicture`. `VideoView` wires identity/processed layer hosts. `decoder.onPresentedFrame` should update first-picture/warmup and measured FPS; `onSourceFrame` supplies optional Vision analysis. `onHandoffNeedsIDR` and `onParameterSetsChanged` are generic requests but their old handlers emit Osmo enables; Luna needs its own proven recovery handling. Do not replay DUML enables.

If starting a VT decoder in the middle of a GOP requires a keyframe, starting decode/sample ownership early can avoid an unproven restart. A recovered live stream must not be torn down merely because Settings or Media covers it. `AppModel.isLive` must become true through an actual backend session, not the baseline's unconditional simulator override.

### Connection model compatibility

The current `ConnectionPhase` cases can represent Luna without wire semantics: idle, scanning, connectingGatt, pairing, awaitingApproval, readingWifiCreds, joiningWifi, openingDatalink, live, failed(message). Their comments mention DUML, but their UI progression is generic. Replace `pocketWizardStep`/copy with generic phase-to-step policy when extracting.

`FoundCamera` currently contains `id: UUID`, `name`, `model: CameraModel`, and `modelId: Int?`; UI uses model name and capabilities. `SavedCamera` adds advertised/model/display name, optional SSID and last connected time. Do not fabricate Pocket model identifiers for Luna. Introduce generic discovered/saved device descriptors or a facade compatibility projection with a neutral model. CoreBluetooth UUID remains the platform discovery identity; Luna authorization identity is a separate persistent secure-store value.

### Theme and resources

Three palettes currently repeat the cyan literal: `BrandColors.accent`, `StartupColors.accent` (including card glow), and `LiveDesign`'s private `djiSky`. Updating only `Branding.swift` misses startup and live surfaces. Use one injected accent and derive opacity variants. Suggested launch token is warm Insta360-inspired yellow `#FFCF00` on the existing `#141414`/`#0E0E0E` charcoal. Preserve semantic red recording/errors, green good/AF, scope trace colors and LUT scientific color ramps; those are not brand accents.

Resource loaders require work if SwiftPM bundles are introduced: `LUTAssist` reads `Bundle.main`; `LucideSVG` tries `Bundle(for: LucideIconBundleToken.self)` then main; `Branding` loads AppLogo from main; fonts currently rely on `UIAppFonts` in the app Info plist. Supply a shared resource bundle lookup/registration for shared fonts/icons/LUTs, retain brand logo in the app bundle, and preserve notices. Do not copy private Downloads footage into the app.

The existing Xcode project is XcodeGen-driven, iOS 17 minimum, Swift 5 language mode for shell, Swift 6 core, family iPhone/iPad, automatic signing with Hotspot Configuration entitlement. A new SwiftPM UI target in Swift 6 mode would expose concurrency errors unrelated to extraction. Explicitly preserve the shell language mode initially. The original entrypoint is only 13 lines; the new brand entrypoint should remain similarly small.

## Critical blockers / accidental regressions to avoid

| Risk | Evidence | Required response |
| --- | --- | --- |
| Direct wire objects leak through facade | `GimbalGamepad`/`HeadphoneMotion` reach `session.datalink`; `CameraMedia` extends `CameraSession` and sends DUML. | Replace with generic input/media actions; capability-disable unsupported drivers before they attach. |
| Pocket-only model/enum types in UI | `CameraStatus` uses Osmo enums; `bodyFamily`, `colorModes`, `supportsFocusMode`; saved-camera body mismatch rules; `LUTResolver` defaults. | Keep only temporary presentation-compatible values, avoid sending their raw values as Luna opcodes, extract neutral models gradually. |
| False LIVE in Simulator | `AppModel.isLive` unconditionally true under simulator; `LiveViewScreen` forces `.dLog2` and starts `SimulatorLiveFeed`. | Gate explicit demo/testing mode. Normal connection UI must remain reachable. |
| Wrong color transform | `.djiAuto` LUT default; simulator transfer forced D-Log2. | Rec.709/identity Luna default; no DJI transform on Luna preview. |
| Hidden controls retain gesture paths | Zoom pinch well also handles focus/tracking/DISP; gamepad and head motion attach on live appearance. | Gate commands individually while retaining generic monitor gestures. |
| Unsupported status masquerades as truth | Camera status default `isRecording=false`, record elapsed zero; recording resolution/FPS differ from preview raster/rate. | Show clear unknown/capability-unavailable values; no optimistic fake SETs. |
| Capability hides media screen entirely | User wants full shell; backend catalog unavailable. | Shared media UI remains reachable with accurate empty/unavailable state, common local features retained. |
| Shared UI resource lookups fail | App-bundle assumptions above. | Bundle-aware resources plus font/icon/LUT smoke tests. |
| New shared package still duplicates source | Copying complete source into each repo merely changes directory names. | Establish one canonical package source, consume it from brand targets, document versions/provenance. |
| Inaccurate support/privacy/legal links | Literal Pocket/DJI/Osmo copy in startup, settings, legal and URLs. | Brand identity configuration supplies display name, legal attribution and actual project links. |
| Copying official DJI LUTs implies Luna support | Official cube resources and DJI resolver catalog are intertwined. | Preserve licenses/provenance and gate camera-specific automatic transforms. |

## Useful baseline verification assets

Existing iOS tests cover: assist toolbar chrome, each assist's options/renderer, live monitor layout/orientation, DISP swipes and chrome-editor return, focus gestures and zoom readouts, system chrome, first connect/recovery card, fonts/icons, decoded frame sampling, format changes, upscaler and LUT present performance, media library and playback assist behavior, operator-facing copy. Reuse those tests against the extracted target instead of rebuilding a parallel assertion suite.

Priority integration evidence: (1) simulator can show startup, saved list, monitor, all seven settings tabs and media shell; (2) generic demo source and Luna use the same feed sink; (3) real Luna session gets an actual presented frame; (4) LUT/peaking/false/zebra/wave/parade/histo/vector toggles operate on its image; (5) open/close Settings/Media and DISP/edit/lock without losing feed; (6) no unsupported command touches the backend; (7) disconnect/reconnect releases sockets and decoder safely. Simulator compilation alone does not establish physical iPhone BLE/Wi-Fi operation.

## Full UI-facing CameraSession member index

The following generated index lists every session member referenced outside its implementation and media extension, matched against actual member declarations to exclude unrelated `URLSession`, `AVAudioSession`, export and playback-session calls. File names refer to the baseline. Internal implementation methods not called by views are not an adapter API requirement.

| Member | Declaration location | Consumers |
| --- | --- | --- |
| `beginMediaBrowse` | `CameraMedia.swift:513` | `AppRoot.swift`, `MediaLibraryStub.swift` |
| `bodyFamily` | `CameraSession.swift:2036` | `CaptureControlSheets.swift`, `LUTPicker.swift`, `LiveViewScreen.swift`, `MediaPlayer.swift` |
| `cacheGrade` | `CameraMedia.swift:727` | `MediaLibraryStub.swift`, `MediaPlayer.swift` |
| `cachePlaybackFile` | `CameraMedia.swift:828` | `MediaPlayer.swift` |
| `cachedSSID` | `CameraSession.swift:280` | `AppRoot.swift` |
| `canReachCameraMedia` | `CameraMedia.swift:792` | `MediaPlayer.swift` |
| `cancelSessionRecovery` | `CameraSession.swift:4013` | `AppRoot.swift` |
| `cancelSubjectTracking` | `CameraSession.swift:2253` | `LiveOverlaySlots.swift` |
| `clearMediaCache` | `CameraSession.swift:4364` | `SettingsRootView.swift` |
| `colorModes` | `CameraSession.swift:2040` | `CaptureControlSheets.swift` |
| `connect` | `CameraSession.swift:444` | `ConnectionSetupView.swift` |
| `connectedCamera` | `CameraSession.swift:41` | `AppRoot.swift`, `AppSettings.swift`, `CaptureControlSheets.swift`, `DiagnosticCenter.swift`, `LUTPicker.swift`, `LiveViewScreen.swift`, `MediaDeliveryOverlay.swift`, `MediaPlayer.swift` |
| `controlBusy` | `CameraSession.swift:144` | `LiveRecordButton.swift` |
| `controlNote` | `CameraSession.swift:146` | `AppRoot.swift`, `GimbalGamepad.swift`, `HeadphoneMotion.swift`, `LiveViewScreen.swift` |
| `currentShootingMode` | `CameraSession.swift:1058` | `CaptureControlSheets.swift`, `LiveRecordButton.swift` |
| `datalink` | `CameraSession.swift:107` | `GimbalGamepad.swift`, `HeadphoneMotion.swift` |
| `decoder` | `CameraSession.swift:341` | `LiveViewScreen.swift` |
| `deleteMediaFiles` | `CameraMedia.swift:925` | `MediaLibraryStub.swift`, `MediaPlayer.swift` |
| `dimmedFaces` | `CameraSession.swift:202` | `LiveViewScreen.swift` |
| `disconnect` | `CameraSession.swift:487` | `AppRoot.swift` |
| `download` | `CameraMedia.swift:635` | `MediaDeliveryOverlay.swift`, `MediaPlayer.swift` |
| `endGimbalStick` | `CameraSession.swift:2145` | `GimbalGamepad.swift`, `HeadphoneMotion.swift`, `LiveGimbalStick.swift` |
| `endMediaBrowse` | `CameraMedia.swift:535` | `AppRoot.swift`, `MediaLibraryStub.swift` |
| `endZoomPinch` | `CameraSession.swift:1247` | `GimbalGamepad.swift`, `LiveZoomControls.swift` |
| `ensureThumbnail` | `CameraMedia.swift:619` | `MediaLibraryStub.swift` |
| `feedRecovering` | `CameraSession.swift:140` | `LiveViewScreen.swift` |
| `fetchOriginalShotColor` | `CameraMedia.swift:684` | `MediaPlayer.swift` |
| `flipGimbal` | `CameraSession.swift:2132` | `LiveGimbalStick.swift` |
| `focusOverlay` | `CameraSession.swift:184` | `LiveViewScreen.swift` |
| `focusPoint` | `CameraSession.swift:172` | `LiveViewScreen.swift` |
| `forgetWifiCreds` | `CameraSession.swift:587` | `AppRoot.swift` |
| `found` | `CameraSession.swift:39` | `ConnectionSetupView.swift`, `SavedCamerasView.swift` |
| `gimbalLimitContact` | `CameraSession.swift:158` | `LiveViewScreen.swift` |
| `gimbalLimitPanSign` | `CameraSession.swift:159` | `LiveViewScreen.swift` |
| `gimbalLimitPulse` | `CameraSession.swift:157` | `LiveViewScreen.swift` |
| `gimbalLimitTiltSign` | `CameraSession.swift:160` | `LiveViewScreen.swift` |
| `gimbalPitchTenthDeg` | `CameraSession.swift:150` | `HeadphoneMotion.swift` |
| `gimbalPoseInvertPan` | `CameraSession.swift:155` | `HeadphoneMotion.swift` |
| `gimbalPoseViewFlip` | `CameraSession.swift:148` | `AppRoot.swift` |
| `gimbalYawTenthDeg` | `CameraSession.swift:149` | `HeadphoneMotion.swift` |
| `handleFeedTap` | `CameraSession.swift:2158` | `LiveZoomControls.swift` |
| `handleGamepadAction` | `CameraSession.swift:2257` | `GimbalGamepad.swift` |
| `hasVideoFormat` | `CameraSession.swift:51` | `AppSettings.swift` |
| `holdsMonitor` | `CameraSession.swift:134` | `AppRoot.swift` |
| `isAvailableOffline` | `CameraMedia.swift:788` | `MediaLibraryStub.swift` |
| `isBrowsingMedia` | `CameraSession.swift:167` | `GimbalGamepad.swift`, `HeadphoneMotion.swift` |
| `isDownloaded` | `CameraMedia.swift:737` | `MediaDeliveryOverlay.swift`, `MediaDeliveryPopup.swift`, `MediaPlayer.swift` |
| `isFavorite` | `CameraMedia.swift:921` | `MediaLibraryStub.swift`, `MediaPlayer.swift` |
| `isFeedWarming` | `CameraSession.swift:142` | `LiveViewScreen.swift` |
| `isFocusResetAvailable` | `CameraSession.swift:2341` | `LiveViewScreen.swift` |
| `isFormatPinActive` | `CameraSession.swift:336` | `CaptureControlSheets.swift` |
| `isLiveVideoStale` | `CameraSession.swift:228` | `HeadphoneMotion.swift` |
| `isLocked` | `CameraSession.swift:226` | `GimbalGamepad.swift`, `HeadphoneMotion.swift`, `LiveCameraControlBar.swift`, `LiveViewScreen.swift` |
| `isReconnecting` | `CameraSession.swift:130` | `AppRoot.swift` |
| `joinedSSID` | `CameraSession.swift:43` | `AppRoot.swift`, `SettingsRootView.swift` |
| `lastGimbalAttitudeDump` | `CameraSession.swift:153` | `HeadphoneMotion.swift` |
| `lastGimbalAttitudeHex` | `CameraSession.swift:152` | `HeadphoneMotion.swift` |
| `liveFPS` | `CameraSession.swift:55` | `AppSettings.swift`, `LiveTopChrome.swift` |
| `liveSignalBars` | `CameraSession.swift:57` | `AppSettings.swift`, `LiveTopChrome.swift` |
| `localPlaybackSource` | `CameraMedia.swift:760` | `MediaPlayer.swift` |
| `localProxySource` | `CameraMedia.swift:773` | `MediaPlayer.swift` |
| `localURL` | `CameraMedia.swift:679` | `MediaDeliveryOverlay.swift`, `MediaLibraryStub.swift`, `MediaPlayer.swift` |
| `mediaCacheByteCount` | `CameraSession.swift:4370` | `SettingsRootView.swift` |
| `mediaDownloadProgress` | `CameraSession.swift:168` | `MediaDeliveryOverlay.swift`, `MediaLibraryStub.swift`, `MediaPlayer.swift` |
| `mediaFetchInProgress` | `CameraSession.swift:163` | `MediaLibraryStub.swift` |
| `mediaFetchListedCount` | `CameraSession.swift:164` | `MediaLibraryStub.swift` |
| `mediaFiles` | `CameraSession.swift:162` | `MediaLibraryStub.swift` |
| `mediaNote` | `CameraSession.swift:165` | `MediaLibraryStub.swift` |
| `noteSceneBecameActive` | `CameraSession.swift:3840` | `AppRoot.swift` |
| `noteSceneBecameInactive` | `CameraSession.swift:3835` | `AppRoot.swift` |
| `phase` | `CameraSession.swift:14` | `AppRoot.swift`, `AppSettings.swift`, `ConnectionSetupView.swift`, `DiagnosticCenter.swift`, `MediaDeliveryPopup.swift`, `MediaLibraryStub.swift`, `SavedCamerasView.swift`, `SettingsRootView.swift` |
| `prepHeadTrackGimbal` | `CameraSession.swift:2106` | `HeadphoneMotion.swift` |
| `pressShutter` | `CameraSession.swift:1066` | `LiveRecordButton.swift` |
| `recenterGimbal` | `CameraSession.swift:2119` | `LiveGimbalStick.swift` |
| `reconnect` | `CameraSession.swift:433` | `AppRoot.swift` |
| `recoveryDeviceName` | `CameraSession.swift:138` | `MonitorRecovery.swift` |
| `refreshAudioState` | `CameraSession.swift:1953` | `CaptureControlSheets.swift` |
| `refreshIsoLimit` | `CameraSession.swift:1140` | `CaptureControlSheets.swift` |
| `refreshMedia` | `CameraMedia.swift:598` | `AppRoot.swift`, `MediaLibraryStub.swift` |
| `rejoinSoftAPAfterInternetHop` | `CameraSession.swift:4328` | `AppRoot.swift` |
| `rememberShotColor` | `CameraMedia.swift:723` | `MediaPlayer.swift` |
| `resetFocusPoint` | `CameraSession.swift:2336` | `LiveOverlaySlots.swift` |
| `retrySessionRecovery` | `CameraSession.swift:4007` | `MonitorRecovery.swift` |
| `sessionRecovery` | `CameraSession.swift:132` | `LiveViewScreen.swift`, `MonitorRecovery.swift` |
| `sessionRecoveryCardGraceElapsed` | `CameraSession.swift:136` | `MonitorRecovery.swift` |
| `setAudioChannel` | `CameraSession.swift:1872` | `CaptureControlSheets.swift` |
| `setColorMode` | `CameraSession.swift:2048` | `CaptureControlSheets.swift` |
| `setDirectionalAudio` | `CameraSession.swift:1916` | `CaptureControlSheets.swift` |
| `setEv` | `CameraSession.swift:1123` | `CaptureControlSheets.swift` |
| `setExpoMode` | `CameraSession.swift:1152` | `CaptureControlSheets.swift` |
| `setFacePriorityEnabled` | `CameraSession.swift:1109` | `AppRoot.swift` |
| `setFocusMode` | `CameraSession.swift:1829` | `CaptureControlSheets.swift` |
| `setFocusTrack` | `CameraSession.swift:1842` | `CaptureControlSheets.swift` |
| `setISO` | `CameraSession.swift:1757` | `CaptureControlSheets.swift` |
| `setIsoLimit` | `CameraSession.swift:1094` | `CaptureControlSheets.swift` |
| `setShootingMode` | `CameraSession.swift:1084` | `CaptureControlSheets.swift` |
| `setShutterDenom` | `CameraSession.swift:1772` | `CaptureControlSheets.swift` |
| `setVideoFormat` | `CameraSession.swift:2002` | `CaptureControlSheets.swift` |
| `setVocalBoost` | `CameraSession.swift:1888` | `CaptureControlSheets.swift` |
| `setWhiteBalanceAuto` | `CameraSession.swift:1790` | `CaptureControlSheets.swift` |
| `setWhiteBalanceCustom` | `CameraSession.swift:1795` | `CaptureControlSheets.swift` |
| `setWindNR` | `CameraSession.swift:1906` | `CaptureControlSheets.swift` |
| `setZoom` | `CameraSession.swift:1258` | `LiveZoomControls.swift` |
| `shotColor` | `CameraMedia.swift:719` | `MediaPlayer.swift` |
| `startScan` | `CameraSession.swift:397` | `AppRoot.swift`, `ConnectionSetupView.swift` |
| `startTracking` | `CameraSession.swift:2218` | `LiveZoomControls.swift` |
| `status` | `CameraSession.swift:18` | `Assists/ZebraAssist.swift`, `CaptureControlSheets.swift`, `LUTPicker.swift`, `LiveAssists.swift`, `LiveBatteryCluster.swift`, `LiveCameraControlBar.swift`, `LivePortraitSystemBar.swift`, `LivePortraitTopBar.swift`, `LiveRecordButton.swift`, `LiveScopes.swift`, `LiveTopChrome.swift`, `LiveViewScreen.swift`, `LiveZoomControls.swift`, `MediaPlayer.swift` |
| `supportsFocusMode` | `CameraSession.swift:1827` | `CaptureControlSheets.swift`, `LiveCameraControlBar.swift` |
| `supportsTapFocus` | `CameraSession.swift:1826` | `LiveViewScreen.swift` |
| `thumbnailURL` | `CameraMedia.swift:733` | `MediaLibraryStub.swift`, `MediaPlayer.swift` |
| `toggleFavorite` | `CameraMedia.swift:923` | `MediaLibraryStub.swift`, `MediaPlayer.swift` |
| `updateGimbalStick` | `CameraSession.swift:2074` | `GimbalGamepad.swift`, `HeadphoneMotion.swift`, `LiveGimbalStick.swift` |
| `updateZoomPinch` | `CameraSession.swift:1219` | `GimbalGamepad.swift`, `LiveZoomControls.swift` |
| `wantsFaceAF` | `CameraSession.swift:215` | `LiveViewScreen.swift` |
| `zoomColorHopPending` | `CameraSession.swift:316` | `GimbalGamepad.swift` |
| `zoomMax` | `CameraSession.swift:272` | `GimbalGamepad.swift` |
| `zoomOptimistic` | `CameraSession.swift:276` | `LiveZoomControls.swift` |
| `zoomPinchPreview` | `CameraSession.swift:274` | `LiveZoomControls.swift` |
| `zoomReadout` | `CameraSession.swift:1178` | `GimbalGamepad.swift`, `LiveZoomControls.swift` |
| `zoomStop` | `CameraSession.swift:266` | `LiveZoomControls.swift` |
| `zoomStops` | `CameraSession.swift:267` | `LiveZoomControls.swift` |

Total: **121 facade members** referenced by the surrounding UI/platform modules. The large number is a compatibility surface, not a recommendation to put all of these on a portable backend protocol. In particular the decoder, interface lock, layout/focus overlay state, toast, cache, and local presentation state stay above the wire adapter.

### CameraStatus fields read by shell code

| Field | Consumers |
| --- | --- |
| `audioChannel` | `CaptureControlSheets.swift`, `LiveAssists.swift`, `LiveCameraControlBar.swift` |
| `audioMeters` | `LiveAssists.swift` |
| `availableIsoIndices` | `CaptureControlSheets.swift` |
| `availableShutterDenoms` | `CaptureControlSheets.swift` |
| `availableVideoFormats` | `CaptureControlSheets.swift` |
| `batteryPercent` | `LiveBatteryCluster.swift`, `LivePortraitTopBar.swift` |
| `charging` | `LiveBatteryCluster.swift` |
| `colorMode` | `Assists/ZebraAssist.swift`, `CaptureControlSheets.swift`, `LUTPicker.swift`, `LiveAssists.swift`, `LiveTopChrome.swift`, `LiveViewScreen.swift`, `LiveZoomControls.swift`, `MediaPlayer.swift` |
| `directionalAudio` | `CaptureControlSheets.swift` |
| `evComp` | `CaptureControlSheets.swift`, `LiveCameraControlBar.swift` |
| `expoMode` | `CaptureControlSheets.swift`, `LiveCameraControlBar.swift` |
| `focusMode` | `CaptureControlSheets.swift`, `LiveCameraControlBar.swift` |
| `focusTrack` | `CaptureControlSheets.swift`, `LiveCameraControlBar.swift` |
| `fps` | `CaptureControlSheets.swift` |
| `inPlayback` | `LUTPicker.swift`, `LiveViewScreen.swift` |
| `isRecording` | `CaptureControlSheets.swift`, `LivePortraitSystemBar.swift`, `LiveRecordButton.swift`, `LiveTopChrome.swift`, `LiveViewScreen.swift`, `LiveZoomControls.swift` |
| `iso` | `CaptureControlSheets.swift`, `LiveCameraControlBar.swift` |
| `isoIndex` | `CaptureControlSheets.swift`, `LiveCameraControlBar.swift` |
| `monitorTransfer` | `Assists/ZebraAssist.swift`, `LiveViewScreen.swift` |
| `shutterDenom` | `CaptureControlSheets.swift`, `LiveCameraControlBar.swift` |
| `timecodeClock` | `LivePortraitTopBar.swift`, `LiveTopChrome.swift` |
| `videoFormat` | `CaptureControlSheets.swift` |
| `videoResolution` | `CaptureControlSheets.swift` |
| `vocalBoost` | `CaptureControlSheets.swift` |
| `whiteBalance` | `CaptureControlSheets.swift`, `LiveCameraControlBar.swift` |
| `whiteBalanceKelvin` | `CaptureControlSheets.swift`, `LiveCameraControlBar.swift` |
| `whiteBalanceTint` | `CaptureControlSheets.swift` |
| `windNR` | `CaptureControlSheets.swift` |
| `zoomFactor` | `LiveZoomControls.swift` |

### Compatible session method signatures

These are the non-private methods declared on the baseline session or its media extension, included to help a compiler-driven extraction. Methods used only by the Osmo implementation (such as media DUML waiters) belong in its adapter, not in the neutral backend.

```swift
func startScan()
func startScan(reconnect id: UUID?)
func reconnect(to id: UUID)
func connect(_ camera: FoundCamera)
func disconnect()
func forgetWifiCreds(for camera: SavedCamera)
func waitFrame( _ set: UInt8, _ cmd: UInt8, timeout: Duration = .seconds(8), consumeHold: Bool = true, send: (() -> Void)? = nil ) async throws -> Duml.Frame
func pressShutter()
func setShootingMode(_ mode: ShootingMode)
func setIsoLimit(_ limit: IsoLimit)
func setFacePriorityEnabled(_ on: Bool)
func setEv(_ ev: EvComp)
func refreshIsoLimit() async
func setFov(_ fov: FovSetting)
func setExpoMode(_ mode: ExpoMode)
func updateZoomPinch(magnification: Double)
func endZoomPinch()
func setZoom(_ factor: Double)
func setZoomSlider(_ factor: Double)
func setZoomSlew(_ value: UInt16)
func setZoomStop()
func setISO(_ index: IsoIndex)
func setShutterDenom(_ denom: Int)
func setWhiteBalanceAuto(tint: Int? = nil)
func setWhiteBalanceCustom(kelvin: Int, tint: Int)
func setFocusMode(_ mode: FocusMode)
func setFocusTrack(_ track: FocusTrackMode)
func setFocusOption(_ option: FocusOption)
func setAudioChannel(_ channel: AudioChannel)
func setVocalBoost(_ boost: VocalBoost)
func setWindNR(_ value: WindNoiseReduction)
func setDirectionalAudio(_ value: DirectionalAudio)
func refreshFocusTrack() async
func clearGlamourIfEnabled() async
func refreshAudioState() async
func setVideoFormat(resolution: VideoResolution, frameRate: VideoFrameRate)
func setColorMode(_ mode: ColorMode)
func updateGimbalStick( x: Double, y: Double, sensitivity: Int = GimbalStick.defaultSensitivity, assistMirror: Bool = false, linear: Bool = false )
func prepHeadTrackGimbal()
func recenterGimbal()
func flipGimbal()
func endGimbalStick()
func handleFeedTap(at normalized: CGPoint)
func markFocus(at normalized: CGPoint)
func startTracking(_ box: TrackingBox)
func cancelSubjectTracking()
func handleGamepadAction(_ action: GamepadOperatorAction)
func handleGamepadTrackToggle()
func noteFrameTooSmall()
func resetFocusPoint()
func startCapturedLiveView(reason: String) -> Bool
func noteSceneBecameInactive()
func noteSceneBecameActive()
func beginSessionRecovery( reason: String, trigger: SessionRecoveryTrigger = .bleDropped )
func retrySessionRecovery()
func cancelSessionRecovery(clearHoldsMonitor: Bool = true)
func sendMediaFrame(_ frame: Duml.Frame)
func rejoinSoftAPAfterInternetHop() async
func sendEnterPlayback()
func sendExitPlayback()
func awaitMediaOpcode( _ set: UInt8, _ cmd: UInt8, timeout: Duration, send: (() -> Void)? ) async throws -> Duml.Frame
func restartLiveViewAfterMedia()
func resetMediaSession()
func clearMediaCache()
func mediaCacheByteCount() -> UInt64
func beginMediaBrowse()
func endMediaBrowse()
func resumeLiveViewAfterMedia(token: Int) async
func refreshMedia()
func refreshMedia() async
func ingestMediaListFrame(_ frame: Duml.Frame)
func ensureThumbnail(for file: MediaFile) async
func download(file: MediaFile) async
func localURL(for file: MediaFile) -> URL?
func fetchOriginalShotColor(for file: MediaFile) async -> ColorMode?
func shotColor(for file: MediaFile) -> ColorMode?
func rememberShotColor(_ color: ColorMode, for file: MediaFile)
func cacheGrade(for file: MediaFile) -> MediaCacheGrade
func thumbnailURL(for file: MediaFile) -> URL?
func isDownloaded(_ file: MediaFile) -> Bool
func remotePlaybackURL(for file: MediaFile) -> URL?
func localPlaybackSource(for file: MediaFile) -> MediaPlaybackSource?
func localProxySource(for file: MediaFile) -> MediaPlaybackSource?
func isAvailableOffline(_ file: MediaFile) -> Bool
func resolvePlaybackSource(for file: MediaFile) async -> MediaPlaybackSource?
func remainingPlaybackSources( for file: MediaFile, after source: MediaPlaybackSource ) -> [MediaPlaybackSource]
func cachePlaybackFile(file: MediaFile, path: String) async throws -> URL
func deleteMedia(_ file: MediaFile)
func deleteMedia(_ file: MediaFile) async
func toggleMediaFavorite(_ file: MediaFile)
func isMediaFavorite(_ file: MediaFile) -> Bool
func isFavorite(_ file: MediaFile) -> Bool
func toggleFavorite(_ file: MediaFile)
func deleteMediaFiles(_ files: [MediaFile]) async
func persistMediaCatalog()
func loadCachedCatalogIfNeeded()
func loadMediaFavorites()
```
