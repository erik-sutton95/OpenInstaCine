# Insta360 Luna Ultra protocol research

Research date: **2026-09-10**, amended **2026-09-11**. This document records public-source evidence. Local verification is reported separately in the [BLE bootstrap proof](luna-ble-bootstrap-2026-09-11.md) and [TCP/preview capture](luna-reconnect-2026-09-11.md). Our client has now reproduced fresh-key negotiation, first authorization, encrypted credentials and a saved-identity BLE reconnect on Luna Ultra v1.0.288. Unmeasured commands below remain source leads.

## Findings that change the starting point

There is now Luna-specific public source code for the BLE bootstrap, including an application encryption handshake. The strongest starting reference is `diamondfsd/luna-ai-cut`, whose MIT-licensed source implements BE80/BE81/BE82, UCD2 framing, P-256 key agreement, camera authorization, and encrypted Wi-Fi credential retrieval. Its codecs and tests are implementation evidence; they are not a substitute for a successful capture and independent replay on this Luna Ultra. [BLE codec][ble-codec], [BLE session][ble-session], [protocol tests][ble-tests], [license][luna-license].

A second developer reports actual Luna Ultra Wi-Fi control and monitoring on firmware 1.0.238, with some later observations on 1.0.283. Its useful contribution is explicit separation of measured controls from guessed/stale enums. That project derives some protocol work from the first, so the two are not fully independent evidence. [Feature inventory][features].

**Recommended sequence:** fingerprint this camera's GATT database; capture the official phone's first connection and reconnect; compare its UCD2 bootstrap against these sources; implement and verify our own authorized session; then move to Wi-Fi control and preview. Do not begin by replaying the GPS remote protocol.

## Evidence classes

| Label | Meaning |
| --- | --- |
| Official Luna | Insta360 explicitly documents this behavior for Luna Ultra. |
| Luna implementation | Luna-specific public source implements it; consult the local reports for verification status. |
| External measurement | Another developer names the camera/firmware and reports measuring it. |
| Other model | Evidence concerns another Insta360 camera or accessory. |
| Unknown locally | Requires our own capture or controlled on-device check. |

## Official Luna connection behavior

| Fact | Consequence for OpenInstaCine | Source |
| --- | --- | --- |
| First connection requires authorization on the camera touchscreen. | Capture before opening the official connection screen and annotate the confirmation tap. | [Connecting the device][official-connect] |
| Phone Wi-Fi and Bluetooth must be enabled; app requires network/Bluetooth/local-network permissions. | Test onboarding permissions separately from protocol failures. | [Connecting the device][official-connect] |
| Insta360 app 2.26.2 or later is specified. BLE identifies camera Wi-Fi information; the app connection cannot use BLE alone. | BLE bootstrap leads into the camera Wi-Fi network for full operation. | [Phone/tablet connection][official-phone] |
| Wi-Fi password is available in the camera's Wi-Fi settings; manual joining is supported. | A manual Wi-Fi path can independently unblock TCP/preview research. | [Phone/tablet connection][official-phone] |
| Main unit: Wi-Fi 6, 802.11 a/b/g/n/ac/ax; detachable screen: Wi-Fi 4, b/g/n; Bluetooth listed as BR/EDR/BLE. | Distinguish camera-phone, camera-screen, and accessory links in captures. | [Hardware specifications][official-spec] |
| Luna Bluetooth wakeup is documented for iOS, after a previous successful connection and enabling wakeup. | Capture power-on pairing separately from later powered-off wakeup. | [Bluetooth wakeup][official-wakeup] |
| Listed Bluetooth accessories are Mic Air, Mic Pro, and POV Head Tracker; GPS data import is not supported. | X-series GPS remote results do not establish Luna accessory compatibility. | [Compatibility][official-compat] |

## Source versions and reuse

