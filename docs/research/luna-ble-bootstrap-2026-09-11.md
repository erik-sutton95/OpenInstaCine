# Luna Ultra: independently authorized BLE bootstrap

Verified 2026-09-11, Europe/Stockholm; capture timestamps below are UTC on Sep 10.
Hardware: **Insta360 Luna Ultra, firmware v1.0.288**. Client: this Mac,
CoreBluetooth through Bleak 3.0.2, Python with cryptography 50.0.1.

**Our client obtained the camera's Wi-Fi credentials using its own identity and
fresh P-256/AES-GCM session. After the owner accepted the camera prompt, a second
connection reused that identity, negotiated a different key, and retrieved the
credentials without requesting approval again.** This establishes the BLE path
independently of the official app's saved iPhone connection.

The implementation is [luna_ble.py](../../tools/luna_ble.py), with portable lab
framing/crypto in [luna_wire.py](../../tools/luna_wire.py) and
[ucd2.py](../../tools/ucd2.py). It does not yet join Wi-Fi or start a live feed.

## Observed GATT

The camera advertises a short identifier matching the suffix of its serial,
with service **BE80**. All UUIDs below use the Bluetooth base suffix
`-0000-1000-8000-00805f9b34fb` with the four-digit value prefixed by `0000`.

| UUID | CoreBluetooth handle | Reported properties | Verified use |
| --- | --- | --- | --- |
| BE80 | 40 | Service | Discovery filter |
| BE81 | 41 | read, write | Requests with `response=True` |
| BE82 | 43 | notify; CCCD handle 45 | Responses and notifications |
| BE83 | 46 | read | Unused |
| BE84 | 48 | read, write | Unused |
| BE85 | 50 | notify; CCCD handle 52 | Unused |
| BE86 | 53 | read, write | Unused |
| BE87 | 55 | notify; CCCD handle 57 | Unused |

Bleak reports **MTU 515**. These are CoreBluetooth discovery results, not raw ATT
handle/MTU-exchange measurements. Bind by UUID and properties, never these handles.
The lab uses sequential writes of at most **206 bytes**, following the public
implementation; this is not a measured camera limit. The successful bootstrap's
requests fit within one chunk, so multi-chunk transmission remains unverified on
hardware. Subscribing produces a **25-byte UCD2 type-05** initial frame.

GATT discovery evidence: `captures/20260910T221040Z-mac-gatt/gatt.json`.
The simultaneous RF follow still yielded advertisements with zero target ATT.
Direct client wire logging establishes the exchanges below; nRF connection
following remains a separate unresolved capture issue.

## Exact successful sequence

Every command below receives UCD2 response **200** with the matching message ID.
Except the two marked encrypted, messages use the plain 12-byte UCD2 header.
Commands 240/241 and request/reply 39 stay plain even after key negotiation.

| Step | Command | Protobuf / result |
| --- | --- | --- |
| 1 | Subscribe BE82 | Accumulate UCD2 frames across notifications |
| 2 | **8**, GetOptions | Fields `[48,15,30]`: model, serial, firmware |
| 3 | **240**, capability query | Empty body; returned schemes **[3,2,1]** |
| 4 | **241**, key exchange | Field 1 = **3**; field 2 = our fresh 65-byte uncompressed P-256 public key |
| 5 | Key exchange response | Field 1 = **1**, field 2 = camera P-256 public key |
| 6 | **8**, encrypted | Fields `[48,30]`; authenticated decrypted response matches the camera model |
| 7 | **39**, authorization check | Field 1 = our saved uppercase UUID; field 2 = **1**; field 3 = the same UUID |
| 8a | New identity: status **1** | **86**, request authorization, body `08 01` |
| 8b | Camera confirmation | Async **8209**, body `08 00`; result 0, omitted operation defaults to 0 |
| 8c | Saved identity: status **0** | Skip command 86 and proceed directly |
| 9 | **8**, encrypted | Fields `[36,37,43]`, body `08 24 08 25 08 2b` |
| 10 | Decrypt response | GetOptions response field 2 → Options field 36 → field 1 SSID / field 2 password |
| 11 | Disconnect | Persist own identity and credentials locally; discard the session key |

Our sequence succeeds without the two large initialization GetOptions batches
found in the public client. We added an encrypted device-info read to validate
the negotiated key before authorization/credential retrieval. This is a proven
sufficient sequence, not proof that every step is strictly necessary.

The request-39 fields align with the newer community schema: `id`,
`initiator_type`, and `device_id`; initiator **1 = PHONE_IOS**. We mirror that
observed value on the Mac, using our own UUID rather than copying the iPhone's
identity. Android's enum 2 is source-backed but not hardware-tested here.
[Authorization schema][schema-auth].

**Key-exchange success is 1, not 0.** `EncryptErrorCode` assigns unknown=0,
none=1, unsupported scheme=2, bad public key=3, derivation failure=4, and no common
scheme=5. An initial experiment stopped on result 1 because it incorrectly
assumed the common zero-success convention. The corrected client checks both
the enum and the public key, and an authenticated response proves the derived
key works. [Encryption enums][schema-crypto].

## Framing and encryption

