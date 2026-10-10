# Android shared shell and Luna transport

Implemented 2026-09-11 from OpenPocketCine baseline `9c4e7334ca4d935c5d467abecaf8f968f7927d84`. This is a local development build; no release or store upload was performed. The sibling repositories were not modified.

## Architecture

| Module | Responsibility |
| --- | --- |
| `:app` | Thin OpenInstaCine launcher, application ID `com.opencapture.openinstacine`, brand identity and yellow `#FFCF00` accent, backend selection. |
| `:monitor` | One copy of the inherited complete Compose presentation, Android resources, MediaCodec/GLES/Vulkan presentation, Swift JNI bridge, scopes/assists, local cache and playback, settings and legal screens. Android library, not another branded application. |
| OpenCineInsta360 `insta360-shell` (was `:core-api`) | Platform-independent Kotlin `CameraBackend`, lifecycle/connection phases, discovery, capability and snapshot models, and Annex-B access-unit flow. |
| OpenCineInsta360 `insta360-luna` (was `:luna-adapter`) | Android BLE/GATT, per-installation authorization identity, UCD2 framing/crypto/protobuf, Wi-Fi network acquisition and network-bound TCP preview. No Compose dependency. |

The thin launcher installs `MonitorConfiguration` before any shared model is constructed. The presentation session consumes the injected backend's flows and feeds the same `HevcDecoder` used by all monitor tools. BLE and TCP frames never enter a Compose screen. Camera commands are not implemented in the presentation session.

`OpenInstaCineAndroid`, the JNI package namespace, and historical class names remain compatibility names so the native bridge continues to load. The root Swift package's `MonitorCore` extraction is linked into the staged JNI product. Generic model/policy migration is incremental: legacy Osmo helper, media DTO, LUT identifiers and protocol policy files remain in the inherited library for source/test compatibility, but the Luna session does not instantiate `BleLink` or `DatalinkDriver` or send DUML. Camera media remains capability-gated; its legacy API is not a validated generic media backend. OpenPocketCine and OpenZCine have not yet been changed to consume these modules.

## Shell parity

The detailed 114-file feature inventory is [android-parity-inventory.md](android-parity-inventory.md). The inherited presentation retains pairing/recent-camera screens, live/clean layouts, chrome editing, locking, local settings, LUT selection/import, peaking, false color, zebra, movable/resizable scopes, histogram/waveform/parade/vectorscope and exposure assists, composition overlays, diagnostics, media filters/sorting/layouts, cached media, playback/scrubbing and playback assists.

Startup, live controls and settings derive their accent from the injected brand. Semantic recording/error red, connection green, scope trace colors and user-selectable colors remain functional colors. Launcher/icon artwork uses the same generated yellow monitor-mark family as Apple. The app retains baseline source and third-party notices.

Luna starts with a Rec.709 identity transform. Camera LUT presents neutral Auto and the official I-Log → Rec.709 SDR conversion, injected by the thin brand app. The selected conversion carries its own input transfer for exposure baking; it never changes source scope metadata. Creative and custom categories remain available. DJI camera LUT assets are not bundled into this app. Unknown camera capture metadata displays placeholders, including REC — and unknown white balance. Audio meters explicitly say unavailable when no levels exist. Unavailable camera sheets retain their header and explanatory state without seeding fictitious format/white-balance values. Failed media-delete guards retain playback/selection. Record, zoom, gimbal, focus, exposure, format, audio controls and camera media are unavailable with explanatory copy; they do not perform guessed writes. No support/source website is invented: optional brand links show Not configured until real destinations are supplied.

## Luna connection path

1. Discover service BE80, connect BE81 write / BE82 notify, subscribe, negotiate MTU and fragment GATT writes to at most 206 bytes.
2. Read model/firmware through command 8; require the Luna Ultra identity before applying this adapter.
3. Negotiate encryption command 240 scheme 3 and command 241 P-256 exchange. Derive AES-128-GCM via ECDH/HKDF; validate the captured key-exchange success enum (1), frame CRC, authenticated header and encrypted reply expectations.
4. Authorize the app installation's own UUID through command 39. If needed, request command 86 and wait for the camera's approval notification. The initiator value follows the earlier verified bootstrap; an Android-specific alternative has not been assumed.
5. Read encrypted Wi-Fi options, hold credentials only in memory, release BLE and request camera Wi-Fi with `WifiNetworkSpecifier`.
6. Use the returned Android `Network.socketFactory` for TCP `192.168.42.1:6666`, send the captured connection prefix, process greeting/heartbeat, authorize, prepare and start command 1 preview.
7. Strip the nine-byte live-envelope prefix from type-1/subtype-20 packets and emit Annex-B HEVC to the shared decoder. A bounded stop request, socket/GATT/network cleanup, feed watchdog and operator Retry cover disconnect/failure.