| Repository | Inspected revision | Use |
| --- | --- | --- |
| `diamondfsd/luna-ai-cut` | `ad47c16929b1b086c0a369fc2b4b5ece5b63f4df`, 2026-09-09 | Main BLE/TCP implementation reference. Root LICENSE is MIT, copyright 2026 diamondfsd. Preserve attribution if incorporating code. |
| `Ripwords/insta360-luna-ultra-desktop` | `426d643d302d6818a7d536b815ee15f73bb9c29d`, 2026-08-04 | Hardware measurement reports, command IDs and capture fixtures. No root license was found in the inspected tree; treat as an evidence reference, not code to vendor without resolving permission. |
| `xaionaro-go/insta360ctl` | `f94193ce03c5af0921a9992bfd1af6bd946150d0`, 2026-03-01 | Older model BLE variants. Predates Luna release; not a Luna implementation. |
| `iliakonnov/insta360-nas` | `b78dddb9cd9bc2cf632871646c6f5af238e582d4` | Newer community protobuf: crypto/error enums, authorization fields and command names. Used as a schema reference; not vendored. |
| `Insta360Develop/Insta360-Developer_Docs` | `caa3700d0bf2a1b96317211f64431bcd0dfe11c0`, 2026-09-08 | Current official SDK model/support scope. |

Revision metadata came from the repositories' GitHub commit endpoints; all source links below are pinned where possible. [Luna commit][luna-commit], [desktop commit][desktop-commit], [older CLI commit][old-commit], [official docs commit][docs-commit]. The Luna repository describes itself as a noncommercial project, while its inspected LICENSE grants MIT permissions; do not confuse the project's description with its actual license file. [README][luna-readme], [LICENSE][luna-license].

## BLE GATT and transport candidate

Entries originated as **Luna implementation** leads. BE80/BE81/BE82 and write-with-response now match our successful Mac session; its complete discovered table and CoreBluetooth MTU are in the [BLE report](luna-ble-bootstrap-2026-09-11.md). [BLE codec][ble-codec], [Web Bluetooth connection code][ble-browser], [transport][ble-transport].

| Role | UUID / behavior |
| --- | --- |
| Camera service | `0000be80-0000-1000-8000-00805f9b34fb` |
| App → camera | `0000be81-0000-1000-8000-00805f9b34fb` |
| Camera → app notifications | `0000be82-0000-1000-8000-00805f9b34fb` |
| Source write mode | ATT write with response; deprecated `writeValue` fallback. |
| Source chunk size | At most 206 bytes per sequential write. This is a source constant, not evidence of our negotiated MTU. |
| Discovery | Service-filtered scan, then discover service/characteristics and subscribe before sending commands. |
| Receive model | Accumulate notification chunks into complete UCD2 frames. Notification boundaries are not message boundaries. |

The service is shared with other Insta360 families. A BE80 match alone does not prove Luna identity. Discover handles and properties rather than copying handles. CoreBluetooth's permitted write length and the observed ATT MTU must govern the eventual Swift transport.

The source resolves its initialization wait on **any first notification**, with a five-second deadline. It calls UCD2 type `0x05` STREAM an initialization heartbeat, but does not establish an exact mandatory initial payload. Its receive code clears the entire buffer on that type. Preserve the actual first bytes and trailing frames in our capture/parser; do not interpret that implementation shortcut as a protocol specification. [BLE session][ble-session].

## UCD2 framing candidate

The following layout is implemented by the Luna BLE codec. Multi-byte integers are little-endian. [BLE codec][ble-codec].

### Plain MESSAGE frame

| Offset | Bytes | Field |
| --- | --- | --- |
| 0 | 4 | ASCII `UCD2` = `55 43 44 32` |
| 4 | 1 | Version `01` |
| 5 | 1 | Header length `0C` (12 bytes) |
| 6 | 1 | Type `04`, command/response message |
| 7 | 1 | Frame sequence, eight-bit counter |
| 8 | 4 | Message byte length; excludes outer header and checksum |
| 12 | 2 | Command or response code |
| 14 | 1 | Content type `02`, protobuf |
| 15 | 4 | Message ID and flags; request builder sets `messageId OR 0x80000000` |
| 19 | 2 | Reserved zero in request builder |
| 21 | variable | Protobuf body |
| end − 4 | 4 | Packet checksum |

