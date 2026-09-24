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
| `LunaProtocol` / `LunaRequest` | Verified bootstrap/read/live requests, official control encoders and typed response helpers |
| `LunaPhotographySettings`, `LunaDeviceStatus`, `LunaCaptureStatus`, `LunaNotification` | Typed status decoders |
| `LunaMediaFile`, `LunaFileMetadata`, `LunaThumbnail` | Media list, metadata, NV12 thumbnail and HTTP URL helpers |
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

Camera controls, status polls and notifications are in the next section. The
live-start body is the exact captured/replayed profile; its fields are not
exposed as speculative settings.

## Control and status API

Updated 2026-09-25. Sources: `LunaControl.swift` (encoders),
`LunaStatus.swift` (decoders), `LunaSchemaTables.swift` (generated enum
tables). Evidence labels:

- **Observed**: byte-identical to an official Insta360 iOS 2.33.0 request, or
  decoded from a real camera reply, on Luna Ultra v1.0.288. The takes are
  `captures/20260910T215020587215Z-luna-reconnect-01/` and the
  `captures/20260916T1*-luna-official-*` series. Fixtures are inlined in
  `Tests/Insta360ProtocolTests/LunaControlTests.swift`.
- **Source-backed**: pinned community schema only; never seen on this wire.

### Official SET shape

Every official photography SET (cmd 9) serializes a whole `PhotographyOptions`
in field order with defaults `20 = {}`, `21 = {}`, `31 = 1`, `88 = 1` present,
and the camera applies only the listed types. Every captured SET used
`FunctionMode` 7. `officialPhotographySet(types:fields:functionMode:)` builds
that shape; all typed setters below use it, so they are byte-identical to the
app. Device-option SETs (cmd 7) likewise carry `1 = 1, 5 = 48000, 42 = 1,
82 = 3` around the one field set.

| Swift | Wire | Evidence |
| --- | --- | --- |
| `setSharpness(_:)` | types [6] | Observed 2 = High (GET 1 = Medium) |
| `setExposureBias(_ stops:)` | types [7], sint32 tenths | Observed +0.3 = wire 6; negatives Source-backed (zigzag) |
| `setVideoExposure(program: .automatic)` | types [21, 100], empty 21, 100 = 2 | Observed |
| `setVideoExposure(program: .isoPriority, iso:)` | types [21, 100] | Observed ISO 160 |
| `setVideoExposure(program: .shutterPriority, shutterSeconds:)` | types [21, 24, 100], 24 = `officialISOTopLimit` | Observed 1/5000 to 1/40, 1/50 |
| `setVideoExposure(program: .manual, shutterSeconds:)` | same, program 3 | Observed (no ISO) |
| `setManualExposure(iso:shutterSeconds:)` | program 3 with ISO and shutter | Source-backed |
| `setColorMode(_:)` | types [35] | Observed 1 Standard, 2 I-Log, 5 Dolby Vision |
| `setWhiteBalanceKelvin(_:)` / `setWhiteBalanceAuto()` | types [39], auto = value omitted | Observed 2000, 2400, auto |
| `setZoomScale(_:)` | types [53] double | Observed 1, 2, 3, 6 (range 1 to 12 external) |
| `setRecordResolution(_:)` | types [31, 63] | Observed 24, 48, 52, 211, 454 |
| `setGimbalFollowSpeed(_:)` | types [91], nested field 2 | Observed Fast = 3 |
| `setGimbalMode(_:)` | types [91], nested field 4 | Observed FPV 1, Roll Lock 2, Roll & Tilt 3, FPV-V 4 |
| `setTapFocus(x:y:width:height:)` | types [94], type 1 + float ROI 2..5 | Observed (fixed: floats, not doubles) |
| `setPhotographyValue(_:_:)` | any scalar type | Source-backed for filter 18, strength 104, FOV 33, flowstate 43, dark EIS 42, AF mode 93, I-Log 72, WB preset 13, ISO limit 24 |
| `LunaShootingMode.request()` | cmd 7 option 41 or 40 | Observed video, timelapse, TimeShift, slow motion, PureVideo, photo, pano |
| `setVideoSubMode(_:)` / `setPhotoSubMode(_:)` | cmd 7 option 41 / 40 | Observed for the modes above; other enum cases Source-backed |

