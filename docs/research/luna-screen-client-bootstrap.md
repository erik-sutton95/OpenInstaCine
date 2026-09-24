# Luna screen client bootstrap: evidence and remaining endpoint gap

Measured **2026-09-11**, from three finalized private wireless captures. This investigation used the research workflow and offline primary packet evidence only. It did not join a network, operate a device, transmit camera commands or modify the captured files.


> **Status, 2026-09-17:** the client bootstrap is solved. The camera resumes KCP
> sequences and a fresh endpoint is discarded as stale; priming fixes it and
> writes now land. Sections below are chronological and several record failures
> that are now explained. Read **Resolved: the camera resumes KCP sequences** at
> the end first, then [the implementation guide](../implementation/luna-color-recovery.md).

**The captured UDP control startup is initiated by the camera, not by a screen “hello”. The camera already targets the screen's IP before the first captured control datagram.** We can describe its replies and the established-session configuration GET precisely. These captures do **not** establish how an arbitrary Mac endpoint becomes the selected screen client, which bootstrap fields it must choose, or a minimal control-only session. The known phone TCP live client does not by itself supply this separate screen-RPC session.

## Sources and reconstruction

The primary sources are the unchanged captures and FCS-good decrypted eight-column UDP exports under these private directories:

| Label used below | Private capture directory and file | Control conversation | Complete CRC-valid messages, camera / screen |
| --- | --- | --- | ---: |
| Reconnect | `captures/20260911T130348Z-luna-screen-confirmed-live/reconnect.pcapng` | `0x001e0007` | 2,857 / 3,142 |
| Startup | `captures/20260911T140806Z-luna-screen-startup-confirmed/startup.pcapng` | `0x0020000a` | 1,945 / 2,280 |
| Recovery | `captures/20260911T151140Z-luna-recovery-toggle-retry/recovery.pcapng` | `0x00200012` | 1,482 / 1,516 |

The private audit script `.local/luna-recovery-live-research/audit.py` dynamically discovers conversations and uses the tracked [`CaptureAssembler`](../../tools/luna_screen_wire.py). It splits coalesced KCP segments, separates directions, removes repeated identical PUSH segments and requires complete application lengths and both CRC16 checks. The three takes respectively exclude camera/screen incomplete groups **5/0, 1/0, 3/3**, and invalid-envelope groups **0/0, 1/0, 5/0**; none has conflicting retransmitted payloads. Incomplete/invalid captured groups are not evidence of invalid messages at the receiver. Private per-take JSON reports preserve frame, time, route, service, method, category, identifier and sequence references without publishing full settings or device identities.

A separate private `pre_udp.py` reads the original captures with their saved private decryption profiles to inspect ARP, ICMP and application ordering. The profile contents and keys were not printed. Captured packets remain the source of the claims below; see the existing [control framing note](luna-screen-udp-control.md), [startup validation](luna-screen-startup-capture-2026-09-11.md) and [recovery mapping](luna-recovery-toggle-capture-2026-09-11.md) for independent surrounding evidence.

## What precedes the first UDP message

Observed addresses are camera `192.168.42.1` and screen `192.168.42.253`, with control UDP camera port **6000** and screen port **6021**. These are measured endpoints, not a claim that any device can safely claim the screen address.

| Take | Pre-UDP primary packet evidence, UTC | First control UDP | First screen control UDP |
| --- | --- | --- | --- |
| Reconnect | Frame **9406**, **13:05:26.522720**: ARP request, camera asks for screen `.253`. Camera ICMP echo request frame **9408**, **26.526086**; screen echo reply **9412**, **26.527702**. | Camera kind 2, frame **9418**, **13:05:26.866427** | Kind-2 reply, frame **9423**, **13:05:26.868126** |
| Startup | Frame **334**, **14:11:09.562660**: screen ARP reply to camera. | Camera kind 2, frame **336**, **14:11:09.563776** | Kind-2 reply, frame **340**, **14:11:09.565111** |
| Recovery | Frame **19418**, **15:12:51.159687**: screen ARP reply to camera. | Camera kind 2, frame **19420**, **15:12:51.161519** | Kind-2 reply, frame **19435**, **15:12:51.165165** |