Total length = `12 + messageLength + 4`; message length = `9 + protobufLength`.

The BLE parser extracts a 30-bit message ID with mask `0x3FFFFFFF`. It does not interpret both high flag bits. The source increments message IDs starting at 1, wraps after `0x3FFFFFFE`, and wraps frame sequence modulo 256. These are source counter policies, not yet measured required initial values. It matches responses by message ID; response code decimal `200` (`0x00C8`) is associated with the pending command. This is a binary protocol response code, not an HTTP response. [BLE session][ble-session].

The TCP implementation encodes the same nine-byte inner header using a 16-bit request ID followed by a 32-bit flags field `0x00008000`. For IDs below 65536 this is byte-identical to the BLE representation. The two source parsers therefore do not establish support for larger TCP IDs. Keep raw header bytes and avoid silently truncating IDs in a shared codec. [TCP codec][tcp-codec].

### Checksum

Both Luna codecs implement an unusual CRC-like checksum: start at `0xFFFFFFFF`; use an MSB-first table for polynomial `0x04C11DB7`; XOR each input byte into the accumulator's **low** byte; perform **four** table rounds per input byte; append the final accumulator as little-endian with no final XOR. Do not substitute ordinary CRC-32, CRC32C, or `zlib.crc32`. [BLE codec][ble-codec], [TCP codec][tcp-codec].

An external project's test identifies this full frame as captured, including its checksum:

```text
55 43 44 32 01 0c 04 10 0f 00 00 00
08 00 02 01 00 00 80 00 00
08 30 08 0f 08 0b
7c 00 8e 7c
```

Interpretation: sequence `0x10`, command 8, request ID 1, GetOptions fields `[48,15,11]`, checksum `0x7C8E007C`. This is an external fixture; our capture must supply independent vectors. [Rust codec fixture][desktop-codec].

### Encrypted MESSAGE frame, scheme 3

| Offset | Bytes | Field |
| --- | --- | --- |
| 0–11 | 12 | Same outer base header, except byte 5 = `2B` (43); length at 8 is ciphertext length |
| 12 | 1 | Encryption option type `40` |
| 13 | 1 | Option value length `1D` (29) |
| 14 | 1 | Encryption scheme `03` |
| 15 | 12 | AES-GCM nonce |
| 27 | 16 | AES-GCM authentication tag |
| 43 | variable | Ciphertext of the **entire nine-byte inner message header plus protobuf body** |
| end − 4 | 4 | Same checksum over the outer header, option and ciphertext |

AES-GCM additional authenticated data is exactly bytes `0..11`, including header length, sequence and ciphertext length. Total size is `43 + ciphertextLength + 4`. The source uses a new random 12-byte nonce per encrypted message; there is no nonce counter construction in this implementation. [BLE codec][ble-codec].

## Application encryption and authorization sequence

The newer [community protobuf schema][new-schema] resolves encryption success to
`ENCRYPT_ERROR_NONE = 1`; scheme 3 is AES-GCM-128. It also names the newer
authorization identity and Find My fields. This is community source attribution,
not an official specification.

This is the sequence in `readWifiCredentials()`, not a proven minimal handshake. It requests encryption only for the **final Wi-Fi GetOptions message**; initialization and authorization messages use the plain builder even after key agreement. [BLE session][ble-session].

