---
title: BLE pairing
description: Scan, GATT, scheme-3 key exchange, owner approval and the encrypted Wi-Fi credential read for the Luna Ultra.
---

BLE is bootstrap only. The phone negotiates an encrypted session, proves it is
approved, reads the camera's Wi-Fi details and disconnects. See the
[connection spine](../connection/).

## Scan

Filter by service **BE80**. The camera advertises a short name that ends in its
serial suffix; OpenInstaCine shows it as **Luna Ultra** plus that suffix. The
client checks the model (GetOptions field 48) before negotiating.

## GATT

All UUIDs use the Bluetooth base: `0000XXXX-0000-1000-8000-00805f9b34fb`.

| Role | UUID | Use |
| --- | --- | --- |
| Service | `BE80` | Discovery filter |
| Write | `BE81` | Requests, written **with response** |
| Notify | `BE82` | Replies and notifications |
| Others | `BE83` to `BE87` | Unused |

Bind by UUID and properties, never by handle. CoreBluetooth reports MTU 515.
Writes are chunked at 206 bytes, following the public implementation; this is
conservative, not a measured limit, and the bootstrap requests fit one chunk.
Subscribing produces a 25-byte UCD2 type-5 greeting. Accumulate
[UCD2 frames](../ucd2-frame/) across notifications.

## Sequence

Every step gets UCD2 response **200** with the matching message ID. Commands
240, 241 and 39 stay **plain** even after a key exists; encryption belongs to each
request, not the session.

| Step | Command | Body and result |
| --- | --- | --- |
| 1 | Subscribe BE82 | Collect the type-5 greeting |
| 2 | **8** GetOptions | Fields `[48, 15, 30]`: model, serial, firmware |
| 3 | **240** capability query | Empty body; returns schemes `[3, 2, 1]` |
| 4 | **241** key exchange | Field 1 = **3**; field 2 = our fresh 65-byte uncompressed P-256 public key |
| 5 | Key exchange reply | Field 1 = **1** (success), field 2 = the camera's public key |
| 6 | **8** GetOptions, encrypted | Fields `[48, 30]`; an authenticated reply proves the derived key |
| 7 | **39** authorization check | Field 1 = our saved uppercase UUID, field 2 = initiator (1 iOS), field 3 = the same UUID |
| 8a | Status **1** (new identity) | **86** request authorization, body `08 01`; the owner accepts on the camera |
| 8b | Camera answer | Notification **8209** body `08 00` (accepted) |
| 8c | Status **0** (saved identity) | Skip 86 |
| 9 | **8** GetOptions, encrypted | Fields `[36, 37, 43]` (body `08 24 08 25 08 2b`) |
| 10 | Decrypt the reply | Options field 36 → field 1 SSID, field 2 password |
| 11 | Disconnect | Keep the identity and credentials; discard the session key |

:::note[Key-exchange success is 1]
`EncryptErrorCode` assigns unknown 0, none 1, unsupported scheme 2, bad public
key 3, derivation failure 4, no common scheme 5. Success is **1**, not 0. Check
both the enum and the returned key.
:::

## Encryption

```text
shared = P-256 ECDH(our ephemeral private key, camera public key)
key    = HKDF-SHA256(shared, salt = "UCD2-ENCRYPT", info = "AES-SESSION-KEY", length = 16)
cipher = AES-128-GCM, a fresh random 12-byte nonce per message
```

The session key and ephemeral private key belong only to one connection and are
never persisted. The platform must validate the camera's point on the curve
(CryptoKit and JCA do). The envelope layout is on the
[UCD2 frame](../ucd2-frame/#scheme-3-encryption) page. A plaintext response can
never satisfy an encrypted read.

## Authorization

Each installation generates its own UUID and keeps it (Keychain on iOS, private
storage on Android). The first connection needs the owner's approval on the
camera's touchscreen; later connections with the same UUID get status 0 and skip
the prompt, even with a fresh key. Never reuse another client's captured
identity.

The client also accepts the source-backed alternative notification 8228; only
8209 has been seen on hardware. Rejection and timeout have not been tested on
hardware.

## Identity and credential storage

| Platform | Approval identity | Camera Wi-Fi password |
| --- | --- | --- |
| iOS | Keychain | Keychain |
| Android | App-private storage | Keystore-sealed `CameraWifiCredentialStore` |

The app treats both as secrets: they are redacted from logs and debug
descriptions and never leave the phone.
