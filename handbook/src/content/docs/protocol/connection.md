---
title: Connection spine
description: BLE bootstraps an encrypted, approved session and hands off to the camera's Wi-Fi. Order of operations from scan to HTTP media.
---

BLE is bootstrap only: it proves the phone is approved and reads the camera's
Wi-Fi details. Control, live view and media go over the camera's own network.
Order of operations:

```text
BLE scan → GATT connect → key exchange → owner approval → read Wi-Fi creds → join AP → TCP 6666 UCD2 → HTTP media
```

1. **[BLE scan](../ble/).** Find service **BE80**. The advertised name ends in the camera's serial suffix.
2. **[GATT](../ble/).** Write requests to **BE81** with response; subscribe to **BE82** for replies and notifications.
3. **[Key exchange](../ble/#encryption).** Scheme 3: fresh P-256 ECDH, HKDF-SHA256, AES-128-GCM. Keys live only for this connection.
4. **[Owner approval](../ble/#authorization).** Check authorization with the app's own UUID; the first time, the owner accepts on the camera's touchscreen.
5. **[Wi-Fi credentials](../wifi/).** An encrypted GetOptions read returns the camera network's SSID and password. Do not synthesize them.
6. **[Join the AP](../wifi/).** Camera at `192.168.42.1`, phone on `192.168.42.x`.
7. **[UCD2 over TCP](../ucd2-transport/).** Port **6666**: preface, greeting, heartbeats, authorization check, then live view. Frames are [UCD2](../ucd2-frame/) with protobuf bodies.
8. **[Live view](../live-view/)** rides the same TCP socket; **[media](../media/)** is HTTP on port 80 while the control session is open.

Framing, crypto and messages live in the Foundation-only Swift package
`Adapters/Insta360Protocol/`. Platform adapters own Bluetooth, crypto, the Wi-Fi
join and sockets: `Insta360Apple` on iOS and `insta360-luna` on Android, both in the
OpenCineInsta360 package.

## Evidence levels

| Level | Meaning |
| --- | --- |
| **Documented** | Official product documentation. |
| **Source-backed** | A public implementation or schema does this; not proof for this body, firmware, phone or client identity. |
| **Observed** | Identified packet frames and camera state support the fact. |
| **Reproduced** | Our own client succeeds repeatedly on the identified hardware. |
| **Unknown** | No sufficient evidence yet. |

The labels stay attached when a claim moves into code or these pages.

## Not DJI

DJI's `fff0`/`fff4`/`fff5` GATT, DUML pairing, `192.168.2.1`, UDP 9004 and the
enable-once watchdog are Osmo behavior, not Luna defaults. The Luna method
follows OpenPocketCine's (scan, GATT, app authorization, camera Wi-Fi, control
transport, live frames and media, with local captures and offline decoders), but
every step has its own wire format.