| Step | Direction / code | Body / condition |
| --- | --- | --- |
| 1 | Subscribe BE82, await notification | First notification ends source initialization wait. |
| 2 | Request 8 (`0x0008`) GET_OPTIONS | Device options `[48,15,11]`. |
| 3 | Request 240 (`0x00F0`) ENCRYPT_CAPABILITY_QUERY | Empty protobuf; response field 1 supplies schemes, packed or unpacked. Require scheme 3. |
| 4 | Request 241 (`0x00F1`) ENCRYPT_KEY_EXCHANGE | Field 1 varint = 3; field 2 bytes = uncompressed 65-byte P-256 public key. Encoded prefix `08 03 12 41`, then key. |
| 5 | Response to key exchange | Field 1 error code; field 2 camera public key. Source ignores the error enum; the newer schema establishes **1 = no error**, not 0. Our client validates both. |
| 6 | Request 8, initialization A | `[30,19,37,22,67,97,89,116,115,114,110,85,156,135,103,150]`. |
| 7 | Request 8, initialization B | `[149,11,147,167,157,158,180,20,165]`. |
| 8 | Request 39 (`0x0027`) CHECK_AUTHORIZATION | Source uses field 1 authorization ID and field 2 Android initiator 2. Our iPhone capture additionally has field 3 device ID, equal to field 1, with initiator **1 = PHONE_IOS**. Our client reproduces this using its own UUID. |
| 9 | Authorization-check response | Status field 1: 0 → already authorized; 1 → request permission; other → fail in this source. |
| 10 | If needed: request 86 (`0x0056`) REQUEST_AUTHORIZATION | Field 1 = 1, named WIFI_PASSWORD. Protobuf `08 01`. |
| 11 | Await asynchronous result | Code 8209 (`0x2011`) or 8228 (`0x2024`); field 1 result, field 2 operation. Source waits 20 seconds. |
| 12 | **Encrypted** request 8 | GetOptions `[36,37,43]`: Wi-Fi info, channel list, status. Protobuf `08 24 08 25 08 2b`. |
| 13 | Decode credentials | GetOptions response field 2 → Options field 36 → Wi-Fi info field 1 SSID, field 2 password. |

Source result values: `0` success, `1` rejected, `2` timeout, `3` busy. Its notification acceptance permits operation 1 or 0. Check status/result semantics against successful and rejected captures; do not equate every code 200 with user authorization. [BLE codec][ble-codec], [BLE session][ble-session].

### Key derivation, exactly as the implementation expresses it

```text
curve = prime256v1 / secp256r1 / NIST P-256
localPublicKey = 04 || X[32] || Y[32]
sharedSecret = ECDH(localPrivateKey, cameraPublicKey)
PRK = HMAC-SHA256(key=UTF8("UCD2-ENCRYPT"), data=sharedSecret)
block = HMAC-SHA256(key=PRK, data=UTF8("AES-SESSION-KEY") || 01)
AESKey = first 16 bytes of block
cipher = AES-128-GCM
```

This is the one-block HKDF-SHA256 construction for a 16-byte result, with those exact salt/info strings and no terminating NUL. The public key is uncompressed, 65 bytes, first byte 4. The source crypto tests exchange two generated keys and round-trip ciphertext; they provide useful regression coverage but no independent official-app ciphertext fixture. [BLE codec][ble-codec], [tests][ble-tests].

**Capture implication (inference):** this is application-layer encryption inside GATT. Even a phone HCI logger that sees plaintext ATT, or an RF capture whose BLE link encryption can be decoded, may still contain encrypted Wi-Fi credentials. Public ECDH keys and packets alone do not yield the session key. Captures can verify order, framing, public keys and encrypted envelopes; an independently authorized client derives the key for its own session. A Bluetooth logging app that only enumerates GATT is not equivalent to an HCI/PacketLogger capture of the official app.

## Wi-Fi control and preview candidate

Public Luna implementations use camera `192.168.42.1`, TCP port **6666** for UCD2 control, and HTTP port **80** for files. A persistent TCP session enables HTTP media access. Current file listing uses GET_FILE_LIST; the older HTML autoindex reportedly disappeared in firmware 1.0.238. Discover the actual network gateway on our connection. [Desktop connection description][desktop-readme], [feature measurements][features].

The current MIT implementation opens TCP, sends a type `0x05` UCD2 STREAM greeting with zero payload, and keeps the session alive by repeating it every **1500 ms**. A successful TCP write alone does not prove camera readiness: its stronger probe requests capture status (15) and checks response 200. Another implementation uses three-second keepalive cycles plus queries. Capture actual official-app intervals instead of treating either value as a camera requirement. [TCP session][tcp-session], [Luna client][luna-client], [desktop implementation][desktop-codec].