In Recovery, camera ICMP echo request **19437** and screen echo reply **19439** follow the first bootstrap, at **15:12:51.165193 / .165254**. Thus a completed ICMP exchange is not uniformly a captured prerequisite for the camera to send kind 2. Recovery frame **19417**, immediately before the ARP reply, is a still-encrypted broadcast packet; its payload cannot be called an ARP request from this decryption alone.

There is **no captured screen-to-camera UDP registration before the camera's first kind-2 packet** in any of the three decrypted exports. The explicit Reconnect ARP request demonstrates that the camera knows which IP to seek before UDP. ARP resolves an already selected IP to a link-layer peer; it does not explain how the camera selected that IP or UDP port. The camera could know it from earlier pairing, attached-screen transport, configuration or another unobserved exchange; these alternatives are not resolved here.

These are absence findings within incomplete monitor captures. The later profiles use a direct pairwise temporal key, so some protected group traffic remains unreadable. Earlier attached-screen provisioning is not observed. No inspected pre-UDP DHCP/TCP/UDP registration supplies an arbitrary Mac endpoint. **Binding local port 6021 is therefore insufficient evidence of a working new-client bootstrap; proactively sending a guessed kind-2 request would be an experiment, not reproduction of the observed initiating sequence.**

## Direct kind-2 exchange

The direct UDP bootstrap is a **25-byte application envelope**, without a preceding KCP header. It uses the same validated 12-byte envelope as ordinary RPC: kind byte, two LE16 routes, LE24 payload length, LE16 header CRC and LE16 payload CRC. Both CRCs use the measured effective seed `0xef4a`; the header CRC covers the eight non-CRC header bytes followed by four zero bytes. The [tracked codec](../../tools/luna_screen_wire.py) verifies the exact lengths and both CRCs.

For kind 2 the 13-byte payload structurally parses as `byte + LE32 + LE32 + LE32`:

| Take / frames | Camera payload values | Screen reply values |
| --- | --- | --- |
| Reconnect **9418 → 9423** | `0, 2007, 0x001e0007, 4` | `1, 2007, 0x001e0007, 3` |
| Startup **336 → 340** | `0, 2398, 0x0020000a, 6` | `1, 2398, 0x0020000a, 4` |
| Recovery **19420 → 19435** | `0, 5958, 0x00200012, 10` | `1, 5958, 0x00200012, 8` |

The camera outer route is **`0x0400 → 0x0000`**, and the screen reply route is **`0x0800 → 0x0000`**. The embedded conversation exactly matches following KCP traffic. The middle value behaves as an echoed transaction value, but its allocation and broader meaning remain unknown. The leading byte distinguishes the observed request/reply directions; its full enum is unknown.

Recovery additionally contains camera values **5959–5962**, frames **19421–19424**, followed by matching screen echoes **19444, 19446, 19448, 19450**. Those changing values are distinct application messages, not identical radio retransmissions. Reconnect frame **9419** instead repeats the same complete bytes as 9418.

**The final LE32 is not mapped.** Its observed camera/screen pairs are `4/3`, `6/4`, `10/8`: neither one fixed reply value nor a universal “subtract two” rule is supported. The dynamic conversation, transaction and terminal values must not be copied from one recorded take as product constants. Captured exchange evidence alone does not establish whether the camera validates the final field, or how another client should derive it.

## First KCP operations and the established-session GET