`LunaShootingMode.functionMode` gives the GET bank the app used for each mode:
video 7, timelapse 2, TimeShift 12, slow motion 21, PureVideo 27, photo 6,
pano 67 (all Observed). SETs stay on 7 as the app did.

Color Recovery is not in this table: SET 73 is accepted but not stored on
v1.0.288 (see [color recovery](luna-color-recovery.md)).

### Capture, gimbal, tracking

| Swift | Evidence |
| --- | --- |
| `startLiveRequest` / `stopLiveRequest` | Observed, byte-identical |
| `startCaptureRequest` (`08 01`) | Observed, byte-identical |
| `stopCaptureRequest` (empty) | Official sends `ExtraMetadata` + mode 1; empty body is our own shape |
| `takePictureRequest` (empty), `takePicture(mode: .gimbalPano)` (`08 05`) | Mode Observed; official also attaches `ExtraMetadata` with phone GPS, omitted here |
| `gimbalMove`, `gimbalStick`, `gimbalRecenterRequest`, `gimbalFlipRequest`, `gimbalReleaseRequest` | Observed |
| `gimbalControl(..., field4:)` | Observed raw `20 04` on every FPV-V MOVE; meaning unproven |
| `openTracking(x:y:width:height:timestampMilliseconds:)` | Observed: ms timestamp + float ROI (fixed: floats at fields 2..5) |
| `cancelTrackingRequest` | Observed (sent with recenter) |

### Status polls and decoders

| Request | Decoder | Evidence |
| --- | --- | --- |
| `statusRequest()` options 11, 20, 85, 180 | `LunaDeviceStatus(response:)`: `battery` (percent, `isCharging`), `storage` (free/total bytes, location, card state), `screenBattery`, `screenConnection` | Observed values 16 %/100 %, 50.38 GB free of 50.49 GB; charging = power type nonzero is Source-backed |
| `storageListRequest()` options 176, 177 | `storageList`, `cardLocationLastUpdate` | Observed (inner 2 PASS, SD 3 NOCARD) |
| `shootingModeRequest()` options 40, 41, ... | `shootingMode` | Observed |
| `captureStatusRequest` (cmd 15) | `LunaCaptureStatus(captureStatusResponse:)`: `state`, `isRecording`, `submode`, `captureSeconds` | Observed state 1 recording, 4 photo; seconds always 0 in captures |
| `getPhotographyOptions(_:mode:packed:)` | `LunaPhotographySettings(response:)` | Observed; see below |
| `remainingTimeRequest(functionMode:)` | `remainingRecordTime` | Observed option 99 seconds per card |
| `darkEISStatusRequest` (cmd 157) | `darkEISStatus(response:)` | Observed reply 1; enum names Source-backed |
| `timelapseOptionsRequest` (cmd 17) | `timelapseOptions(response:)` | Observed 1000 ms interval |

`LunaPhotographySettings` reads sharpness 6, EV 7 (`exposureBiasStops`), WB
preset 13, filter 18, still/video exposure 20/21 (`LunaExposure`), ISO top
limit 24, record resolution 31 (`videoResolution`), FOV 33, color 35, kelvin 39
(0 = auto), photo resolution 40, dark EIS 42, flowstate 43, zoom 53, I-Log 72,
Color Recovery 73, gimbal options 91 (`LunaGimbalOptions`), gimbal status 92
(`LunaGimbalStatus`), AF mode 93, pano type 98, remaining time 99, IQ 3A 100
and filter strength 104. The camera sends explicit zeros, so `nil` means the
field was omitted (73, 42 and 43 are always omitted on v1.0.288). The same
parser handles SET success replies (`types`) and notification 8293.