### Command inventory

IDs below are evidenced in Luna-specific public source. “Implemented” does not mean locally verified, and support over **Wi-Fi** does not establish that the same operation works over **BLE**. [Luna desktop command constants][desktop-codec].

| Decimal / hex | Command | Luna evidence and remaining work |
| --- | --- | --- |
| 1 / `0001` | START_LIVE_STREAM | Both Luna implementations use it. Validate actual codec, dimensions, latency and recording coexistence. |
| 2 / `0002` | STOP_LIVE_STREAM | Empty body in both implementations. |
| 3 / `0003` | TAKE_PICTURE | External Luna project reports still capture. Verify mode-dependent body and completion event. |
| 4 / `0004` | START_CAPTURE | External project reports recording; capture mode changes request payload. |
| 5 / `0005` | STOP_CAPTURE | External project reports recording stop. Establish failure/busy/end-of-recording semantics. |
| 7 / `0007` | SET_OPTIONS | Device settings; field availability remains model/firmware-specific. |
| 8 / `0008` | GET_OPTIONS | BLE bootstrap and Wi-Fi device information. |
| 9 / `0009` | SET_PHOTOGRAPHY_OPTIONS | Exposure, color, zoom etc. require function-mode and option mapping. |
| 10 / `000A` | GET_PHOTOGRAPHY_OPTIONS | Needed for snapshots and controlled setting diffs. |
| 12 / `000C` | DELETE_FILES | Exists; unnecessary for connection/monitor research. Do not include in bootstrap probes. |
| 13 / `000D` | GET_FILE_LIST | Source pages media; internal storage location = 2, SD = 3; page size 50. |
| 15 / `000F` | GET_CURRENT_CAPTURE_STATUS | Empty request body in current MIT probe; useful initial read-only response check. |
| 39 / `0027` | CHECK_AUTHORIZATION | BLE flow above. |
| 86 / `0056` | REQUEST_AUTHORIZATION | BLE Wi-Fi-password permission request above. |
| 240 / `00F0` | ENCRYPT_CAPABILITY_QUERY | Scheme discovery. |
| 241 / `00F1` | ENCRYPT_KEY_EXCHANGE | Scheme 3 key agreement. |

The implemented live-start protobuf is:

```text
10 01 30 28 38 09 40 01 48 28 50 12
# varint fields: 2=1, 6=40, 7=9, 8=1, 9=40, 10=18
```

Source names suggest video enabled, bitrate/resolution pairs and gyro enabled. The old enum labels for resolutions must not be used as evidence of the actual Luna dimensions. [Live-start builder][live-commands], [external live-start fixture][desktop-live].

Video is multiplexed with command replies on the **same TCP connection**, in UCD2 type `0x01` MEDIA frames. A nine-byte media header precedes the elementary video bytes; its first byte selects substream, with `0x20` treated as video. Type `0x05` STREAM is a greeting/heartbeat, despite its misleading name. [TCP codec][tcp-codec], [TCP receiver][tcp-session].

The external Luna project reports an H.264 preview at **1280×960** and no confirmed preview-resolution control. Decode the actual SPS/PPS and, if present, HEVC VPS rather than assuming codec or dimensions; some source fixtures/legacy enums describe other models. The localhost HTTP endpoint used by these desktop apps is their own bridge, not proof of a camera RTSP/RTMP endpoint. [Feature measurements][features], [live-view implementation][desktop-live].

For the shared monitor engine, the vendor layer should deliver timed H.264/H.265 access units after UCD2 demultiplexing. It must retain raw timestamps/header bytes until timebase and metadata are understood. Rendering, GPU image processing, monitoring tools, LUTs, and display behavior can then remain vendor-neutral. This is an integration recommendation, not a claim that Luna preview timing or color metadata is already mapped.

## Settings and gimbal gaps that affect app parity

