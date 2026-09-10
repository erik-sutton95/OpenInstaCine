# Shared engine integration for OpenInstaCine

The [shared monitor design](SHARED-MONITOR-ENGINE.md) governs this project. This
repo starts at protocol discovery; it must grow into an Insta360 adapter and thin
brand targets that inherit OpenPocketCine's experience from shared packages.

The design was imported from OpenPocketCine at `9c4e733` on 2026-09-10, with
trailing whitespace removed. The two source copies were byte-identical, including
OpenZCine's at `28bb1143`. It remains design
intent: neither inspected Swift package manifest consumes a shared monitor engine.
This inventory is a migration input, not a claim that extraction has happened.

## Initial extraction inventory

Paths below are relative to the named sibling repo. These are existing seams to
inspect/extract, not files to clone into a third application.

| Surface | Existing sources | Destination / boundary |
| --- | --- | --- |
| Delivery coordination and progress UI | Both: `ios/.../MediaDelivery.swift`, `MediaDeliveryOverlay.swift`, `MediaDeliveryPopup.swift` | Shared orchestration and platform UI modules; camera download/hop implementation injected |
| Frame.io models, OAuth and requests | Z: `Sources/OpenZCineCore/Frameio/`; Pocket: `ios/OpenPocketCine/Frameio/` | Shared portable client/planning; platform auth and secret storage stay in shells |
| Layout policy | Both cores: `MonitorLayoutPolicy.swift`, `MonitorPortraitLayout.swift`; Pocket: `ios/OpenPocketCine/LiveMonitorLayout.swift` | Shared policy and per-platform monitor UI; capability-gated gimbal cluster |
| Scopes and assists | Z core: `ScopeSampler.swift`, `ScopeDisplayScale.swift`; Pocket shell: `LiveScopes.swift`; both shells: `ScopeTraceMetalView.swift` | Shared math/presentation policy; platform GPU implementations stay native |
| LUTs and color workflow | Both cores: `CubeLUT.swift`, `MonitorLUT.swift`; existing platform bake/export code | Shared parsing/library/orchestration; format-specific camera metadata in adapter |
| Media catalog/cache/review | Pocket core: `MediaManifest.swift`; Pocket shell: `CameraMedia.swift`; Z shell: `MediaLibrary.swift` | Shared clip/cache/playback models and UI; OEM catalog/file transfer in backend |
| Diagnostics | Pocket core: `Diagnostics.swift`; both apps' diagnostic infrastructure | Shared redaction and report policy; OS collection/persistence in shell |
| Connection and recovery | Pocket: `BleLink.swift`, `CameraSession.swift`, DUML core; Z: `NativeCameraSession.swift`, Nikon protocol core | Wrap existing adapters; extract only policy whose semantics truly match |
| BLE/Wi-Fi/decoder I/O | CoreBluetooth / network / hotspot / VideoToolbox and Android equivalents | Reusable platform services injected into adapters; no OS imports in portable protocol core |
| Storefront identity | Xcode/Gradle targets, resources, schemes, signing, CI | Remain distinct OpenPocketCine, OpenZCine, OpenInstaCine brand apps |

## Capabilities needed for identical operator experience

Monitoring tools are shared product features. Camera features need positive
capability evidence for the connected body and mode. Unknown Luna operations
remain unavailable with a clear reason until verified.

| Capability group | Evidence required from Luna backend |
| --- | --- |
| Live feed | Codec, dimensions, framing/timestamps, start/stop, audio if available |
| Record and status | Record start/stop, recording state, battery, storage, busy/errors |
| Exposure and image controls | Supported ranges/modes and authoritative readback for ISO, shutter, WB, EV, profile, format |
| Zoom / iris | Independent support and allowed ranges; no assumed iris control |
| Gimbal / tracking | Pan/tilt, recenter, orientation, tracking support and stop semantics; hardware presence is insufficient |
| Clip operations | Catalog, download, proxy/original identity, delete/star support independently |
| Timecode / audio | Actual transport/metadata support, not inferred from the model name |
| Network behavior | Camera AP requirement, delivery internet hop, usable reconnect path |

The shared UI responds to these capabilities and ranges, never `if brand ==
insta360`. Brand identity supplies name/icons/legal copy and backend construction.
Unknown support should not be collapsed into a permanently hardcoded false; the
adapter can update capabilities once device/mode discovery completes.

## Migration sequence

1. Complete this cross-app inventory and reconcile existing feature differences.
2. Extract Delivery and Media orchestration into one versioned package source.
   Prove both existing apps call it before extending destinations.
3. Extract scopes/assists/layout and reusable SwiftUI/Compose monitor surfaces.
4. Formalize the portable `CameraBackend` contract around proven Osmo and Nikon
   adapters. Keep protocol-specific recovery rules within the relevant adapter.
5. Make the two existing brand apps thin consumers and run their parity gates.
6. Wire the verified Luna backend and OpenInstaCine's thin targets to those same
   packages. A new monitor/media/Frame.io screen copied here fails the design.

Luna capture and portable protocol research can proceed while extraction is
planned; production UI integration depends on the shared engine. Do not invent
an incompatible third backend contract solely to make a scaffold compile.

The engine/monorepo name remains open in the original design. A versioned shared
package across the existing repos is allowed during migration. Final naming does
not block protocol captures or this inventory.

## Acceptance

- One implementation source for shared behavior, consumed by all brand apps.
- OpenPocketCine's monitor, assists, media/playback and delivery experience is
  inherited on each native platform wherever Luna capabilities permit it.
- Portable wire codec tests use documented vectors and hardware fixtures with
  provenance; native camera I/O remains shell-owned.
- Physical iOS and Android connection, first frame, reconnect, controls and media
  checks are required for whichever product surface ships. A Python capture
  helper is research tooling, not evidence that either app platform works.
- Existing Osmo/Nikon protocol, performance and parity gates remain green during
  extraction. The present discovery work does not modify those applications.
