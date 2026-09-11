# OpenInstaCine

Native iOS and Android field monitor for Insta360 cameras, starting with **Luna
Ultra**. OpenInstaCine carries forward OpenPocketCine's monitor shell, with a
yellow `#FFCF00` identity and a separate Insta360 connection adapter.

The native shell and live-video adapters are implemented. The monitor, scopes,
assists, settings, library, playback and delivery components come from the
OpenPocketCine baseline; camera settings and recording remain unavailable for
Luna until their commands are verified. This is the first shared-engine
extraction in this repository. OpenPocketCine and OpenZCine have **not yet been
switched to consume it**.

The earlier Python Mac viewer completed real BLE → Wi-Fi → displayed-video
sessions. Native simulator/emulator review uses an explicitly labeled **LOCAL
REPLAY** of private camera footage. That proves decode/render/UI behavior, not a
new camera connection. Native first-install consent, Wi-Fi association and
reconnect still need physical-device validation. The overnight app review does
not operate the connected phone.

## What is included

| Area | Current scope |
| --- | --- |
| Live monitor | Inherited landscape/portrait layouts, status chrome, DISP modes and editor, interface lock, settings overlays, feed warmup/recovery presentation |
| Image assists | LUT import/look selection, peaking, false color, highlight/midtone zebras, guides, grids, crosshair and mirror |
| Scopes | Waveform, RGB parade, histogram, vectorscope and traffic lights, driven by decoded image samples |
| Media shell | Library, sorting/filtering, favorites, cache states, playback and playback assists retained; Luna catalog, transfer and deletion are unavailable |
| Delivery | Existing local-media share/export surfaces; Apple retains LUT bake and Frame.io delivery, which requires local configuration. Android retains its baseline system delivery features |
| Luna adapter | Discovery, owner approval, encrypted credential bootstrap, camera Wi-Fi handoff, bounded UCD2 parsing, HEVC preview, heartbeat and cleanup |
| Deferred camera features | Record/photo capture, exposure, white balance, capture format, zoom/focus/tracking, gimbal, camera audio and camera media |

Luna currently advertises **live video only**. Unsupported operations do not
send speculative camera commands. The observed preview is 1280×720 HEVC Main at
25 fps, 8-bit Rec.709 limited range on firmware v1.0.288; these are preview
properties, not the camera's recording settings. Luna starts with a Rec.709
viewing path. Signal colors such as false color, clipping and record red retain
their meaning alongside the yellow app accent.

See the [implemented architecture](docs/implementation/architecture.md),
[Apple session](docs/implementation/apple-session.md),
[Android implementation and review](docs/implementation/android-shell.md),
[shared-core extraction](docs/implementation/shared-core-extraction.md), and
[baseline provenance](docs/implementation/baseline-provenance.json).

## Build and review

Run commands from this repository root. Apple development uses Xcode with an
iOS Simulator runtime, XcodeGen and Swift 6; the inspected environment has Xcode
26.2 and XcodeGen 2.46. Android targets API 29+ and arm64-v8a, using SDK 36,
NDK 28.2.13676358, CMake 3.22.1, Java 17+ and the matching Swift 6.3.3 Android
toolchain/SDK. Android stages the complete Swift runtime automatically.

```sh
# Portable shared core and protocol tests; no camera or phone access.
swift test
swift test --package-path Adapters/Insta360Protocol

# Generate and compile the native Apple app for Simulator.
just apple-generate
just apple-build

# Select an existing simulator explicitly; these commands never select a phone.
xcrun simctl list devices available
just apple-test SIMULATOR_UUID
just apple-simulator SIMULATOR_UUID

# Private replay requires ffmpeg/ffprobe and an existing local HEVC recording.
just apple-replay SIMULATOR_UUID /absolute/path/to/private-preview.hevc
```

The underlying Apple generation/build commands are:

```sh
xcodegen --spec Apps/Apple/project.yml
xcodebuild -project Apps/Apple/OpenInstaCine.xcodeproj \
  -scheme OpenInstaCine -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .local/AppleDerivedData CODE_SIGNING_ALLOWED=NO build
```

`apple-test`, `apple-simulator` and `apple-replay` require a simulator UUID.
Replay media and generated indexes stay private and are not bundled with the
app. Without a replay source, Simulator cannot exercise CoreBluetooth. Mac
Catalyst is configured as a secondary target; it is not a promised validated
desktop release.

```sh
# Native Android APK, inherited monitor tests, protocol tests and lint.
Apps/Android/gradlew -p Apps/Android :app:assembleDebug
Apps/Android/gradlew -p Apps/Android :monitor:testDebugUnitTest :luna-adapter:testDebugUnitTest
Apps/Android/gradlew -p Apps/Android :app:lintDebug :monitor:lintDebug :luna-adapter:lintDebug
```

Android output: `Apps/Android/app/build/outputs/apk/debug/app-debug.apk`.
The existing SDK-36 AAR metadata exemption is retained and documented in the
Gradle files; some inherited dependencies request SDK 37 metadata. Native JNI
loading and rendering must be checked in addition to JVM tests. Android
emulator replay is also explicitly labeled; its software decode/GPU limits do
not establish real-device performance.

The extraction passed 609 shared-core/facade tests and 24 Swift protocol tests.
Android reports 462 inherited monitor tests plus 9 Luna tests passing, with APK
and lint verification. Final Apple UI-suite results are recorded separately
when review completes; this README does not claim that suite is fully passing.
The [adapter review](docs/implementation/apple-adapter-review.md) records
connection-race fixes and the remaining hardware verification boundary.

## Existing Mac live-view lab

The small Python viewer remains available independently of the native shell:

```sh
just lab-setup
just luna-view
```

Keep the camera awake and close the official Insta360 app's connection first.
On a new setup use `just luna-authorize 'EXACT_ADVERTISED_NAME'` to request
approval on the camera, then `just luna-view 'EXACT_ADVERTISED_NAME'`. Close the
video window to stop. These commands connect to the real camera and may change
the Mac's Wi-Fi association; they are separate from simulator-only review.
[Mac instructions and measured evidence](docs/mac-preview.md).

Protocol and capture references:

- [Public sources and command research](docs/research/insta360-protocol-sources.md)
- [Verified BLE bootstrap](docs/research/luna-ble-bootstrap-2026-09-11.md)
- [Own Wi-Fi handoff](docs/research/luna-own-network-2026-09-11.md)
- [TCP reconnect and decoded HEVC proof](docs/research/luna-reconnect-2026-09-11.md)
- [Portable Swift protocol](docs/implementation/luna-swift-protocol.md)
- [Passive BLE capture workflow](docs/capture-guide.md)
- [Shared-engine design standard](docs/SHARED-MONITOR-ENGINE.md)

Raw captures, HCI logs, camera footage, identifiers, Wi-Fi credentials and
replay indexes remain in gitignored `captures/` or `.local/`. Apple stores its
approval identity and Wi-Fi credentials in Keychain. Android persists its own
installation identity and keeps Wi-Fi passwords/session keys in memory.
Frame.io configuration is local/CI supplied; no account or OAuth credential is
bundled.

Licensed under [Apache 2.0](LICENSE). See [NOTICE](NOTICE) and
[third-party notices](THIRD-PARTY-NOTICES.md) for inherited code, fonts and icons.
OpenInstaCine is an independent project, unaffiliated with Insta360.