External firmware-1.0.238 measurements report photography color-mode field 35 as Standard=1, I-Log=2, Dolby Vision=5; filter field 18 and strength field 104; Pano photo submode=8. The important lesson is that stale enum values can be accepted and echoed while the camera displays a different setting. Verify writes on the camera screen and actual captured metadata, not merely a protocol success response. [Calibration findings][calibration].

The external project cited below had not mapped gimbal pan/tilt, tap-to-focus, or Deep Track command numbers. It identifies names such as `PHONE_COMMAND_GIMBAL_CONTROL`, `PHONE_COMMAND_OPEN_TRACKING_WITH_RECT`, and focus commands, but names are not numeric IDs or payload schemas. Code 8302 was correlated with pan-limit state there, with the semantic name still an inference. This makes isolated official-app joystick, tracking and focus actions high-value capture targets **after** connection and preview work. [Protocol gap][protocol-gap].

A newer [command enum][new-schema] supplies candidate IDs **226** gimbal control,
**230/231** open/close tracking, **237** open tracking with rectangle, **238**
cancel tracking and **239** get PTZ track state. These are useful capture targets,
not verified Luna capabilities or safe-to-guess payloads.

Preview I-Log/Dolby Vision behavior, color metadata, camera color-recovery monitoring, lens switching, zoom interpolation, gimbal velocity/position semantics, autofocus, touchscreen coexistence, disconnect/reconnect, and recording-time preview all remain locally unknown. App UI parity does not establish camera feature parity.

## Other-model references: useful, but a separate protocol family

| Reference | Actual scope | Relevance |
| --- | --- | --- |
| [pchwalek ESP32 implementation][remote-esp32] | X3 and RS 1-inch, GPS remote emulation | Camera connects as central to a remote peripheral exposing CE80/CE81/CE82. `FC EF FE` button messages are not the phone's BE80 protocol. |
| [TheAngryRaven GPS specification][gps-spec] | X4 plus GPS remote, author reports passive nRF52840 measurements | Useful for RF workflow, remote role reversal and ORBIT wake advertisements; not proof of Luna wake bytes. |
| [xaionaro-go protocol][old-protocol] | Older direct-control models and GO variants | Describes BE80 direct control with Header16 or GO wrapping, distinct from this Luna UCD2 implementation. |

An nRF52840 capture can observe BLE, but Luna also has Bluetooth BR/EDR and a Wi-Fi-connected detachable display. Absence of desired traffic on one BLE stream does not establish absence of all wireless traffic.

## Official SDK route

The current official iOS guide lists X6 through ONE-series panoramic models, with **no Luna**. Android V2 covers **X, ACE and GO**, while legacy V1 is X-only; no Luna coverage is stated there either. Desktop CameraSDK is described as USB-only, Windows/Linux, again without Luna. The official OSC guide also omits Luna. Lack of a listing is **unconfirmed support**, not proof that every SDK call fails. [iOS guide][sdk-ios], [Android guide][sdk-android], [desktop guide][sdk-desktop], [OSC guide][sdk-osc].

The SDK application accepts personal or enterprise applicants and links an EULA; the form says results arrive within three business days. This research submitted no application. [SDK application][sdk-apply].

The linked EULA, marked 2023-09-21, is proprietary: it grants a limited royalty-free license and permits SDK distribution inside an application, while restricting standalone distribution, SDK reverse engineering/modification, some open-source combinations, imitation of Insta360 software, and use of its name/marks. It also contains rights granted back to Insta360. These are practical SDK-adoption terms to inspect before adding binaries; they are not a technical reason to stop observational interoperability work. [SDK EULA, sections 3, 4, 9 and 10][sdk-eula].

The source-based protocol path is presently better aligned with a reusable monitoring engine because Luna support and redistribution terms are not established for the official SDK. An SDK inquiry could run separately, without blocking captures or assuming the SDK solves gimbal control.

## Next evidence to collect

The list below was the initial research plan. Our GATT discovery, first approval,
warm BLE reconnect, and encrypted credential retrieval are now complete. The
official-app TCP/first-picture take is decoded and our Mac joined the camera AP.
Own-client TCP authorization and a sustained Mac live window subsequently passed
([report](../mac-preview.md)); native platforms, rejection/reboot/recovery and
camera controls remain outstanding.

