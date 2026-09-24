# Luna Ultra protocol investigation

Updated: 2026-09-17. Scope: establish the connection protocol needed for an
Insta360 adapter, with the same evidence-driven progression used by
OpenPocketCine. This is an investigation ledger, not a completed protocol spec.

**2026-09-11 result:** our client independently completes BLE authorization,
encrypted Wi-Fi credential retrieval and a saved-identity reconnect on Luna
Ultra v1.0.288. See the [BLE proof](research/luna-ble-bootstrap-2026-09-11.md).
Separately, 226 official-app TCP UCD2 frames pass checksum validation and ten
1280×720 HEVC/BT.709 preview frames decode successfully in the
[network take](research/luna-reconnect-2026-09-11.md).
The saved BLE tool also passed after the owner woke the camera. The Mac then
joined the returned AP and reached its HTTP/TCP listeners; independent UCD2
preview subsequently succeeded in the [Mac viewer](mac-preview.md): 467 decoded
frames in the bounded take, then a displayed feed for over four minutes with
acknowledged stop and a repeated full connection.

## Evidence levels

- **Documented:** official product/SDK documentation.
- **Source-backed:** a public implementation does this; not proof for this body,
  firmware, phone, or client identity.
- **Observed:** identified local packet frames and camera state support the fact.
- **Reproduced:** our client succeeds repeatedly on the identified hardware.
- **Unknown:** no sufficient evidence yet.

The [source research](research/insta360-protocol-sources.md) gives exact citations,
framing, crypto details, and command leads. These labels must stay attached when
moving a claim into code or public documentation.

## Current ledger

| Concern | Current evidence | Next proof |
| --- | --- | --- |
| BLE to Wi-Fi handoff | Complete Mac BLE → AP → TCP authorization → live preview reproduced | Native iOS/Android integration and recovery |
| Device identity | Observed model/firmware; serial suffix matches BE80 advertiser | Repeat after restart and with other models |
| GATT BE80 / BE81 write / BE82 notify | Discovered and used on Mac; CoreBluetooth MTU 515 | Raw ATT/MTU capture; multi-chunk writes; native phone clients |
| UCD2 framing and protobuf | Reproduced BLE request/reply correlation; TCP capture decoded | Sustained session, malformed/recovery cases on hardware |
| Crypto negotiation and session keys | Reproduced fresh P-256/AES-GCM keys and authenticated replies in two sessions | Native ports and disconnect/rekey recovery |
| First authorization and cached reconnect | Reproduced own UUID, initiator 1, approval then status 0 reconnect | Rejection, timeout, camera reboot, initiator 2 |
| Wi-Fi credentials and AP startup | Encrypted GetOptions [36,37,43] credential read and AP join succeed | Establish AP lifetime, sleep/wake and startup requirements |
| Camera IP, control port, media endpoints | Own TCP 192.168.42.1:6666 authorization; HTTP 80 reachable | HTTP file-transfer semantics |
| Live enable, codec, packetization | Own commands 1/2; decoded 1280×720 HEVC/BT.709, 25 fps; 271-second live window | Latency, native decoding, interruption recovery and recording coexistence |
| Record, exposure, WB, format, battery, storage | SET: ISO 160, shutter 1/50, EV +0.3, Standard=1 / I-Log=2 / **Dolby=5**, WB 2000/2400K, sharpness High, zoom 1–6, format enum, record 4/5, photo 3, modes 41, pano 40=8 | Colour Recovery **solved**: screen RPC `iq_ilog_lut.enable`, writable from a Mac once the KCP sequence is primed. See [implementation guide](implementation/luna-color-recovery.md). Phone option 73 remains a no-op on v1.0.288. |
| Gimbal/zoom/tracking | Zoom 1/2/3/6; recenter + flip; FPV/FPV-V/Roll Lock; tap-focus; Deep Track 237; **stick MOVE cmd 226 action 1, sint32 ±99** | Dolby still open; Colour Recovery solved |
| Clip list, download, playback, delete/star | cmd 2 + 118 + 11 + HTTP GET; **delete cmd 12 URI**; star/like not on UCD2; no play/pause opcodes | Filter field 18 unused by iOS live UI |

## Local hardware check

On 2026-09-10 the installed tools identified a Nordic BLE sniffer and an attached
iPhone 16 Pro Max. `nrfutil ble-sniffer` 0.21.0 and Wireshark 4.6.8 captured and
read actual over-the-air packets. A short follow-up capture verified the new
capture helper stops its process group and releases the serial device.
An independently constructed synthetic HCI/ATT packet verified report extraction
of opcode, attribute handle, payload and connection handle, plus manifest creation.
The report command also rejects inputs outside this repo's local capture area.

