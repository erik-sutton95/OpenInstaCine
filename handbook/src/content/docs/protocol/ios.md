---
title: iOS notes
description: Simulator limits, Hotspot Configuration, Local Network, CoreBluetooth and CryptoKit on iOS, compared with Android.
---

Compared with the Android adapter:

- **Must run on a physical iPhone** for Bluetooth and the Wi-Fi join. A Simulator
  build skips Bluetooth and talks to a camera on the Mac's current network
  (`LunaCameraBackend(useExistingNetwork: true)`), with an already-approved
  identity from the `LUNA_IDENTITY` environment variable. See
  [Setup](../../guides/setup/#simulator-live-testing).
- **Joining the camera network:** `NEHotspotConfiguration` (needs the *Hotspot
  Configuration* entitlement; the App ID also has *Access WiFi Information*).
  Success from `apply` does not mean the phone associated; wait for a
  `192.168.42.x` address. See [Camera Wi-Fi](../wifi/#when-the-join-fails).
  Android uses `requestNetwork` with a `WifiNetworkSpecifier` and binds the
  process to that network.
- **Local Network permission** (`NSLocalNetworkUsageDescription`) is required to
  reach `192.168.42.1`, plus a Bluetooth usage string.
- **CoreBluetooth:** write BE81 **with response**. A request completes only after
  both the reply notification and the write completion, because the reply can
  arrive first.
- **Crypto:** CryptoKit P-256, HKDF-SHA256 and AES-GCM; Android uses JCA. Both
  validate the camera's public key on the curve.
- **Storage:** the approval identity and camera Wi-Fi password are in the
  Keychain. The Keychain survives a reinstall, but iOS's approval to join the
  camera network does not, so the first connect after a reinstall shows the
  **Join Wi-Fi Network** alert.
- **No MAC over CoreBluetooth.** The app identifies the camera by service BE80
  and name, and matches the serial read over TCP.

See [BLE pairing](../ble/) and [camera Wi-Fi](../wifi/).