1. **Identity and GATT:** powered-on advertising, manufacturer data, address behavior, service discovery, characteristic properties, CCCD writes, ATT MTU, first notification, and device/app/firmware versions.
2. **First official-app connection:** record the on-camera confirmation moment, plain command order, crypto scheme/public-key exchange, authorization ID and initiator, response correlation, and encrypted message boundaries.
3. **Reconnect:** repeat without forgetting/clearing the pairing and compare skipped steps, authorization persistence, Wi-Fi credential request and BLE disconnect timing.
4. **Controlled rejection:** if a permission screen is available naturally, capture Cancel separately; do not reset the camera just to manufacture a first pairing.
5. **Wi-Fi session:** record assigned IP/gateway, TCP endpoints, UCD2 greeting, keepalive interval, initial reads, live-start/stop, actual video codec/dimensions/timing, and HTTP file access behavior.
6. **Independent replay:** after confirming this camera's fingerprint, use our own identity and ephemeral key pair to obtain authorized Wi-Fi credentials and a read-only capture-status response. Save successful sanitized fixtures.
7. **One action per capture:** record start/stop, ISO, shutter, WB, color, resolution, zoom, joystick axis, recenter, focus and tracking. Log the camera-screen state before and after each action.

Completion of bootstrap means reproducible discovery → authorization → Wi-Fi join → positively matched camera response, including reconnect and rejected/timeout behavior. Completion of monitoring adds sustained preview with measured latency and recovery. BLE discovery alone is neither milestone.

## Sources