The initial baseline had no Luna/Insta360-named advertisements; examination by
service UUID found a BE80 candidate. Its identifier/address and original frames
stay in `captures/`. Some received packets have bad Nordic CRC flags; use valid
CRC packets and repetition when establishing identity or bytes. The initial
ad-hoc capture lasted longer than requested because its launcher left a plugin
child running; this is recorded in its metadata. It was stopped, and the new
helper uses process-group shutdown.

The ordinary iPhone reconnect preserved its existing authorization and yielded
network traffic but no camera BLE transaction. After disconnecting that app,
our Mac discovered the GATT table and completed its own authorization. The owner
accepted the prompt, and a second session recognized our saved identity without
another request. Direct client logs contain both exchanges; the RF sniffer still
did not follow target ATT, so do not describe these as decoded over-the-air takes.

The downloaded profile is Apple's `Bluetooth Logging for iOS`
(`com.apple.bluetooth.logging`), configured to remove itself after four days.
PacketLogger 26.0.0 nevertheless demonstrably receives current iPhone HCI and ACL
traffic in this session; a reinstall has not been required. Its device metadata
reports iOS 26.6.1 (23G83). Paired phone and profile identifiers stay local.
The installed official app is Insta360 2.33.0, build 30451, queried from the phone.
The subsequent network capture reports camera firmware v1.0.288 and establishes
the TCP authorization sequence. The later independent client supplies the BLE
credential acquisition evidence.

`tools/ucd2.py` now provides read-only checksum validation, fragmented-frame
reassembly, and plain-message header parsing. Nine offline tests cover the
external captured checksum fixture, arbitrary split points, coalesced frames,
corruption, size rejection, greeting preservation, opaque encrypted payloads,
reviewed greeting/live-start fixtures from this Luna capture, and a stream-sized
checksum regression after accelerating the checksum for network reception.
`tools/luna_wire.py` adds the bootstrap protobuf subset and scheme-3 crypto;
`tools/luna_ble.py` supplies the repeatable connection lab. Ten additional tests
cover independent crypto fixtures, malformed protobuf, key-exchange error enums,
invalid keys, encrypted-response enforcement and private identity persistence.
`tools/luna_tcp.py` adds bounded capture and a live window with two simulated-camera tests.
`tools/luna_mac.py` supplies the verified complete Mac launcher.
Run `just lab-check` for all 21 checks. These are lab tools, not native app code.

## Connection milestone order

1. **Fingerprint:** camera identity, advertising, complete GATT table, MTU,
   notification/indication setup, write type and pacing.
2. **Official-app transcript:** TCP reconnect captured; camera BLE transaction
   missing from that take. Compare future official BLE takes to our own transcript.
3. **Portable codec:** bounded UCD2 parsing/reassembly, protobuf subset, correlated
   replies, crypto framing, malformed/truncated-frame and independent-vector tests.
4. **Own session (first approval and warm reconnect reproduced):** discovery →
   connect → subscribe → negotiate crypto → camera approval → read current
   Wi-Fi credentials. Generate fresh keys and identity;
   never hardcode another client's captured session. Verify cold and warm paths.
5. **Network and picture:** join actual AP → connect observed transport → obtain
   first decoded frame → sustained feed → deliberate disconnect/reconnect.
6. **Controls and media:** one behavior per capture, map proven features into
   capabilities. Exercise on both native platforms before product sign-off.
7. **Shared monitor integration:** consume extracted packages as described in
   [the integration plan](shared-engine-integration.md).

## How this follows OpenPocketCine

The previous app documents scan → GATT/app authorization → camera Wi-Fi → control
transport → live frames and media, with local captures and offline decoders.
Its initial capture guide explicitly used idle/live/exit comparisons and repeat
takes to isolate commands. We reuse that method, logging and portable-core split.

DJI's FFF0/FFF4/FFF5, DUML pairing, 192.168.2.1, UDP 9004 and enable-once watchdog
rules are Osmo behavior, not Luna defaults. Public accessory-emulator protocols
also need role checks: a camera acting as a central for a GPS remote does not
describe the phone connecting to the camera's GATT server.

Local references inspected: OpenPocketCine `9c4e733`, its protocol handbook and
initial `82a78d4:docs/capture-guide.md`; OpenZCine `28bb1143` and its RVI helper.
