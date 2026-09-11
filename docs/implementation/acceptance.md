# OpenInstaCine shell acceptance and review

2026-09-11 · OpenInstaCine 0.1.0 (1) · Implementation through `81da05a`

The native shell uses the actual OpenPocketCine baseline implementations from
`9c4e7334ca4d935c5d467abecaf8f968f7927d84`. It is not a set of replacement mock
screens. The new app supplies an Insta360 identity, yellow `#FFCF00` accent and
Luna backend. [Architecture](architecture.md), [Apple inventory](ios-parity-inventory.md)
and [Android inventory](android-parity-inventory.md) record the extraction and
remaining compatibility work in detail.

No application was installed or launched on the connected physical iPhone.
Apple review used iPhone 17 Pro and iPad mini simulators in landscape, plus a
Mac Catalyst build. Android review used an arm64 API 35 emulator.

## Feature coverage

| Surface | Implemented behavior and evidence |
| --- | --- |
| Identity | Separate app IDs, name, generated monitor icon, yellow selection/focus/accent tokens; inherited fonts, Lucide icons, charcoal surfaces and semantic analysis colors |
| Startup | Original splash, first-run steps, scanning list, saved-camera cards/options, reconnect, setup and failure/recovery screens; local recording source selected through these real screens |
| Live monitor | Original safe-area/layout policies, video presentation, top status, battery/lock, system controls, capture bar and scrollable assist rail; moving Luna HEVC displayed on both Apple simulators and Catalyst |
| Display modes | DISP 1/2, clean mode, visibility preferences, chrome editor, portrait/landscape policy and lock retained; both modes switched successfully in final iPhone review, with inherited layout/editor unit coverage |
| LUT | Auto uses the backend's Rec.709 preview transfer; creative looks, custom imports, exposure and split preview retained. Luna camera LUT catalog offers Auto |
| Peaking / false color / zebra | Existing GPU effects, options, exposure scales and legends; real false-color paint and legend visually verified; inherited effect tests pass |
| Waveform / parade | Existing pixel sampling, mode/brightness/scale controls, trace rendering, positioning and resizing; actual recorded-pixel waveform on Apple and waveform/parade on Android visually verified |
| Histogram / vectorscope / lights | Original sampling/math, scale and compensation options, presentation and settings; inherited shared/native tests retained |
| Composition | Guides, aspect masks, grids, crosshair, mirror and positioning retained with baseline defaults/persistence |
| Audio | Live audio remains visible but reports unavailable without backend levels. Clip playback audio/metering infrastructure retained; no decoded Luna live-audio claim |
| Capture controls | Original control locations and panels retained; unknown recording/format/exposure/WB values remain unknown. Final WB panel visually verified with disabled choices and clear unavailable copy; unsupported writes do not invent camera state |
| Gimbal / head tracking / zoom | Original reusable UI/input components retained and capability gated. Luna does not advertise these controls |
| Settings | All seven sections retained: Link, Sharing, View Assist, Controls, Display, Storage, System. Each opened in iPad landscape; Sharing retains the baseline Coming soon state |
| Media library | Original filters, sorting, grid/list/thumbnail sizes, favorites, cache policy and navigation. Apple replay supplied one local asset through the backend contract; Android exercised its inherited offline cache/player |
| Playback | Actual Luna MP4 picture played in the inherited player, with scrub/transport/conform/assist/share surfaces. Android also verified portrait playback. Failed deletion now keeps the current screen/selection |
| Delivery | Original shared delivery picker, local share and Apple Frame.io/configuration flows retained; picker inspected without sending/uploading anything. Frame.io requires local app configuration |
| Diagnostics / legal | App identity injected into report headings, local redaction/journals retained, legal screens and upstream attribution preserved. No new support/source URL or service credential invented |

The feature inventory is broader than the manual smoke pass. Existing automated
coverage and source preservation support parity; this report does not claim
every gesture on every physical device has been exhaustively exercised.

## Automated validation