KCP itself has the standard 24-byte little-endian segment header; each direction has its own sequence and acknowledgement state. Multiple KCP segments share datagrams. KCP ACK is transport acknowledgement, not camera command success. [Framing and primary KCP source reference](luna-screen-udp-control.md#kcp-transport)

- **Reconnect** begins with screen sequence **6173**, frame **9427**, already replying to an earlier uncaptured camera request. This is a resumed logical session. Its next screen message is service **2/method 1/category 0**, route `0x0bfb → 0x07fc`, body `LE32(2)`, frame **9428**, sequence **6174**, identifier **23018**. Starting a fresh KCP endpoint at zero cannot reproduce this resumed state.
- **Startup** begins at sequence **0** in both directions: camera service **4/method 4/category 0**, frame **348**, then screen response **349**. Screen sequences 1–3 are missing. Camera frame **360** acknowledges service 2/method 1 with a four-byte zero body, but that take does not reveal its request.
- **Recovery** begins at screen sequence **0**, frame **19453**, **15:12:51.178760**, with service **2/method 1/category 0**, route `0x0bfb → 0x07fc`, body `LE32(2)`, identifier **78080**. Camera response **19466**, **15:12:51.235489**, sequence **3**, reverses the routes, uses category 2 and returns `LE32(0)`. All these takes include active screen video, so the necessity of this start-like operation for configuration-only access is untested.

Once a session exists, the exact full configuration read is supported by **27 complete matched pairs** in Recovery:

```text
Envelope: kind 0, source 0x0814, destination 0x0405
RPC:      version 1, service 1, method 1, category 0, request identifier
Body:     empty

Reply:    reversed routes, same service/method/identifier, category 2
Body:     LE32(result=0) + LE32(JSON byte count) + JSON + opaque 8 bytes
```

Concrete pair: request **25252**, **15:13:04.908738**, screen sequence **474**, identifier **8286**; response **25282**, **15:13:04.942561**, camera sequences **363–364**. Its JSON reports the recovery selector false. Reassembly is necessary because configuration responses span multiple KCP segments. The eight trailing bytes are preserved opaque data, not padding that can be discarded. [Exact recovery schema and SET/readback correlations](luna-recovery-toggle-capture-2026-09-11.md)

A conservative **conditional** control flow is therefore: establish the yet-unmapped selected-client session, validate its received bootstrap, maintain the negotiated KCP conversation, issue the empty GET above with a tracked identifier, and accept only a complete CRC-valid matched reply with valid declared JSON length and the observed result value. This is a decoder/transaction outline, **not a validated minimum live-client recipe**. No capture experiment removes the screen's other operations one by one, and no Mac configuration GET has been demonstrated by this offline investigation.

## Reciprocal camera requests

Dispatch must include **route, service, method and category**, and replies must reverse the route and preserve the identifier. Categories 1 and 4 are also present and must not automatically receive category-2 success acknowledgements.

The recurring request found in **all three takes** is:

```text
Camera: 0x07fc → 0x0bfb; service 4, method 4, category 0; empty body
Screen: 0x0bfb → 0x07fc; same service/method/identifier; category 2
Reply body: LE32(0) + LE64(changing counter)                 # 12 bytes
```

There are **27 complete requests / 24 matched replies**: Reconnect 14/14, Startup 9/7, Recovery 4/3. The median request interval is approximately ten seconds. First matched examples are Reconnect **9943 → 9944**, Startup **348 → 349**, Recovery **22881 → 22882**. Missing replies in a capture are not proof that the device omitted them.

The changing counter advances at approximately **1,000,000,000 units per elapsed second**, calculated from every adjacent pair of captured replies. Per-take median rates are **1,000,002,471**, **1,000,033,229**, and **1,000,033,541** units/s. Its magnitude is incompatible with current Unix nanoseconds and is consistent with a monotonic nanosecond counter, but its origin, clock contract and necessity remain unmapped. The captured reply is **not** just a four-byte result. Hardcoding a captured counter or asserting a synchronization algorithm is unsupported.

Other matched camera requests demonstrate different response shapes:

| Take / request → response frames | Camera route | Service / method | Request body | Captured screen reply body |
| --- | --- | --- | --- | --- |
| Reconnect **9430 → 9431** | `0x07fd → 0x17fe` | 2 / 16 | `LE32(0)` | `LE32(0)` |
| Reconnect **9435 → 9440** | `0x07fd → 0x17fe` | 2 / 10 | Two zero bytes | `LE32(0)` |
| Reconnect **9441 → 9443** | `0x07fd → 0x17fe` | 2 / 6 | `LE32(0)` | `LE32(0)` |
| Recovery **19596 → 19597** | `0x0405 → 0x0bfb` | 1 / 5 | One byte `0x64` | `LE32(0)` |
| Recovery **34977 → 34978** | `0x0405 → 0x17fe` | 5 / 3 | `LE32(1)` | `LE32(0)` |
| Recovery **35026 → 35075** | `0x07fd → 0x0bfd` | 3 / 1 | Empty | **48 bytes**, semantics unmapped |

These are observed pairs, not named camera functions or a blanket success-reply policy. Several additional service 2/3 requests near the end of Recovery have no captured matched reply. Their meaning and required behavior are unknown; fabricating success for them would exceed this evidence.

## Periodic screen traffic is not a proven mandatory heartbeat

Three recurring screen requests merit distinguishing from recovery writes:

| Screen route | Service / method | Observed request / response | Cadence and evidence |
| --- | --- | --- | --- |
| `0x0bfb → 0x07fc` | 1 / 2 | Request `LE32(1)`; reply `LE32(0) + LE32(3)` or `LE32(1)` as the second word | About **2 s**; **102 requests / 99 matched replies** across takes. Example Recovery **20225 → 20226**. Function unnamed. |
| `0x0bfb → 0x0407` | 1 / 13 | Request six opaque bytes; reply zero result plus a changing signed 32-bit value | About **0.5 s**; **456 requests / 446 matched replies**. Example Recovery **19764 → 19779**. A telemetry query is plausible, not proved; no identifying request bytes are published. |
| `0x0814 → 0x0405` | 11 / 1 | Length-prefixed namespace query and JSON reply | Approximately 1 s in the earlier takes; faster during recovery settings interaction. Mapped `gui` state query, not recovery itself. |

**Service 1/method 2 on route `0x0bfb → 0x07fc` is different from the large configuration SET on `0x0814 → 0x0405`.** Matching only numeric service and method would confuse a periodic four-byte request with a roughly 2.6 KB configuration write. A further frequent service 4/method 1/category 1 stream carries 550/678-byte binary bodies; this investigation does not assign it a heartbeat or omit it as irrelevant without validation.

## Implication for the requested Mac recovery button

The 720p phone-protocol feed and camera recovery control use two distinct demonstrated transports. The recovery property and full GET/SET framing are now known; the missing step is a verified live screen-RPC client session from the Mac, including endpoint selection and coexistence with the phone preview. This note does not establish that screen control can coexist with that preview or that camera/screen/client IP reassignment is an appropriate solution.

A future controller should obtain fresh config/readback before presenting an authoritative On/Off state. The observed bulk SET includes many unrelated current camera properties and an opaque prefix. There is **no proven minimal PATCH form**, and replaying a captured whole-settings snapshot could replace current exposure, recording or other settings. See the [recovery capture note](luna-recovery-toggle-capture-2026-09-11.md) for the two changed LUT leaves, 85 unchanged scalar leaves, zero-result replies and image correlations. No equivalence to the phone's candidate option 73 is established by these captures.

The next information required is narrow: how the camera selects a replacement endpoint, what the kind-2 terminal value means for that client, and which established-session exchanges are necessary when video remains on the phone protocol. No active experiment was performed as part of this note.

## Follow-up: Mac GET is KCP-acknowledged but has no RPC reply

The parent operator subsequently ran an active Mac probe while the phone-protocol feed remained live. This investigation only read its finalized `captures/20260911T180847845264Z-luna-recovery-live/screen-control.jsonl`; it performed no additional active test. The file contains 13 datagrams and is distinct from the successful physical-screen captures above. The private decoded comparison is `.local/luna-recovery-live-research/probe-180848.json`.

| Probe time UTC | Observed application/transport event |
| --- | --- |
| **18:08:48.238883** | Mac sends kind 2, leading flag **0**, with its own proposed transaction/conversation and final word **8**. |
| **18:08:48.244794** | Camera sends kind 2, leading flag **0**, transaction **21901**, conversation **`0x00200015`**, final word **12**. |
| **18:08:48.244837** | Mac replies flag **1**, echoing camera transaction/conversation, final word **8**. |
| **18:08:48.611743** | Mac sends the empty configuration GET, source `0x0814`, destination `0x0405`, version 1, service 1, method 1, category 0, identifier **9549953**. KCP sequence **0**, fragment **0**, window **256**. |
| **18:08:48.641074** | Camera KCP ACK: sequence **0**, UNA **1**, same conversation and echoed transport timestamp. **No application payload.** |
| **18:08:49.424163–52.929371** | Camera sends four more kind-2 requests, transactions **21902–21905**, same conversation and final word 12. Mac repeats the flag-1/word-8 replies. No camera KCP PUSH or RPC reply is present in the completed log. |

The initial Mac solicitation precedes the first camera datagram by **5.911 ms**. Consequently, this particular log does not distinguish an unsolicited camera invitation from a response to, or collision with, the Mac's competing proposal. The camera uses a different transaction and conversation from that proposed by the Mac; it does not return a flag-1 acceptance of that proposal.

The five camera requests are spaced approximately **1.179, 1.502, 1.003 and 1.000 seconds** apart. This differs materially from successful Recovery: its five distinct control requests arrived within **1.709 ms**, all before the first screen reply, and then control bootstrap stopped. The common count of five does not establish the same retry behavior.

The Mac GET's exact 22-byte application message passes both envelope CRCs and matches the successful captured GET's routes, ten-byte RPC layout and empty body. No extra opaque field or additional UDP prefix occurs in that captured GET. The Mac's pending-response key correctly expects the reversed route and the same service/method/identifier. Its KCP ACK demonstrates receipt at the transport layer, not a working RPC dispatcher or successful bootstrap.

### Cross-channel evidence about the final word

Inspecting both control and media direct envelopes adds useful negative evidence:

| Take / channel | Camera → screen final words | Conversation / local frame references |
| --- | --- | --- |
| Reconnect, control | **4 → 3** | `0x001e0007`, **9418 → 9423** |
| Reconnect, media | **4 → 3** | `0x001e0008`, **9422 → 9425** |
| Startup, control | **6 → 4** | `0x0020000a`, **336 → 340** |
| Startup, media | Camera **5**, reply not captured | `0x0020000b`, **339** |
| Recovery, earlier media conversation | **8 → 7** | `0x00200011`, **19429 → 19441** |
| Recovery, current control | **10 → 8** | `0x00200012`, **19420 → 19435** |
| Recovery, current media | **9 → 8** | `0x00200013`, **19430 → 19445** |

Six subsequent media negotiations retain conversation `0x00200013` and final words **9 → 8**, while transactions advance **6026–6031**; example **25475 → 25476**. Thus the final word does not simply echo the camera's word, count bootstrap requests, or equal the current KCP sequence. The fresh screen sequences start at zero despite final word 8. An endpoint/session generation is a plausible interpretation of the stable per-conversation values and changes across takes; it is **not a decoded field definition**. Existing evidence provides no justified replacement constant for the Mac's stale copied value 8, nor a universal arithmetic derivation from the camera's 12.

Across all three successful captures, **all 44 complete direct UDP application envelopes** on the inspected channels are kind 2. No additional complete direct registration envelope or opaque pre-KCP wrapper was recovered. Capture incompleteness and undecrypted traffic still limit that negative finding.

### Bounded implications for the live client

The reviewed client provisionally marks itself ready as soon as it receives camera kind 2. It should treat that as a discovered conversation until a valid application reply establishes working RPC. It also ignores camera category-0 requests; the known service 4/method 4 request needs the observed **12-byte** result-plus-counter response shape if supported. However, this probe contains no incoming camera KCP PUSH at all, so that missing responder does not yet explain this particular failure.

The smallest comparison supported by the successful captures is **listening without the speculative initial flag-0 solicitation**, keeping the remaining GET experiment unchanged, and distinguishing a genuine camera invitation from the competing-proposal case. This investigation did not run that comparison. A current successful physical-screen reply would supply the missing current peer final-word evidence; blindly cycling candidate values would not map the field. No alternate header tag, authorization payload, universal terminal constant or minimal control-only session is established here.

## Follow-up: Mac endpoint with the screen attached, 2026-09-17

A further active trial removed the competing-endpoint variable. The screen was **physically attached**, so it held no Wi-Fi association and `192.168.42.253` was free. The Mac took that address, joined on the phone AP after a BLE bootstrap, and ran the existing lab client in listen-first mode. Evidence is the private `captures/20260917T110918693964Z-luna-recovery-live/` log.

| Observation | Value |
| --- | ---: |
| Camera kind-2 invitations received | 40 |
| Mac kind-2 replies sent | 40 |
| Kind-18 (`0x12`) exchanges, each direction | 3 |
| Camera KCP PUSH datagrams received | **0** |
| Configuration GET replies | **0** |

The camera invited the Mac roughly once per second for the life of the session and never opened the application channel. The lab's reported `control_ready` reflects only a constructed KCP endpoint, and its displayed `recovery: false` is the exception fallback, not a reading; no `initial-screen-config.json` was written. Meanwhile the phone-protocol feed on the same Mac was healthy: 1,033 decoded 1280×720 frames, zero bad checksums, acknowledged live stop.

This removes IP contention with the real screen as the explanation. The camera's willingness to invite an arbitrary endpoint, combined with its refusal to dispatch RPC to it, keeps the unmapped step at selection or authorization rather than addressing. The **kind-18 envelope is new**; it does not appear in the physical-screen takes analyzed above, and its role is unknown. It is the most concrete next lead, alongside the still-unmapped kind-2 final word.

A separate hardware note: attaching the screen powers the camera's Wi-Fi down. The AP must be brought back with the BLE bootstrap before any Mac client can join.

## Resolved: the camera resumes KCP sequences, and a fresh client is discarded as stale

The long-standing description of the Mac failure, that the camera "KCP-acknowledges but never dispatches an RPC reply", was incomplete and led to several wrong hypotheses about addressing and authorization. The transport-level cause is now identified and fixed.

**The camera does not start a fresh KCP conversation. It resumes one.** Its first acknowledgement reports a next-expected sequence in the thousands, while a new client endpoint begins at zero:

```text
TX PUSH sn=0       una=0        len=22     # the config GET, fresh endpoint
RX ACK  sn=0       una=14361               # camera: I expect 14361 next
```

A segment below the receiver's window is acknowledged at the transport layer and then discarded without reaching the application. Every earlier Mac attempt therefore sent requests the camera was guaranteed to drop, which is why the symptom looked like silent refusal.

Priming the endpoint resolves it. Sending the captured session start first makes the camera reveal its expected sequence; jumping the send sequence to that value makes subsequent requests land:

```text
TX PUSH sn=14362   una=0        len=22     # config GET, primed
RX ACK  sn=14362   una=14363               # window advanced: accepted
TX PUSH sn=14363   una=0        len=22
RX ACK  sn=14363   una=14364               # accepted
TX PUSH sn=14364   una=0        len=22
RX ACK  sn=14364   una=14365               # accepted
```

The advancing `una` is the camera consuming each request. The expected sequence also **persists across client runs**, observed rising 14361 to 14362 between separate probe invocations, confirming durable per-conversation state on the camera rather than a value invented locally.

The client now also answers the **media-channel bootstrap**. A real screen answers the camera on the media port pair as well as the control pair, within eleven milliseconds, maintaining three conversations in total. A control-only client leaves the camera repeating its hello about once per second, against roughly every thirty seconds in a healthy session. Both responder and priming are implemented in the tracked screen client as `ScreenMedia`, `KCP.jump_recv` and `ScreenControl.prime`.

### What remains

With transport corrected, the camera **accepts and consumes** configuration reads and still sends no application reply. No camera KCP PUSH arrives on either channel. This narrows the open question considerably and removes the addressing and stale-sequence explanations. The remaining candidates, in the order the evidence favours:

1. **Client registration is incomplete.** The physical screen begins a continuous upstream immediately on association: a service 4 method 1 stream of 678-byte bodies whose payloads carry the ASCII magic `IDUA`, roughly sixteen per second, plus small service 5117 status messages on route `0x17fe → 0x07ff`. The camera's first application message follows 484 ms later. Our client sends none of this.
2. **Reply routing.** The camera may direct replies using state established at attachment rather than the requester's envelope.
3. **Request identity.** Message bodies elsewhere in the protocol carry a leading 64-bit endpoint id, camera 6 and screen 38, in which our client does not participate.

Reproduce with `.local/luna_allchannel_probe.py`, which binds both ports, answers both bootstraps, primes the sequence and issues a read-only GET. It sends no configuration write.
