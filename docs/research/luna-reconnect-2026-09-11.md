# Luna Ultra: first verified reconnect and preview

Analysis date: 2026-09-11, Europe/Stockholm. Capture: 2026-09-10 UTC.
The owner performed disconnect → reconnect → live view in the official app.
The camera was already paired to this iPhone. The owner confirmed completion;
whether a touchscreen approval prompt appeared was not explicitly reported.

## Hardware and evidence

| Item | Observed value |
| --- | --- |
| Camera | **Insta360 Luna Ultra**, reported in GetOptions response |
| Camera firmware | **v1.0.288** |
| Phone | iPhone 16 Pro Max, iOS **26.6.1 / 23G83** |
| Official app | Insta360 **2.33.0 / 30451** (`com.insta360.oner`) |
| Phone logger | Apple PacketLogger **26.0.0**, live iPhone HCI/ACL |
| RF logger | Nordic BLE sniffer **0.21.0**, nRF52840 |
| Packet analysis | Wireshark/tshark **4.6.8**, local UCD2 parser, FFmpeg/ffprobe |

The camera's GetOptions response contains Options field **15** (serial), **30**
(firmware), and **48** (model). The serial suffix matches the short BE80 advertiser
name observed by both the sniffer and phone logger. This identifies the advertiser
as this Luna; raw serial, address and client identifiers remain private.
Field-name attribution comes from the [public schema](https://github.com/Ripwords/insta360-luna-ultra-desktop/blob/426d643d302d6818a7d536b815ee15f73bb9c29d/scripts/luna-protocol-schema.json);
the actual values and serial match come from this take.

Local evidence directory: `captures/20260910T215020587215Z-luna-reconnect-01/`.
Frame numbers below refer to `network.pcapng`, not the HCI or RF files.

| Original artifact | SHA-256 |
| --- | --- |
| RF `ble.pcap` | `bb0120bcc67509903fa9367f7bdde547e17415f27d17910ad832bb64dc5b0666` |
| Final phone log `phone-reconnect-02.pklg` | `d6817fb08bc71337cbf9ae49dc151e821fe0a95c9f2d4b16c25742904894f1c6` |
| IP `network.pcapng` | `8442ac378f6fdb1ed450adcd8d9646a0e5ef1e9f4cebd4032f4ed761d43dca56` |

The local manifest records exact sizes and hashes. Earlier phone snapshots are
retained separately; the final snapshot has 19,780 PacketLogger records. Generated
protobuf and transport reports contain unredacted values and remain gitignored.

## Verified network path

The phone obtains **192.168.42.82** on the camera network and opens:

- TCP **192.168.42.1:6666** for UCD2 control and preview.
- HTTP **192.168.42.1:80** for a separate request in the same startup window.

The RVI capture contains about **9.06 seconds** of this TCP connection. Its
300-second recording began while waiting for the operator, so it ends shortly
after preview starts. This proves first-picture decoding, not a full 15-second
preview soak or complete disconnect/recovery behavior.

After TCP sequence/retransmission handling, the two directional streams have no
sequence gaps in the captured data:

| Direction | Reassembled bytes | Valid UCD2 frames | Checksum failures | Incomplete tail |
| --- | --- | --- | --- | --- |
| Phone → camera | 3,615 | 94 | 0 | 0 |
| Camera → phone | 49,678 | 132 | 0 | 0 |

All **226 UCD2 frames** pass the checksum independently implemented in
`tools/ucd2.py`. The phone stream also contains a 17-byte prefix before UCD2.

## Startup transcript

| IP frame | Direction | Observed operation |
| --- | --- | --- |
| 144154 | Phone → camera | 17-byte prefix below |
| 144156 | Camera → phone | UCD2 type **05**, empty greeting |
| 144158 | Phone → camera | Command **8**, request ID 1, GetOptions |
| 144160 | Phone → camera | Command **7**, request ID 2, SetOptions; captured, not replayed |
| 144162 | Camera → phone | Response **200**, ID 1; includes serial, firmware and model |
| 144164 | Camera → phone | Response **200**, ID 2 |
| 144166 | Phone → camera | Command **8**, ID 3, more options |
| 144167 | Camera → phone | Response **200**, ID 3 |
| 144169 | Phone → camera | Command **39**, ID 4, authorization check |
| 144170 | Camera → phone | Response **200**, ID 4, authorization status field 1 = **0** |
| 144172 onward | Both | Type **05** heartbeats; option, status and media-library messages |
| 144402 | Phone → camera | Command **1**, ID 77, live-start payload below |
| 144411 | Camera → phone | Response **200**, ID 77, empty body |
| 144448 onward | Camera → phone | Type **01** media, substream **20**, HEVC video |

Command 83 / request ID 5 receives response **500**, while subsequent commands
continue. Record command-level outcomes; neither a valid checksum nor an open
socket establishes that every operation succeeded. RVI batches some timestamps,
so sub-millisecond startup timing is not a reliable latency measurement.

### Prefix before UCD2

```text
11 00 00 00 06 00 00 af fa af fa af fa af fa af fa
```

Its length/type structure resembles the older protocol's SYNC frame, whose
implementation uses a different ten-byte magic. Here the camera responds with a
UCD2 greeting, not the older echo. The meaning of the replacement magic and
whether every connection requires it remain unknown. [Older SYNC framing](https://github.com/xaionaro-go/insta360ctl/blob/f94193ce03c5af0921a9992bfd1af6bd946150d0/pkg/wifi/conn.go).

### Authorization check on Wi-Fi

Request 39 contains:

| Protobuf field | Observed value |
| --- | --- |
| 1 | 36-byte UUID-shaped string; value private |
| 2 | Varint **1** |
| 3 | The same 36-byte UUID string as field 1; value private |

Response 200 contains field 1 = **0**, field 2 = **2**, field 3 = **255**, and
field 4 as a 36-byte string. Status 0 matches the public schema's authorized
value. A newer community schema names request field 3 `device_id`, and initiator
**1 = PHONE_IOS**. Response fields 2/3/4 are `findmy_pair_status`, `findmy_pair_id`
and `device_id`; pair-status 2 is named paired. These labels resolve the field
names but do not establish every Find My behavior on this camera.
[Authorization schema](https://github.com/iliakonnov/insta360-nas/blob/b78dddb9cd9bc2cf632871646c6f5af238e582d4/insta360-server/insta360_messages.proto#L3281).

These TCP messages are plaintext UCD2. This does not disprove the source-backed
encrypted BLE credential flow. Do not replay the official app's private IDs as
our client identity.

## Independently decoded preview

The complete live-start protobuf body is:

```text
10 01 20 80 f7 02 38 2b 50 0e 60 01
```

Decoded fields: **2=1, 4=48000, 7=43, 10=14, 12=1**. Older schema names these
video enable, audio sample rate, two resolution selectors and rotate enable.
Those names are source interpretations; the resulting stream was measured here.

There are **24** captured MEDIA frames: substream **20** ×10, **30** ×4, and
**40** ×10 (hex). Substreams 30/40 remain uninterpreted in this report. Removing
the nine-byte media header from substream 20 yields 19,386 bytes of Annex-B video.

FFprobe/FFmpeg independently parse and decode the resulting elementary stream:

| Property | Observed result |
| --- | --- |
| Codec/profile | **HEVC / Main** |
| Dimensions | **1280×720** |
| Pixel format | **yuv420p**, 8-bit 4:2:0 |
| Signaled range | Limited / `tv` |
| Color primaries, transfer, matrix | **BT.709** for all three |
| Reported rate | **25 fps** |
| Decoded frames | **10** |

The first decoded PNG was visually inspected and shows a real camera image.
Files `preview.hevc` and `first-frame.png` remain private. This is a decoded
capture, not a live OpenInstaCine application session.

The media header's eight bytes after the substream byte, interpreted little-endian,
increase by **40** between these video packets, consistent with milliseconds at
25 fps. Units, epoch and reset behavior still need another take. The phone's
type-05 heartbeats are approximately **2.01 seconds** apart in this window.

This contradicts assumptions that Luna always previews H.264 at 1280×960. The
adapter must consume actual stream headers and negotiated settings rather than
fixing codec/dimensions to earlier external reports.

## Command coverage in this take

Observed phone command numbers:

```text
1, 7, 8, 10, 13, 15, 17, 38, 39, 83, 118, 151, 152,
157, 160, 172, 217, 225, 242, 265
```

The main [source research](insta360-protocol-sources.md) maps the common commands.
Additional primary-source names include 83 prepare file package, 151 prepare file
sync package, 152 finish file sync, 38 file-info list, 118 camera file-access state,
and 17 timelapse options. [MessageCode schema](https://github.com/Ripwords/insta360-luna-ultra-desktop/blob/426d643d302d6818a7d536b815ee15f73bb9c29d/scripts/luna-protocol-schema.json).
Older constants suggest 157 dark/EIS status, 160 cloud-storage upload status and
172 download-file list; Luna semantics still need field-level validation.
[Older command constants](https://github.com/xaionaro-go/insta360ctl/blob/f94193ce03c5af0921a9992bfd1af6bd946150d0/pkg/protocol/messagecode/messagecode.go).
The newer schema names **217** SET_CLOUD_TAB_SHOW, **225** SET_CLOUD_PROMPT_INTERVAL
and **242** GET_FIRMWARE_VERSIONS. **265 remains unnamed.** These names are source
attribution; setting effects require separate validation.
[Newer command enum](https://github.com/iliakonnov/insta360-nas/blob/b78dddb9cd9bc2cf632871646c6f5af238e582d4/insta360-server/insta360_messages.proto#L1246).

The official app sends no record start/stop in this controlled take. Recording,
zoom, gimbal, focus and tracking are not verified by incidental startup queries.

## BLE result and immediate next step

The RF take contains advertisements but **zero target link-data or ATT packets**.
The phone log has other ATT traffic and advertises this camera's identifier, but
contains no `UCD2` bytes or decoded camera command transaction. The data therefore
does not establish the BLE authorization handshake. Reuse of a saved Wi-Fi path
is a plausible explanation for the successful paired reconnect, not a proven
rule about how Insta360 always reconnects.

A subsequent Mac/CoreBluetooth experiment discovered the camera's GATT service,
completed its own authorization with fresh keys and identity, and retrieved
encrypted Wi-Fi credentials. A second session reused that identity successfully.
See the separate [BLE session report](luna-ble-bootstrap-2026-09-11.md); it does
not change the absence of camera ATT in this official-app take.

For the shared engine, these results establish a concrete adapter boundary:
Insta360 transport/framing → timed HEVC access units → shared native feed sink.
They do not justify copying OpenPocketCine's screens or asserting full feature
parity before the engine extraction and camera controls are implemented.
