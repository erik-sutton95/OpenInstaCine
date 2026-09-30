---
title: UCD2 frame
description: UCD2 framing, checksum, the nine-byte message header, and the scheme-3 encrypted envelope used on BLE and TCP.
---

Format and checksum are in `Adapters/Insta360Protocol/Sources/Insta360Protocol/UCD2.swift`
(tested against captured fixtures). The same frame carries every message on BLE
and TCP. Most messages are plain; a few BLE reads use the
[scheme-3 envelope](#scheme-3-encryption).

## Layout

```text
"UCD2" | ver | hdr-len | type | seq | payload-len:u32le | [extension] | payload | checksum:u32le
```

| Offset | Field | Notes |
| --- | --- | --- |
| 0 | magic | `55 43 44 32` (`UCD2`) |
| 4 | version | `01` |
| 5 | header length | **12** plain, **43** scheme-3 encrypted |
| 6 | type | **4** message, **1** media, **5** heartbeat |
| 7 | sequence | 8-bit, per connection, wraps |
| 8 | payload length | `u32` little-endian; excludes the header and checksum |
| 12 | extension | scheme 3 only: `40 1d 03`, 12-byte nonce, 16-byte GCM tag |
| header length | payload | message, media or empty |
| end - 4 | checksum | `u32` little-endian over every byte before it |

### Checksum

Not conventional CRC-32. The accumulator starts at `FFFFFFFF`; each byte is
XORed into its low byte, followed by 32 MSB-first polynomial rounds with
`04C11DB7`. No final XOR. Four byte-table rounds per byte give the same result.

## Message header

A type-4 payload (after decryption, for an encrypted frame) starts with a
nine-byte header, then the body:

| Offset | Field | Notes |
| --- | --- | --- |
| 0 | code | `u16` little-endian `MessageCode`: the command, the response status, or a notification |
| 2 | content type | 2 protobuf; 1 raw bytes (seen on NV12 thumbnail replies) |
| 3 | identifier | `u32` little-endian: 30-bit request ID plus two flag bits; `0x80000000` is set on both request and reply |
| 7 | reserved | `u16` |
| 9 | body | protobuf, raw bytes, or empty |

| Direction | Code |
| --- | --- |
| Phone request | The command, for example 9 `SET_PHOTOGRAPHY_OPTIONS` |
| Camera reply | **200** success, **500** rejected; same request ID |
| Camera notification | Codes **8192 and above**, for example 8208 capture status |

Do not read a reply code 200 as the schema's `PHONE_COMMAND_CTRL_BATCH_FAVORITE`:
correlate by direction and request ID. Request IDs start at 1 per connection;
keep separate counters and reassemblers for BLE and TCP and recreate them after
a disconnect.

Bodies are proto3: default zeros and false are omitted, so an absent field is not
proof of Off. GetOptions replies carry the returned option IDs in field 1 (not an
error status) and the options in field 2.

## Scheme-3 encryption

| Part | Bytes |
| --- | --- |
| AAD | The first 12 outer header bytes, built with the plaintext length **before** encryption |
| Extension | `40 1d 03`, then the 12-byte nonce and the 16-byte tag |
| Ciphertext | Starts at offset 43; covers the whole inner message header plus body |

AES-GCM ciphertext length equals plaintext length; there is no padding. The
checksum is appended after the nonce and tag are in place. Never decrypt or
interpret a frame that has not passed the length and checksum check. Keys come
from the [BLE key exchange](../ble/#encryption).

## Media frames

A type-1 payload starts with a nine-byte media header: one subtype byte and an
eight-byte little-endian timestamp in milliseconds, then the data. See
[Live view](../live-view/#per-packet).