Only the per-installation authorization UUID and ordinary app preferences are persisted. Session keys and Wi-Fi passwords are not logged or stored. Wi-Fi permission and camera approval remain normal platform/user actions. Foreground retry is supported; exhaustive background/radio-loss/reconnect behavior needs physical-device validation.

## Build and tests

From `Apps/Android`:

```sh
JAVA_HOME=/opt/homebrew/opt/openjdk ./gradlew \
  :app:assembleDebug \
  :monitor:testDebugUnitTest \
  :app:lintDebug :monitor:lintDebug
```

The build stages Swift automatically via `:monitor:stageSwiftCore` and `scripts/android-stage-swift-core.sh`. It requires the matching Swift 6.3.3 toolchain, installed `swift-6.3.3-RELEASE_android` SDK, Android SDK 36, NDK 28.2.13676358, CMake 3.22.1 and Java 17 or newer. This workstation uses Homebrew JDK 26. The local SDK path belongs in ignored `local.properties`, not source control. Current ABI is **arm64-v8a**, min API 29, target API 36.

The baseline dependency versions demand API 37 in AAR metadata, while this workstation's SDK repository does not offer `platforms;android-37`. The inherited metadata-check exemption is retained; library lint bundle tasks explicitly depend on exemption marker outputs so Gradle task validation and lint remain runnable. This is a documented development-build limitation, not a claim of API 37 certification.

APK: `Apps/Android/app/build/outputs/apk/debug/app-debug.apk`. It contains the complete Swift runtime closure plus Vulkan, 20 arm64 native libraries (17 from the Swift closure, Vulkan, AndroidX graphics path and MLKit). Generated binaries remain ignored build artifacts.

Validation: **479 JVM tests** (462 inherited tests, nine protocol/crypto/channel tests, and eight I-Log/catalog/source regressions). New checks cover captured CRC/live-start bytes, every frame split and coalescence, length/CRC rejection, an independent AES-GCM/HKDF fixture, authenticated tampering, key-exchange enum rejection, packed encryption schemes and malformed protobuf, plaintext downgrade rejection and fragmented correlated encrypted responses. App, monitor and Luna lint pass.

## Emulator review and private replay

API 35 arm64 emulator `OpenInstaCine_API35`, landscape 2400×1080. No physical Android phone was connected. Real Luna BLE → Android Wi-Fi → TCP has **not** been exercised on Android hardware yet.

The debug source set includes `LocalReplayBackend`; it is absent from release source sets, and the launcher checks `BuildConfig.DEBUG` before it can be selected. Private video is never bundled. It requires `files/review-preview.hevc` plus `files/review-preview-index.json` inside the app's private storage, the latter containing `framesPerSecond` and `packets` with byte `offset`/`size`. Launch explicitly:

```sh
adb shell am start -n com.opencapture.openinstacine/.MainActivity --ez local_replay true
```

A persistent yellow `LOCAL REPLAY · NOT A LIVE CAMERA` banner labels the review. Starting normally selects the real Luna backend. Replay identities are excluded from the saved-camera list. Invalid/missing input produces an explanatory failure; there is no generated demo feed.

Private captured Luna access units were decoded through MediaCodec into the same live renderer and Swift-backed scope sampler. Vulkan initialized, but the emulator rejected AHardwareBuffer import; the inherited GLES fallback rendered successfully. At the capture's 25 FPS, software-emulator pressure caused skipped decoder input and visible missing-reference corruption. For visual/scope QA only, the private replay index was paced at 5 FPS. This is a test pacing adjustment, not a production camera-rate change or a physical-device performance result.

Verified with private screenshots under ignored `.local/android-review/`: real moving HEVC picture, yellow live/clean chrome, waveform and RGB parade populated from actual pixels, live false-color rendering and legend, settings Link/View Assist/Display panels, truthful empty camera-media state, cached-media presentation and actual offline MP4 playback with a moving picture and working transport, portrait rotation and the playback-assist toolbar. Review findings also corrected the first-frame/presentation clock, a remaining blue DISP token, settings/diagnostic wordmark, and the storage-settings cache root to include the actual no-backup media directory.

Remaining validation: real Android camera approval/permissions/network routing, sustained hardware decode/Vulkan and scopes, rotation/background recovery across device models, media/camera control protocols, and eventual migration of sibling apps onto this shared module boundary. No camera-settings or record-control support is claimed by this shell milestone.