Plain and encrypted envelopes retain the same UCD2 checksum and nine-byte inner
message header. Scheme 3 uses an outer header length of **43**; the extension
begins `40 1d 03`, then nonce (12 bytes) and GCM tag (16 bytes). Ciphertext starts
at offset 43 and covers the entire inner header plus protobuf. AAD is exactly
the first 12 outer bytes. The wire length excludes the outer header and checksum.

```text
shared = P-256 ECDH(our ephemeral private key, camera public key)
key = HKDF-SHA256(shared, salt="UCD2-ENCRYPT", info="AES-SESSION-KEY", length=16)
payload encryption = AES-128-GCM, random 12-byte nonce per message
```

The checksum starts `FFFFFFFF`; each byte is XORed into the accumulator's low
byte followed by 32 MSB polynomial rounds (`04C11DB7`); no final XOR; appended
little-endian. It is not conventional CRC-32.
The [public BLE codec][codec] supplied these protocol leads; two successful
sessions on this camera establish interoperability. Public keys differ between
the sessions, and both encrypted replies in each session authenticate correctly.

## Evidence and limits

| Take | UTC interval | Requests / camera frames | Result |
| --- | --- | --- | --- |
| `20260910T221355Z-own-ble-bootstrap` | 22:13:55–22:14:34 | 7 / 29 | New identity, camera approval, credentials read |
| `20260910T222232Z-own-ble-bootstrap` | 22:22:32–22:22:54 | 6 / 10 | Saved identity, status 0, credentials read |
| `20260910T225718262725Z-luna-ble` | 22:57:18–22:57:21 | 6 / 10 | Saved tool after camera wake, status 0, credentials read |

All three have two encrypted requests/replies, **zero checksum failures**, and no
incomplete receive tail. The camera returns a 21-byte SSID and 8-byte password;
values remain private. The raw client logs' SHA-256 hashes are:

| Artifact under `captures/` | SHA-256 |
| --- | --- |
| First take `wire.jsonl` | `00856628a7e2a0fb8901ffdf748553318af2653a03a970dbb3949f8878c7d8b2` |
| Reconnect `wire.jsonl` | `3cb502edf6f4966769f322b50647e65cc30ab16c2d49fade81f081f6e3a23640` |
| Saved tool `wire.jsonl` | `9290c3b9e831b294c366a73c94ef23ce1fcfb6a0e9df565e33cfca585ee86a6c` |

The saved lab tool is refactored from the successful experimental script. Its
final hardware rerun **passed after the owner woke the camera**, completing in
about 3.52 seconds without another approval. Its source SHA-256 was
`094735149896aab1fa1ea05141e1c3e5af227fdf8275514c0a1ee018379298f9`.
The preceding failed scans remain recorded; neither reached service discovery.
This demonstrates reconnect after the reported wake/power-on action, without
establishing a controlled full power-cycle or remote-wakeup test.
Its offline checks cover independent Node/WebCrypto crypto fixtures, malformed
protobuf, key-exchange errors/invalid curve points, authenticated-response
requirements, camera errors, and private identity/credential persistence. Run
`just lab-check`; the standard `just check` remains dependency-free.

Not yet established: authorization rejection/timeout on hardware, persistence
across camera reboot, powered-off wakeup, multi-client arbitration, maximum BLE
write size, other GATT channels, Android/iOS native-client behavior, or other
Insta360 models.

The official-app [TCP/HEVC capture](luna-reconnect-2026-09-11.md) establishes the
network endpoint and decoded first picture separately. Our Mac subsequently
joined the returned AP and reached its listeners, as recorded in the
[own-network report](luna-own-network-2026-09-11.md). Independent TCP preview and a sustained live window subsequently passed in the
[Mac viewer](../mac-preview.md). Interruption recovery, controls and media remain
the next experiments. Shared monitor UI integration follows the existing
[engine extraction plan](../shared-engine-integration.md).

## Repeat the lab

```sh
just lab-setup
just luna-authorize 'EXACT_ADVERTISED_NAME'  # First identity: accept on the camera
just luna-connect 'EXACT_ADVERTISED_NAME'    # Saved identity: no prompt expected
just lab-check
```

Keep the camera awake and the official app disconnected. macOS may request
Bluetooth permission for the host process. The client validates Luna's model
before negotiating. Exit 0 means credentials were retrieved, 2 means the saved
identity needs camera authorization, 1 means failure, and 130 means interrupted.
It disconnects at the end and does not change the Mac's network.

`.local/luna-client-identity.json` preserves this client's identity.
`.local/luna-wifi.json` stores credentials with mode 0600. Each run writes private
GATT, raw wire, message metadata and summary files under ignored `captures/`.
Do not commit raw logs; they include identifiers. Private keys and session keys
are never persisted. A failure leaves any earlier credential file unchanged;
use the successful summary and credential timestamp to identify a current read.

[codec]: https://github.com/diamondfsd/luna-ai-cut/blob/ad47c16929b1b086c0a369fc2b4b5ece5b63f4df/electron/devices/insta360/lunaBleCodec.ts
[schema-auth]: https://github.com/iliakonnov/insta360-nas/blob/b78dddb9cd9bc2cf632871646c6f5af238e582d4/insta360-server/insta360_messages.proto#L3281
[schema-crypto]: https://github.com/iliakonnov/insta360-nas/blob/b78dddb9cd9bc2cf632871646c6f5af238e582d4/insta360-server/insta360_messages.proto#L409