| Gate | Result |
| --- | --- |
| Portable shared/compatibility/JNI Swift tests | 609 tests in 54 suites passed |
| Standalone Swift Luna protocol | 24 tests passed; debug and release checked during adapter development |
| Apple native UI / facade tests | 413 tests, 1 optional fixture skipped, 0 failures; includes 16 backend-facade regressions |
| Apple builds | Simulator Debug, unsigned generic iOS Release and Mac Catalyst Debug all succeeded |
| Release isolation | Release binaries contain neither the replay backend/label nor debug replay/direct-TCP environment selectors |
| Android | 471 JVM tests passed; app, monitor and Luna lint passed; complete arm64 debug APK built |
| Python protocol/lab harness | 21 tests passed, including expected negative authorization/transport cases |
| Source boundary | Foundation-only core imports and absence of camera wire codecs in shared Apple screens checked by tests |
| Build/review helpers | Shell syntax, Python compilation, real HEVC indexing/remux and just recipe expansion checked |
| Repository hygiene | Generated build output, captures, recordings, credentials and local indexes excluded; whitespace checks pass; staged source scan found no private identity/credential values |

One inherited Apple test requires a caller-supplied D-Log2 movie through
`OPV_SIM_FEED_CLIP`; it skips when absent. Other inherited D-Log math and official
cube tests still run. The old scene-brightness heuristic test was changed to
require explicit source transfer metadata; dark Rec.709 scenes cannot be
misidentified as DJI log footage. The Osmo single-SD routing regression remains
in the compatibility tests, outside the shared media cache.

Final local evidence: `.local/apple-acceptance-tests.log`,
`.local/apple-release-final.log`, `.local/apple-catalyst-final.log`,
`.local/final-core-tests.log`, `.local/final-protocol-tests.log`,
`.local/final-lab-check.log`, `.local/release-boundary.json`.
The final injected diagnostic-heading change also passed all eight focused
diagnostic tests. One earlier integration run was interrupted during test-host
startup by review cleanup; the complete subsequent run passed all 413 cases.
Upstream LUT tables/license text retain original bytes through scoped Git
attributes rather than rewriting vendor numerical assets.

## Feed evidence and limits

The earlier Mac protocol harness was tested with the physical Luna Ultra and
the user confirmed its live picture. That established the observed BLE
authorization, encrypted Wi-Fi credentials and UCD2 TCP/HEVC path. See the
[protocol research](../research/) and [Apple adapter review](apple-adapter-review.md).

During native shell implementation the camera stopped advertising and its AP
was unavailable. Therefore **the new native Apple and Android BLE → Wi-Fi →
live-camera path is implemented but not yet physically validated**. No simulator
or replay result substitutes for that check. First native connection may need
approval on the camera for the app installation's own authorization identity.

Native decoding and shared monitor tools were exercised with the real recorded
Luna 1280×720, 25 fps, Rec.709 HEVC capture through an explicit DEBUG-only backend.
Apple displayed approximately 23–24 fps during representative review. Android's
software emulator required 5 fps replay pacing for clean scope inspection;
its Vulkan AHardwareBuffer import fell back to the inherited GLES renderer.
These are development-environment observations, not hardware performance claims.
Replay is labeled in the monitor, uses private local input, and is excluded
from release builds. No footage is distributed with the app.

Camera recording/settings, live audio, gimbal/zoom and camera media operations
remain deliberately unimplemented for Luna. Frame.io credentials and store
signing/release distribution are not configured here. Android's inherited
SDK 36 / dependency metadata 37 exemption is documented in [android-shell.md](android-shell.md).

The shared package/platform modules are ready for further brands. OpenPocketCine
and OpenZCine themselves were not migrated or modified; replacing their copies
with these modules is a separate integration step. Several inherited value
types and JNI names remain in a documented compatibility layer.

## Reproduce the review

```sh
just apple-generate
just apple-build
xcrun simctl list devices available
just apple-test SIMULATOR_UUID
just apple-replay SIMULATOR_UUID /absolute/path/to/preview.hevc
just android-build
just android-check
just core-test
just lab-check
```

The simulator helper validates its UUID against CoreSimulator and only uses
`simctl`; it cannot target a physical phone. Rotate the selected simulator to
landscape, then choose **Local recording · preview test**. For the real adapter,
launch without replay environment variables. Simulator cannot perform BLE.

Local review artifacts remain under ignored `.local/` and native `build/`
directories. The Android APK is `Apps/Android/app/build/outputs/apk/debug/app-debug.apk`.
The Apple project is generated at `Apps/Apple/OpenInstaCine.xcodeproj` from the
checked-in `project.yml`.

The fresh iPhone simulator installation was launched using the documented
`just apple-replay` command after tests, clearing only this test app's prior
simulator sandbox. It remains in landscape for review. The temporary iPad and
Android emulators were shut down after inspection. No connected phone or
unrelated application process was used.

Final simulator picture and RGB waveform: `.local/ios-review/iphone-landscape-final.png`.
Final Link settings show LOCAL REPLAY rather than claiming an active BLE link.
