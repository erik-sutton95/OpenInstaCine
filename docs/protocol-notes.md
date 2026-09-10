# Luna Ultra protocol investigation

Updated: 2026-09-10. Scope: establish the connection protocol needed for an
Insta360 adapter, with the same evidence-driven progression used by
OpenPocketCine. This is an investigation ledger, not a completed protocol spec.

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
| BLE to Wi-Fi handoff | Documented for Luna | Timestamped official-app connection and matching BLE/IP logs |
| Device identity | Observed nearby BE80 advertiser with short identifier; attribution to owner's Luna pending | Match discovery with camera on/off state and model/firmware response |
| GATT BE80 / BE81 write / BE82 notify | Source-backed Luna implementation | Actual service discovery, properties, CCCD, MTU and write mode |
| UCD2 framing and protobuf | Source-backed | Complete reassembled transactions with length, IDs, type, status |
| Crypto negotiation and session keys | Source-backed P-256/AES-GCM implementation | Our client negotiates fresh keys and authenticates a response |
| First authorization and cached reconnect | Source-backed, iOS identity value unknown | Separate initial-approval and reconnect transcripts |
| Wi-Fi credentials and AP startup | Source-backed options; may be app-encrypted | Decode our session's response; join returned AP |
| Camera IP, control port, media endpoints | Source-backed candidates | Observe actual phone interface/route and network flows |
| Live enable, codec, packetization | Source-backed leads; local behavior unknown | First independently decoded frame, then sustained live feed |
| Record, exposure, WB, format, battery, storage | Public command leads | Isolated changes with request/reply/status and on-camera confirmation |
| Gimbal/zoom/tracking | Do not infer support from Pocket or camera hardware | Identify protocol then validate each control/capability |
| Clip list, download, playback, delete/star | Implementation leads vary | Read/list/download first; exact clip identity and file integrity |

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

**No local Luna GATT handshake or command has been captured or reproduced yet.**
The owner confirmed the Luna is already paired to the iPhone and placed the
sniffer beside the camera. The next take is an ordinary reconnect, preserving
that existing authorization.

The downloaded profile is Apple's `Bluetooth Logging for iOS`
(`com.apple.bluetooth.logging`), configured to remove itself after four days.
PacketLogger 26.0.0 nevertheless demonstrably receives current iPhone HCI and ACL
traffic in this session; a reinstall has not been required. Its device metadata
reports iOS 26.6.1 (23G83). Paired phone and profile identifiers stay local.
The installed official app is Insta360 2.33.0, build 30451, queried from the phone.
The camera firmware and successful camera-specific handshake still need recording.

`tools/ucd2.py` now provides read-only checksum validation, fragmented-frame
reassembly, and plain-message header parsing. Seven offline tests cover the
external captured checksum fixture, arbitrary split points, coalesced frames,
corruption, size rejection, greeting preservation, and opaque encrypted payloads.
This is analysis tooling; no camera commands or crypto session are implemented.

## Connection milestone order

1. **Fingerprint:** camera identity, advertising, complete GATT table, MTU,
   notification/indication setup, write type and pacing.
2. **Official-app transcript:** first authorization if still available, then two
   ordinary reconnects. Compare direction, timing, request IDs, and state.
3. **Portable codec:** bounded UCD2 parsing/reassembly, protobuf subset, correlated
   replies, crypto framing, malformed/truncated-frame and independent-vector tests.
4. **Own session:** discovery → connect → subscribe → negotiate crypto → camera
   approval → read current Wi-Fi credentials. Generate fresh keys and identity;
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
