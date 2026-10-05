# Shared Foundation core extraction (superseded)

This is a 2026-09-11 extraction report, kept as history. `SharedMonitorEngine`, `MonitorCore` and
`Adapters/OsmoCompatibility` no longer exist. The portable core is now `Sources/OpenPocketViewCore`,
an app-owned fork that is no longer synced from OpenPocketCine; shared owners live in OpenCine. See
[architecture.md](architecture.md) for the current layout.

The root `SharedMonitorEngine` package now exports a real **MonitorCore** library:
25 Foundation-only source files, 3,677 lines of existing monitor math and policy.
It has no dependency on camera adapters, platform frameworks, networking, BLE,
UI or native decoding. The Osmo protocol implementation is physically located
under `Adapters/OsmoCompatibility`, not inside the shared core.

The source baseline is OpenPocketCine commit
`9c4e7334ca4d935c5d467abecaf8f968f7927d84`. Existing copyright, provenance and
algorithm comments remain. No sibling repository was modified. The extraction
preserves the tested behavior and source-level APIs consumed by the inherited
Apple shell and Android JNI facade.

## Dependency direction

```text
New neutral consumers ────────────► MonitorCore (Foundation only)
Camera backend contract ─────────► MonitorContracts

Existing Apple/JNI imports ───────► OpenPocketViewCore compatibility module
                                    ├── @_exported import MonitorCore
                                    └── existing Osmo wire/models/policies

OpenPocketCineAndroid JNI facade ─► OpenPocketViewCore + CJNI

Insta360 native backend ─────────► Insta360Protocol + MonitorContracts
```

`OpenPocketViewCore` remains both a product and module. Its target path is now
`Adapters/OsmoCompatibility/Sources/OpenPocketViewCore`. `Exports.swift`
reexports MonitorCore so old imports continue to resolve the same public type
names; there is only one implementation of the extracted math. Camera-specific
methods on those types are compatibility extensions that import MonitorCore.
The dependency cannot point back from MonitorCore to those extensions.

The root package retains `MonitorContracts`, the `OpenPocketCineAndroid` dynamic
product, CJNI target and all JNI facade source/signatures. Swift artifacts must
be rebuilt after the module split; this preserves source/JNI compatibility, not
binary compatibility with previously compiled Swift modules.

## What is shared now

| Area | Shared implementation |
| --- | --- |
| Color/scopes | `MonitorTransfer`, transfer/gamut math, `ScopeAnchors`, waveform/histogram scaling, cached scope tables, traffic lights, zebra and false-color bands |
| LUTs | `.cube` parsing/resampling/interpolation, generated looks, exposure compensation, custom LUT indexing and safe filenames |
| Audio assists | Normalized stereo dBFS values, segment conversion, peak hold and meter ballistics |
| Face assists | Normalized tracking-box geometry/smoothing and encoded face-luma measurement; camera EV translation remains in the adapter |
| Layout | Landscape/portrait zones, safe-area policies, feed frames, gimbal/zoom parking geometry and orientation choices |
| Presentation | Freeze/flush/last-frame retention decisions, duplicate-frame suppression, GPU presentation limits, split-grade gates, mirror hold, parameter-set/decoder rebuild predicates |
| Video primitives | Standard AVC/HEVC NAL typing, keyframe detection and Annex-B splitting; proprietary transport depacketization remains in the adapter |
| Playback/media policies | Conform rate choices/duration/speed, playback tap behavior, cache availability grades, media kinds, browser tab/sort values and byte/duration formatting |
| Session/telemetry policies | Reconnect backoff, bounded recovery/drop-storm decisions, frame-rate sampler, connection timing, normalized link scoring/bars and rolling-first-picture gating |
| Operator intent | Gamepad action mapping, shutter-angle conversion, local VPN explanatory copy/predicates |

The generic files are under `Sources/MonitorCore`. New code can depend on its
product directly without importing either camera protocol module.

## Mixed files split at the boundary

