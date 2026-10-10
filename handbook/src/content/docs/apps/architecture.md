---
title: Architecture
description: OpenCine shared monitor packages, native app composition and the portable Luna integration.
---

OpenInstaCine composes OpenCine's shared monitor and app shell with the Luna
integration. The portable camera protocol and its platform adapters own
Bluetooth, crypto, Wi-Fi and sockets.

| Layer | Path | Role |
| --- | --- | --- |
| Core | `Sources/` (app-owned `OpenInstaViewCore`, no longer synced from OpenPocketCine), OpenCine `OpenCineCore` and `OpenCineMedia` | Portable monitor logic, camera contracts and media math, with app-side Luna hooks for I-Log color mode, resolutions and `.lrv` proxy. |
| Shared UI | OpenCine `MonitorPresentation`, `MonitorUI`, `Android/monitor-ui/` | The shared design system, in the OpenCine platform repository (sibling checkout `../OpenCine`). The app assigns the yellow accent at launch. |
| Connection flow | OpenCine `OpenCineAppKit`, `Android/appkit/` | Cameras and pairing screens, discovery, connection progress, typed failures and saved-camera migration through `LunaIntegration`. |
| Luna protocol | OpenCine `Sources/Insta360Protocol/` | Portable codec: UCD2 framing and checksum, bounded reassembly, protobuf, scheme-3 envelopes, status, settings, media and control messages. Foundation only: no Bluetooth, network or crypto implementation. |
| Luna Apple adapter | OpenCine `Sources/Insta360Apple/` | CoreBluetooth pairing, CryptoKit handshake, Keychain, camera Wi-Fi join, Network.framework TCP and session lifetime. |
| iOS app | `ios/OpenInstaCine/` | App-owned code on the shared OpenCine shell (`OpenCineAppKit`), no longer synced from OpenPocketCine: Luna presentation adapters and native app services. |
| Watch companion | `ios/OpenInstaCineWatch/` | watchOS remote; the phone stays the radio. |
| Android app | `Apps/Android/` | App-owned Compose code (`:app`, `:monitor`) on the shared OpenCine shell (`appkit`) and `monitor-ui`, no longer synced from OpenPocketCine, with the Kotlin shell contract and Luna adapter from OpenCine (`insta360-shell`, `insta360-luna`). |
| Android facade | `Sources/OpenInstaCineAndroidFacade/` | JNI exports for the shared decoder, LUT and assist code. |
| Lab tools | `tools/` | Python BLE and TCP research clients, the Mac live-view lab, `tools/LunaProbe` (Swift CLI) and the DEBUG remote client. |
| Tests | `Tests/`, `ios/OpenInstaCineTests/`, `Apps/Android/monitor/src/test/`, OpenCine `Tests/` | Core, protocol and app tests, including saved-camera upgrade and downgrade fixtures on both platforms. |

Common behavior is maintained in OpenCine and adopted through the pinned
package dependency. The former Pocket source-sync workflow is retired.
Boundary tests keep DUML and UCD2 wire APIs out of shared monitor modules.
Common controls use neutral descriptors and services supplied by the integration.
Both apps use the shared connection model and register their integrations explicitly.
Legacy app models and native adapters remain documented while their ownership migrates.

## Saved-camera compatibility

The versioned document lives in `OpenInstaCine.Cameras` on iOS and
`openpocketcine.cameras` / `document` on Android. The shared store merges the old
records on launch and mirrors edits back to `OpenInstaCine.SavedCameras` and
`openpocketcine.saved-cameras` / `records-json`, respectively. This preserves
upgrade and downgrade compatibility, including names and setup identifiers.
An undecodable record is retained without discarding the valid cameras.

Credentials stay in their existing Keychain or Keystore locations. Camera IDs,
media favorites and EV calibration keys do not change. Forget removes only the
selected camera's Wi-Fi credentials and saved record; the phone's Luna approval
identity stays intact.

## Luna feed path

1. Discover service BE80, subscribe to BE82 and write to BE81 with response.
2. Check the model and negotiate scheme 3 (P-256 ECDH, HKDF-SHA256,
   AES-128-GCM) with an installation-owned authorization UUID.
3. Check authorization. If required, request approval and wait for the
   camera's touchscreen result. Read the encrypted Wi-Fi details only after
   approval.
4. Join the camera network and open TCP `192.168.42.1:6666`. The Apple adapter
   compares the BLE and TCP serials to detect a different camera at the same
   private address.
5. Send the preface, wait for the greeting, start heartbeats, read model,
   authorization and status, wake the gimbal and start live view.
6. Validate frame length and checksum, take media subtype `0x20`, and hand
   Annex-B HEVC to the shared native decoder. Scopes and assists use the real
   decoded pixels.
7. Disconnect with a best-effort live stop, cancel outstanding work and discard
   transport and key state. Recovery is bounded and returns to the operator.

The Apple adapter correlates requests by transport generation plus operation
ID. A request completes only after both a valid response and the BLE write
completion, which covers a notification arriving before the write
acknowledgment.

Operator-visible behavior matches OpenPocketCine unless the Luna cannot do it.
The contract between the two apps is
[`docs/SHARED-MONITOR-ENGINE.md`](https://github.com/erik-sutton95/OpenInstaCine/blob/main/docs/SHARED-MONITOR-ENGINE.md);
the feature-by-feature parity table is
[`docs/implementation/luna-ios-status.md`](https://github.com/erik-sutton95/OpenInstaCine/blob/main/docs/implementation/luna-ios-status.md);
the portable package is described in
[`docs/implementation/luna-swift-protocol.md`](https://github.com/erik-sutton95/OpenInstaCine/blob/main/docs/implementation/luna-swift-protocol.md).

Wire format is in [Protocol](../../protocol/connection/).
