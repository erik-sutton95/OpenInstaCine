---
title: Architecture
description: The shared OpenPocketCine monitor core and native shells, with a portable Luna protocol package and platform adapters.
---

OpenInstaCine is the OpenPocketCine monitor with a Luna backend. The monitor
core and shells are shared; the camera link is a separate, Foundation-only Swift
protocol package plus platform adapters that own Bluetooth, crypto, Wi-Fi and
sockets.

| Layer | Path | Role |
| --- | --- | --- |
| Shared core | `Sources/` | OpenPocketCine monitor core (`OpenPocketViewCore`, `MonitorContracts`) with small Luna hooks: I-Log color mode, Luna resolutions, `.lrv` proxy. |
| Shared UI | OpenCineUI `MonitorPresentation`, `MonitorUI`, `Android/monitor-ui/` | The shared design system, in its own repository (sibling checkout `../OpenCineUI`). The app assigns the yellow accent at launch. |
| Luna protocol | `Adapters/Insta360Protocol/` | Portable codec: UCD2 framing and checksum, bounded reassembly, protobuf, scheme-3 envelopes, status, settings, media and control messages. Foundation only: no Bluetooth, network or crypto implementation. |
| Luna Apple adapter | `Adapters/Insta360Apple/` | CoreBluetooth pairing, CryptoKit handshake, Keychain, camera Wi-Fi join, Network.framework TCP and session lifetime. |
| iOS app | `ios/OpenInstaCine/` | The OpenPocketCine shell plus the Luna session (`CameraSession*.swift`, `LunaShellMapping.swift`). |
| Watch companion | `ios/OpenInstaCineWatch/` | watchOS remote; the phone stays the radio. |
| Android app | `Apps/Android/` | OpenPocketCine's Compose shell (`:monitor`) on OpenCineUI `monitor-ui`, with the Kotlin shell contract and Luna adapter from OpenCineInsta360 (`insta360-shell`, `insta360-luna`). |
| Android facade | `Sources/OpenPocketCineAndroidFacade/`, `Sources/CJNI/` | JNI exports for the shared decoder, LUT and assist code. |
| Lab tools | `tools/` | Python BLE and TCP research clients, the Mac live-view lab, `tools/LunaProbe` (Swift CLI) and the DEBUG remote client. |
| Tests | `Tests/`, `Adapters/Insta360Protocol/Tests/`, `ios/OpenInstaCineTests/` | Core, protocol and app tests. |

The iOS presentation shell is re-synced from OpenPocketCine with `just sync-openpocketcine`,
which leaves the Luna files, the Swift core and anything a shared OpenCine package owns alone. Boundary tests keep DUML and UCD2 wire APIs
out of the shared monitor modules, and the monitor engine does not import Luna
wire types. Adding a control means extending the neutral backend contract first,
then the Luna mapping.

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