[official-connect]: https://onlinemanual.insta360.com/lunaultra/en-us/camera/insta360app/connectingthedevice
[official-phone]: https://onlinemanual.insta360.com/lunaultra/en-us/operation-tutorials/connection/phones-tablets
[official-spec]: https://onlinemanual.insta360.com/lunaultra/en-us/specs/specs
[official-wakeup]: https://onlinemanual.insta360.com/app/en-us/operation-tutorial/camera-connection/bluetooth-wakeup
[official-compat]: https://onlinemanual.insta360.com/lunaultra/en-us/specs/compatibility
[luna-commit]: https://api.github.com/repos/diamondfsd/luna-ai-cut/commits/ad47c16929b1b086c0a369fc2b4b5ece5b63f4df
[desktop-commit]: https://api.github.com/repos/Ripwords/insta360-luna-ultra-desktop/commits/426d643d302d6818a7d536b815ee15f73bb9c29d
[old-commit]: https://api.github.com/repos/xaionaro-go/insta360ctl/commits/f94193ce03c5af0921a9992bfd1af6bd946150d0
[docs-commit]: https://api.github.com/repos/Insta360Develop/Insta360-Developer_Docs/commits/caa3700d0bf2a1b96317211f64431bcd0dfe11c0
[luna-readme]: https://github.com/diamondfsd/luna-ai-cut/blob/ad47c16929b1b086c0a369fc2b4b5ece5b63f4df/README.md
[luna-license]: https://github.com/diamondfsd/luna-ai-cut/blob/ad47c16929b1b086c0a369fc2b4b5ece5b63f4df/LICENSE
[ble-codec]: https://github.com/diamondfsd/luna-ai-cut/blob/ad47c16929b1b086c0a369fc2b4b5ece5b63f4df/electron/devices/insta360/lunaBleCodec.ts
[ble-session]: https://github.com/diamondfsd/luna-ai-cut/blob/ad47c16929b1b086c0a369fc2b4b5ece5b63f4df/electron/devices/insta360/lunaBleSession.ts
[ble-browser]: https://github.com/diamondfsd/luna-ai-cut/blob/ad47c16929b1b086c0a369fc2b4b5ece5b63f4df/electron/devices/insta360/lunaBleWebBluetoothScripts.ts
[ble-transport]: https://github.com/diamondfsd/luna-ai-cut/blob/ad47c16929b1b086c0a369fc2b4b5ece5b63f4df/electron/devices/insta360/lunaBleWebBluetoothTransport.ts
[ble-tests]: https://github.com/diamondfsd/luna-ai-cut/blob/ad47c16929b1b086c0a369fc2b4b5ece5b63f4df/scripts/test-luna-ble-protocol.mjs
[tcp-codec]: https://github.com/diamondfsd/luna-ai-cut/blob/ad47c16929b1b086c0a369fc2b4b5ece5b63f4df/electron/devices/insta360/insta360TcpCodec.ts
[tcp-session]: https://github.com/diamondfsd/luna-ai-cut/blob/ad47c16929b1b086c0a369fc2b4b5ece5b63f4df/electron/devices/insta360/insta360TcpProtocol.ts
[luna-client]: https://github.com/diamondfsd/luna-ai-cut/blob/ad47c16929b1b086c0a369fc2b4b5ece5b63f4df/electron/devices/insta360/lunaProtocol.ts
[live-commands]: https://github.com/diamondfsd/luna-ai-cut/blob/ad47c16929b1b086c0a369fc2b4b5ece5b63f4df/electron/devices/insta360/lunaControlMessages.ts
[desktop-readme]: https://github.com/Ripwords/insta360-luna-ultra-desktop/blob/426d643d302d6818a7d536b815ee15f73bb9c29d/README.md
[features]: https://github.com/Ripwords/insta360-luna-ultra-desktop/blob/426d643d302d6818a7d536b815ee15f73bb9c29d/docs/FEATURES.md
[desktop-codec]: https://github.com/Ripwords/insta360-luna-ultra-desktop/blob/426d643d302d6818a7d536b815ee15f73bb9c29d/src-tauri/src/luna.rs
[desktop-live]: https://github.com/Ripwords/insta360-luna-ultra-desktop/blob/426d643d302d6818a7d536b815ee15f73bb9c29d/src-tauri/src/liveview.rs
[calibration]: https://github.com/Ripwords/insta360-luna-ultra-desktop/blob/426d643d302d6818a7d536b815ee15f73bb9c29d/docs/superpowers/specs/2026-07-25-camera-protocol-calibration.md
[protocol-gap]: https://github.com/Ripwords/insta360-luna-ultra-desktop/blob/426d643d302d6818a7d536b815ee15f73bb9c29d/docs/PROTOCOL-GAP.md
[remote-esp32]: https://github.com/pchwalek/insta360_ble_esp32/blob/main/Insta_BLE.ino
[gps-spec]: https://github.com/TheAngryRaven/insta360-ble-gps-spec/blob/main/README.md
[old-protocol]: https://github.com/xaionaro-go/insta360ctl/blob/f94193ce03c5af0921a9992bfd1af6bd946150d0/doc/protocol.md
[sdk-ios]: https://github.com/Insta360Develop/Insta360-Developer_Docs/blob/caa3700d0bf2a1b96317211f64431bcd0dfe11c0/docs/en/sdk/x-ace-go/ios/guide.md
[sdk-android]: https://github.com/Insta360Develop/Insta360-Developer_Docs/blob/caa3700d0bf2a1b96317211f64431bcd0dfe11c0/docs/en/sdk/x-ace-go/android/guide.md
[sdk-desktop]: https://github.com/Insta360Develop/Insta360-Developer_Docs/blob/caa3700d0bf2a1b96317211f64431bcd0dfe11c0/docs/en/sdk/x-ace-go/desktop/guide.md
[sdk-osc]: https://github.com/Insta360Develop/Insta360-Developer_Docs/blob/caa3700d0bf2a1b96317211f64431bcd0dfe11c0/docs/en/sdk/x-ace-go/osc/guide.md
[sdk-apply]: https://www.insta360.com/sdk/apply
[sdk-eula]: https://www.insta360.com/support/supportcourse?post_id=20734

[new-schema]: https://github.com/iliakonnov/insta360-nas/blob/b78dddb9cd9bc2cf632871646c6f5af238e582d4/insta360-server/insta360_messages.proto