| Original surface | Shared part | Compatibility part |
| --- | --- | --- |
| `AudioLevelMeter` | Meter values/ballistics and shared 15-segment scale | Captured `cam_audio_status_v2` byte parsing |
| `CameraLinkHealth` | Input model, score math and warmup gate | Mapping Osmo `ConnectionPhase` to chip labels/target FPS |
| `LiveColorScience` | Curves, matrices, scopes and caches | `ColorMode` conversion and the camera-specific preview fingerprint heuristic |
| `Hevc` | Standard NAL operations | DJI marker constant/removal; full UDP depacketizer remains separate |
| `EncoderPresentPath` | Decoder/presentation predicates | Osmo live-enable command timing predicate |
| `ShutterAngle` | Angle/rate calculations | Selection from the Osmo `camcap_shutter` table |
| `TrackingBox` | Normalized geometry and smoothing | Captured push/float payload parsers, minimum accepted camera box size and camera tracking policies |
| `FacePriorityExposure` | Pixel/box luminance measurement and common timing constants | Mapping the result to/from the Osmo `EvComp` value |
| `MediaManifest` | Cache grades, media kinds, tab/sort values and formatting | Osmo file handles, filename interpretations, manifest assembler and HTTP URL construction |
| `ConformPreview` | Rate/conform and playback tap policy | `PlaybackVideoLayout`'s CGSize/CGRect wrapper, which requires CoreGraphics on Darwin |

The existing present-freeze threshold remains 2 seconds. Its one definition now
belongs to `FeedPresentPolicy`; the Osmo watchdog reads that shared value. Other
camera recovery thresholds and replay/enable decisions remain Osmo policies.

## Remaining compatibility work

This is a working extraction seam, not a claim that every inherited model is
already brand-neutral. The compatibility module still contains 33 files:

- DUML frames/transports/opcodes, BLE advertisements/model tables, SoftAP
  addressing, camera status/control values, subscription and capability parsing,
  ACK mailbox, video depacketization and camera recovery behavior.
- `MonitorLUT` still combines operator selection with `ColorMode`, camera family,
  official DJI assets and profile resolution. Its portable cube processing has
  moved; a future normalized profile/asset bridge replaces this resolver.
- `MediaFile` still exposes Osmo handles/storage/filename interpretations.
  Manifest parsing and media HTTP paths stay with it until a normalized media
  contract supplies the shared browser/delivery layer. This pass extracts the
  existing cache/conform/presentation primitives; it does not claim to have
  migrated the entire delivery queue or native media platform services.
- `LiveChromeThrottle`, diagnostics report branding, saved-camera/model records,
  gimbal/head tracking and other helpers still use inherited Osmo value types.
  Keeping them together avoids changing their behavior while camera controls
  are unavailable in the new Luna shell.
- `LiveFrameTap` is a platform pixel-buffer converter using CoreVideo/CoreImage;
  it and the CoreGraphics playback wrapper remain available through the old
  import. They should move into a dedicated shared Apple processing target when
  the native wrapper is fully separated.
- Named D-Log/D-Log2 math and the existing measured preview-ceiling calibration
  are retained for baseline parity. **Luna's verified stream is Rec.709** and
  must use authoritative backend color metadata. It must not activate Osmo's
  pixel-range fingerprint heuristic or inherited automatic DJI LUT defaults.

The inherited UI can therefore keep its compatibility import during this
iteration while taking all extracted implementations from MonitorCore. The new
Luna backend knows no DUML. Adopting the shared package in the existing
OpenPocketCine/OpenZCine repositories remains a separate migration; this work did
not replace or modify those repositories.

## Verification

Before extraction, the copied root package passed **606 tests in 53 suites**.
After extraction, `swift test` passes **609 tests in 54 suites**, including all
baseline tests and Android facade tests. No existing test or expected value was
changed to accommodate the split. The new `MonitorCoreTests` target depends on
MonitorCore alone and adds:

1. A Foundation-only import boundary check for every shared core source.
2. A wire-code ownership check across MonitorCore, MonitorContracts and the
   shared Apple screens. DUML/UCD2 codec, command and depacketizer references
   cannot silently re-enter these layers.
3. A direct neutral-import check for LUT math, Rec.709, cache/media policies,
   presentation, HEVC primitives and tracking geometry.

The complete run is recorded privately in
`.local/shared-core-extraction-tests.log`. Run the checks with:

```sh
swift test
```

Native Apple simulator builds and Android cross-compilation/packaging validate
the platform wrappers separately. This extraction does not use or connect to a
physical phone or camera.
