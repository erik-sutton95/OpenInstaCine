# Luna Ultra detached-screen UDP control

Measured **2026-09-11**, using the finalized private capture `20260911T130348Z-luna-screen-confirmed-live/reconnect.pcapng` and its decrypted `udp.tsv` export. This was an offline analysis; it performed no hardware actions or network connections. The separate capture operator obtained the user's confirmation of attachment, detachment and an updating screen picture.

**The screen control link uses KCP over UDP, carrying a previously unmapped binary RPC protocol with readable JSON state. It is distinct from the phone's TCP/UCD2 protocol.** This capture establishes substantial framing and state-query behavior, but not a complete new-client bootstrap or an independently usable pre-Color-Recovery feed.

## Evidence and capture limits

The camera endpoint is `192.168.42.1:6000`; the screen endpoint is `192.168.42.253:6021`. The separate `6002 ↔ 6023` channel is being analyzed for media and is outside this note's reconstruction scope. Endpoint addresses are observations for this session, not values a future adapter should assume universally.

The capture operator recovered all four WPA2 EAPOL handshake messages at frames 9394, 9397, 9400 and 9401, around **13:05:26 UTC**. Wireshark successfully decrypted the link using privately stored camera credentials. This analysis consumed the finalized UDP export, which the operator restricted to FCS-good packets. It did not read or publish the private Wireshark key configuration.

Control-channel accounting:

| Measurement | Result |
| --- | ---: |
| Captured UDP datagrams, including retries | 13,220 |
| Datagrams with the 802.11 retry flag | 2,594 |
| KCP PUSH segments before sequence deduplication | 7,112 |
| KCP ACK segments before deduplication | 8,239 |
| Repeated PUSH sequence numbers, identical payloads | 974 |
| Conflicting payloads for a repeated PUSH sequence | 0 |
| Unique screen-to-camera PUSH segments | 3,142 |
| Unique camera-to-screen PUSH segments | 2,996 |
| Complete reconstructed application messages | 5,999 |
| Reconstructed messages matching the inner length field | 5,999 |

Several KCP segments can share one UDP datagram, so segment and datagram counts differ. The parser splits every segment, deduplicates by direction/conversation/sequence, orders by sequence, and joins only contiguous descending-fragment chains ending at fragment zero. It does not concatenate captured UDP datagrams or treat radio retries as new application commands.

This is an incomplete monitor capture of application traffic: **1,090 screen-side and 156 camera-side sequence numbers are absent inside their respective observed ranges**, and five incomplete fragment chains were discarded. Missing capture data does not prove the receiving device lost those messages. FCS-good frames and successful decryption do not make the application capture complete.

The first observed screen/camera PUSH sequence numbers are **6173 / 5973**, not zero. The reconstructed interval is **13:05:26.878–13:07:44.803 UTC**. RPC identifiers are also already advanced. These facts support a **resumed logical session after Wi-Fi reconnection**; they do not establish exactly where the prior session was transported or initialized.

## KCP transport

The observed layout matches the original KCP implementation, including the 24-byte header, little-endian fields, PUSH=81 and ACK=82. Only these two command values occur here. [Pinned KCP implementation][kcp]

| UDP segment offset | Size | Interpretation |
| --- | ---: | --- |
| 0 | 4 | Conversation ID; observed control value `0x001e0007` |
| 4 | 1 | Command: `0x51` PUSH or `0x52` ACK |
| 5 | 1 | Remaining-fragment count |
| 6 | 2 | Advertised receive window; observed 256, occasionally 255 |
| 8 | 4 | KCP timestamp |
| 12 | 4 | Sequence number |
| 16 | 4 | UNA, next sequence not yet acknowledged |
| 20 | 4 | Segment payload length |
| 24 | variable | Segment payload |

Two-fragment messages occur, with fragment values 1 then 0. The conversation ID is session evidence, not a proven fixed product constant. ACKs belong to transport reliability and must not be interpreted as camera command success. KCP itself supplies neither encryption nor an application command schema. [KCP source][kcp]

## Inner envelope and observed reconnect exchange

Every complete reconstructed message has this **12-byte envelope**:

| Offset | Size | Observed interpretation |
| --- | ---: | --- |
| 0 | 1 | Envelope kind: `0` for ordinary reconstructed messages; `2` in the direct reconnect exchange |
| 1 | 2 | First little-endian routing value, consistent with a source endpoint |
| 3 | 2 | Second little-endian routing value, consistent with a destination endpoint |
| 5 | 3 | Little-endian payload length, exactly total message length minus 12 |
| 8 | 4 | Unmapped changing value; integrity/checksum semantics unverified |
| 12 | variable | Application payload |

Routing values swap in matching requests and responses. For example, the GUI query goes from `0x0814` to `0x0405`; its response reverses those values. This supports the routing interpretation without identifying the internal processes behind the numbers. Ordinary IEEE CRC-32 variants and selected existing UCD2-checksum candidates did not explain bytes 8–11. **This audit does not claim application-envelope checksum validation.**

Before the first observed KCP control segment, a short exchange uses the same envelope shape directly over UDP:

| Time UTC / frame | Direction | Outer routing values | Thirteen-byte payload, parsed structurally |
| --- | --- | --- | --- |
| 13:05:26.866427 / 9418 | Camera → screen | `0x0400 → 0x0000` | byte `0`; LE32 `2007`; LE32 `0x001e0007`; LE32 `4` |
| 13:05:26.866446 / 9419 | Camera → screen | Same | Identical radio retry |
| 13:05:26.868126 / 9423 | Screen → camera | `0x0800 → 0x0000` | byte `1`; LE32 `2007`; LE32 `0x001e0007`; LE32 `3` |