`LunaVideoResolution` / `LunaPhotoSize` map all 476 / 46 schema enum values to
width, height, fps and an `aspectLabel` (Source-backed names).
`LunaVideoResolution.observed` lists the values seen on the wire. Enum fps can
differ from measured: 43 streams at 25 fps, and 30p record banks report 29 in
notification 8234.

### Notifications

`LunaNotification(message:)` decodes camera messages by code; unknown codes
return `.unknown(code:body:)`.

| Code | Case | Evidence |
| ---: | --- | --- |
| 8195 / 8196 | `.battery` / `.batteryLow` | Source-backed; never fired in captures (poll option 11) |
| 8198 | `.storage(cardState:location:kind:)` | Observed; carries no byte counts, re-poll 20/176 |
| 8201 | `.captureStopped(errorCode:uri:)` | Source-backed |
| 8208 | `.captureStatus` (fields 1, 2, 7, 17, 18) | Observed incl. 19-frame pano progress |
| 8234 | `.liveStream(LunaLiveStreamParameters)` | Observed 1280x720@25, 720x1280@25, 1280x960@29 |
| 8248 | `.trackExport(uri:succeeded:)` | Observed; diagnostic log export, not media |
| 8275 | `.subMode(photo:video:sensor:)`, `shootingMode` | Observed after every mode change |
| 8293 | `.photographyChanged(LunaPhotographySettings)` | Observed after resolution SETs |
| 8298 | `.livePhoto(errorCode:mode:)` | Observed (0, 1 OFF) |
| 8302 | `.gimbalStatus(LunaGimbalStatus)` | External measurement + schema shape; not in our takes |
| 8308 | `.screenBattery` | Observed |
| 8315 | `.tracking(state:endReason:detectCountdown:)` | Observed |
| 8317 | `.afSceneChange` | Observed, empty body |

Authorization notifications 8209 / 8228 stay with
`validateAuthorizationNotification(_:)`.

### Media

| Swift | Evidence |
| --- | --- |
| `fileListRequest(mediaType:start:count:location:)` / `fileList(response:)` | Observed shape (media type 2/3/6, limit INT32_MAX, location 2/3); `start` paging Source-backed |
| `fileInfoListRequest(location:)` / `fileInfoList(response:)` -> `[LunaMediaFile]` | Observed; `LunaFileMetadata`: creation stamp, size, duration s/ms, dimension, fps, gamma, sub-media type, codec |
| `fileExtraRequest(_:extraType: .metadata)` | Observed; reply is the same `ExtraMetadata`, parse with `LunaFileMetadata(_:)` |
| `fileExtraRequest(_:extraType: .thumbnail)` / `LunaThumbnail(response:)` | Observed: raw 40-byte header + NV12 (1280x720 video, 1024x768 photo, 1920x960 pano), verified by rendering |
| `stoppedVideo(response:)` | Observed cmd 5 reply URI (size/time omitted) |
| `deleteFiles(_:)` | Observed byte-identical |
| `LunaMediaFile.httpURL(host:)`, `proxyURI` | Observed: player GETs `http://192.168.42.1<uri>` with Range, and `LRV_<stamp>.lrv` for `VID_<stamp>.mp4` |

The official app fetched no HTTP thumbnail; thumbnails come only from cmd 11
type 2. Favorite (cmd 176) was never emitted by the app.

### Known gaps

- Negative EV encoding, manual exposure with an explicit ISO, and every
  Source-backed setter above have no captured official SET.
- `capture_time` units: every captured cmd 15 / 8208 reported 0.
- Battery notification 8195 and gimbal notification 8302 bodies are not captured.
- MOVE `field4` meaning, thumbnail header words 3 and 4, and whether the camera
  accepts `takePicture` / `stopCapture` without the app's `ExtraMetadata`.
- `P05` resolution names are read as 0.5 fps.

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

The 40 XCTest cases cover official-app control, status, notification and
media fixtures (`LunaControlTests.swift`), plus captured request/greeting/live-start bytes, an
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
No captures, owner/device identifiers, credentials or private keys are fixtures;
official-app bodies are inlined as hex with serials, GPS and client UUIDs removed.
