# Portable Luna protocol

`Adapters/Insta360Protocol` is a standalone Swift 6 package exporting the
`Insta360Protocol` library. It imports only Foundation, supports the Apple app's
macOS 13 / iOS 16 deployment floor, and contains no Bluetooth, network, decoder,
UI, filesystem, subprocess or cryptographic implementation. The Apple adapter
supplies transport and CryptoKit. The monitor engine does not import Luna wire
types.

This is a native port of the verified research tools, not a new camera protocol:

- [BLE bootstrap evidence](../research/luna-ble-bootstrap-2026-09-11.md) and
  [Python codec](../../tools/luna_wire.py).
- [UCD2 capture parser](../../tools/ucd2.py) and
  [TCP viewer](../../tools/luna_tcp.py).
- [Independently displayed Mac feed](../mac-preview.md), Luna Ultra v1.0.288:
  HEVC Main, 1280×720, 25 fps, BT.709 limited range.
- The pinned [community protobuf schema](https://github.com/iliakonnov/insta360-nas/blob/b78dddb9cd9bc2cf632871646c6f5af238e582d4/insta360-server/insta360_messages.proto#L4973)
  confirms that GetOptions response field 1 contains **returned option IDs**, not
  an error status; field 2 contains Options. Command success is response 200,
  with 500 rejected. This distinction is covered by packed and unpacked fixtures.

## Module boundary

| Type | Responsibility |
| --- | --- |
| `UCD2Frame` | One complete checksum-validated frame; plain/scheme-3 builders and envelope access |
| `UCD2Reassembler` | Incremental framing of one ordered, directional stream, with bounded pending bytes and corruption diagnostics |
| `UCD2Message` | Nine-byte message header; separates 30-bit request ID from its two flag bits; validates response matching/encryption policy |
| `Scheme3Envelope` | Exact AAD, nonce, tag and ciphertext for platform authentication/decryption |
| `ProtoMessage` | Bounded unsigned-varint, fixed32, fixed64 and length-delimited protobuf parsing; strict typed field access |
| `LunaProtocol` / `LunaRequest` | Verified bootstrap/read/live requests and typed response helpers |
| `LunaRequestCounter` | Per-connection IDs beginning at 1 and independently wrapping 8-bit sequences |
| `LunaMediaPacket` | Type-1 media subtype, original 64-bit timestamp and payload extraction |

Create separate reassemblers and counters for BLE and TCP; recreate them after a
disconnect. `feed(_:)` accepts any transport fragmentation or coalescing. The
default frame limit is 4 MiB; the parser keeps a cursor while draining a batch,
checksums directly against buffered bytes, and compacts between input batches.
It does not shift the remaining stream for every video packet. An oversized
header or a bad checksum is skipped and counted; the next valid frame can be
recovered. The adapter decides whether those diagnostics require disconnecting.
The returned array is limited by the input batch, so transports should continue
to supply moderate receive chunks (for example, 64 KiB).

Protobuf parsing validates the complete message before exposing fields, caps
message size at 1 MiB and fields/repeated values at 16,384 by default, checks
64-bit varint overflow and length bounds, and rejects groups. Known singular
fields use the last occurrence but reject incorrect wire types in any occurrence.
Missing proto3 authorization status is authorized (0); missing key-exchange
status is unknown (0) and must fail. Key-exchange success is **1**.

## Adapter sequence

BLE discovers BE80, writes BE81 with response, and subscribes to BE82. Bind the
public UUID constants by UUID and characteristic properties. The exported
206-byte write chunk is conservative, not a measured camera maximum; the
verified bootstrap requests fit one chunk. For a new saved identity:

1. Subscribe, collect the type-5 greeting, and send
   `deviceInformationRequest(includeSerial: true)`.
2. Send `encryptionCapabilitiesRequest`, decode `encryptionSchemes(response:)`,
   and require scheme 3. Generate a fresh P-256 private key.
3. Send `keyExchangeRequest(publicKey:)` with the 65-byte uncompressed X9.63
   public key. `cameraPublicKey(response:)` checks success 1 and encoding;
   **CryptoKit must validate the point on the curve** and perform ECDH.
4. Derive 16 bytes with HKDF-SHA256 and `hkdfSalt` / `hkdfInfo`. The session key
   and ephemeral private key belong only to this connection.
5. Send `deviceInformationRequest(encrypted: true)` and authenticate/decode
   its encrypted response, establishing that the derived key works.
6. Send the **plain** `authorizationCheck(identity:)`, using the app's own
   persistent UUID. Status 0 proceeds; status 1 requires `requestAuthorization`
   and the owner prompt. After its matching response, validate async notification
   8209. The source-backed 8228 alternative is accepted but not hardware-proven.
7. Send encrypted `wifiCredentialsRequest`. Match and authenticate its response
   before `wifiCredentials(response:)`. Store credentials securely in the
   platform adapter; the value's normal/debug descriptions are redacted.
8. Disconnect BLE and discard ephemeral keys before or during Wi-Fi handoff.

Key negotiation and authorization-check messages remain plain even after a key
exists. Encryption belongs to each request, not a blanket session-wide toggle.

For TCP, join the returned AP, connect to `defaultHost:defaultPort`
(192.168.42.1:6666), send `tcpPreface`, wait for the type-5 greeting, and start
two-second heartbeats. Read device information, check authorization using the
same saved UUID, read capture status, then send `startLiveRequest`. All of these
TCP messages are plain. Acknowledge live start before reporting the session live;
decoded-frame arrival is the separate first-picture signal. On close, attempt
`stopLiveRequest` if start might have reached the camera, then close transport
and clear all pending requests.

There are no record, delete, format, exposure, lens, gimbal or other unverified
camera-setting commands in this module. The live-start body is the exact
captured/replayed profile; its fields are not exposed as speculative settings.

## Encryption integration

Build the inner message using `request.message(identifier:).payload`. For a
plain request, `request.plainFrame(identifier:sequence:).raw` returns the packet;
it refuses requests marked `requiresEncryption`.

For an encrypted request, call
`UCD2Frame.scheme3AssociatedData(sequence:plaintextLength:)` **before** AES-GCM
encryption. Use those exact twelve bytes as AAD and a fresh random twelve-byte
nonce. Pass the resulting ciphertext, nonce and sixteen-byte tag to
`UCD2Frame.scheme3(sequence:ciphertext:nonce:tag:)` with the same sequence. The
builder appends the UCD2 checksum after placing nonce/tag in the 43-byte header.
AES-GCM ciphertext length equals plaintext length; no padding is present.

For a reply, `frame.scheme3Envelope()` separates those fields. Authenticate and
decrypt using the platform's AES-GCM before constructing
`UCD2Message(payload: plaintext)`. Then call
`successfulResponseBody(for:encrypted:requiresEncryption:)` using the actual
authenticated envelope state and the outstanding request's policy. A plaintext
response cannot satisfy an encrypted read. Never decrypt or interpret bytes
from a frame that has not passed the framing/checksum parser.

`plainMessage()` does not interpret ciphertext. Unknown extensions and short
inner headers fail. The portable package does not authenticate tags itself;
its envelope tests are not a replacement for platform crypto tests.

## Video handoff

`LunaMediaPacket(frame:)` requires a plain type-1 frame and at least a nine-byte
media header. `hevcAnnexB` is present only for subtype `0x20`; its bytes go to the
native HEVC decoder. Subtypes `0x30` / `0x40` remain uninterpreted, without
inventing audio or metadata meanings. An empty video payload is rejected.

The timestamp is the original eight-byte little-endian counter. Hardware
observed a delta of 40 at 25 fps, but its epoch/timebase remains unproved. Keep
that distinction when generating presentation timestamps; do not present it as
wall-clock time. Media bytes are not retained or recorded by this package.

## Validation

Run from the project root:

```sh
swift test --package-path Adapters/Insta360Protocol
swift test -c release --package-path Adapters/Insta360Protocol
```

The 24 XCTest cases cover captured request/greeting/live-start bytes, an
independent checksum vector and bit-round reference, every split point and
bytewise input, coalescing, corruption resynchronization, oversized headers,
large garbage input with bounded pending bytes, nonzero-based Data slices,
request ID/encryption/error matching, unknown flags, counter rollover, the
independent Node/WebCrypto scheme-3 envelope fixture, malformed protobuf and
field types, packed/unpacked responses, crypto success 1, proto3 authorization
defaults, rejection notifications, credential parsing/redaction, and media
timestamp/subtype extraction.

These offline native checks establish codec compatibility with the sanitized
fixtures. The earlier Python client established camera interoperability; the
native Apple adapter still requires its own integrated build and hardware test.
No captures, owner/device identifiers, credentials or private keys are fixtures.