Each is 25 bytes total, with envelope kind 2 and payload length 13. The embedded conversation value matches subsequent control KCP traffic. The meanings of `2007`, the leading byte and the terminal values remain unmapped. This is an **observed reconnect exchange**, not a demonstrated complete authentication or initial pairing handshake.

## RPC header and property traffic

The payload begins with a consistent ten-byte RPC-like header in all 5,999 reconstructed messages:

| Offset within envelope payload | Size | Interpretation supported by matching traffic |
| --- | ---: | --- |
| 0 | 1 | Constant `1`, candidate version |
| 1 | 2 | Little-endian service/group ID |
| 3 | 2 | Little-endian method ID |
| 5 | 1 | Message category/flags |
| 6 | 4 | Little-endian request/message identifier |
| 10 | variable | Method-specific data |

Category 0 behaves as a request and category 2 as its response: **403 observed pairs** match reversed routing, service, method and identifier. Another 103 responses lack a captured request. Categories 1 and 4 also occur, but their full semantics are not established. These are not the phone UCD2 message codes: service 11/method 1, for example, does not mean phone command 11 or phone command 1.

The clearest mapped methods are a property service, **service `0x000b`**:

- **Method 1, category 0:** a LE32 byte length followed by a namespace string. Observed namespaces are `gui` and `bla`.
- **Method 1, category 2:** LE32 result value, LE32 namespace length plus namespace bytes, then LE32 JSON length plus JSON bytes. The inspected replies have result 0, with the lengths accounting for the complete payload. This is evidence of a successful-looking reply structure, not a general result-code specification.
- **Method 2, category 0:** namespace length/string, then JSON length/string containing an array of replacement operations. The two observed replies use category 2 and a four-byte zero result.

The reconstructed traffic contains **117 `gui` queries, 133 `gui` state replies, one `bla` query/reply, and two GUI replacement requests/replies**. Unequal query/reply counts reflect the incomplete capture, not an inferred polling protocol error. GUI query/reply traffic is approximately once per second. Other recurring traffic includes service 1/method 13 request/reply pairs at about 0.5-second intervals and several category-4 reports near one-second intervals; their meanings remain unnamed.

Two captured screen-to-camera replacements are directly readable:

| UTC | JSON path | New value |
| --- | --- | --- |
| 13:05:28.982812 | `/gui/focus_set_page_id` | `kLiveviewSplitScreenPage` |
| 13:06:21.856044 | `/gui/focus_set_page_id` | `kAAAPage` |

These are observed operations by the paired screen. This investigation did not send them, and their capture does not establish that issuing them alone starts a screen video session.

## Screen state and implications for the requested feed

The `bla` reply at **13:05:28.873805 UTC** contains the literal states `PowerOn`, `ScreenBright` and `ScreenDirectionHorizontal`. Its feature/configuration object includes `remote_screen_auto_off_enabled: true`, `preview_initial_angle: 180`, and a preview rotation value `RotateAngle90`. These names and values are observed JSON; the feature flag is **not** a verified active screen-off setting or a command for preventing the phone connection from closing the preview.

All 133 GUI state replies contain `pipeline_build_state: 0` and a `pipeline_status_snapshot` whose `bt`, `preview` and `split_screen_wifi` values are all zero. An updating screen picture was separately confirmed by the user, so **zero cannot be interpreted as “preview off” from this capture**. The values may describe another lifecycle state, a cached/default representation or a different subsystem; their enum semantics remain unknown. Preview ROI is consistently `{height:1000, width:1000, start_x:0, start_y:0}`; this does not establish pixel dimensions.

No recovered control message contains a named Color Recovery/LUT selector. No Annex-B SPS/PPS signature was found in the complete control messages, and the recovered JSON contains no named codec-configuration or extradata field. Binary methods remain largely unmapped, and missing KCP segments limit negative findings. This control capture therefore supplies **no verified decoder initialization parameters, pre-LUT selector or independent color-pipeline setting**.

Readable routing, RPC fields and JSON demonstrate that the recovered control messages are not protected by blanket application-payload encryption once WPA2 is decrypted. This does not establish the cryptographic properties of every binary method, or remove the unknown inner integrity field. Private device-identifying JSON properties were excluded from this note.

## Comparison with public WT/protobuf candidates

The community protobuf contains `WtClientConnectionReq` (client type/device ID), a connection response with refusal fields, `WtDecodedFrameIdFeedback` (frame ID, packet sequence, timestamp), and `WtPreviewStateAck` (start/stop, SSRC, error). It also contains video timing and RTP-timestamp structures. These are useful source definitions, but **none has been positively matched to the recovered control methods**. [Pinned schema][proto]

The captured reconnect envelope is fixed-width binary; the mapped property RPCs use length-prefixed strings and JSON. They are not demonstrated instances of those WT protobuf messages. Likewise, the captured control datagrams are KCP, not bare RTP. A media protocol nested inside another channel requires its own evidence.

The next implementation dependency is a complete initial-session trace: identify connection/session establishment, decode the unknown inner integrity field, obtain codec setup, and map the operations actually required for receiving video. Only decoded image comparisons with Color Recovery's state recorded can answer whether the screen path supplies the requested unconverted I-Log feed.

Sanitized offline reconstruction and JSON summaries remain in the ignored `.local/luna-screen-udp-control/` directory. The capture, decrypted payload export, keys and device identifiers remain private.

[kcp]: https://github.com/skywind3000/kcp/blob/b1a7a2101dcbb96017681a500d6b82bbe5a88766/ikcp.c#L789
[proto]: https://github.com/iliakonnov/insta360-nas/blob/b78dddb9cd9bc2cf632871646c6f5af238e582d4/insta360-server/insta360_messages.proto#L7951
