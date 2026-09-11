# Luna Color Recovery: controlled screen-link capture

Measured **2026-09-11** from the finalized private capture `20260911T151140Z-luna-recovery-toggle-retry/recovery.pcapng` and its good-FCS decrypted `udp.tsv`. This analysis was entirely offline and sent no commands. Offline key derivation independently validated the captured EAPOL message 3 and 4 MICs.

**Color Recovery is now mapped in the screen RPC configuration: `iq_ilog_lut.enable` and `iq_ilog_lut.lut_type` change together, with matching camera replies and readback. Independently decoded screen video changes with that state. This does not yet provide an independent pre-LUT feed while camera Recovery remains On.**

## Operator report versus measured timing

The requested sequence was an attached camera in 10-bit I-Log with Recovery On, power-off for ten seconds, boot, detachment, then On → Off → On → Off → On with twenty seconds of live preview per state. The user's reply **“Done”** was recorded at **15:13:46.539028 UTC**. The requested final state was detached with Recovery On; completion of that recipe is operator-confirmed, but there is no separate physical timestamp or confirmation for each setting and hold. [Private operator report](../../captures/20260911T151140Z-luna-recovery-toggle-retry/operator-report.json)

The decrypted control interval is only **15:12:51.161519–15:13:37.996015 UTC**. Its readbacks contain **15 rapid alternating state transitions**, from an initially observed true to a last observed false. Consequently, the recorded traffic does not establish twenty-second holds or identify exactly four physical user taps. The reported final On state is not confirmed by the last captured readback. The useful evidence is the actual repeated request/readback/video correlation below.

## Reconstruction and completeness

The analyzer discovered control KCP conversation **`0x00200012`** dynamically on camera UDP `6000` ↔ screen UDP `6021`. Both directions begin at sequence zero. The separately analyzed video conversation is `0x00200013`; neither ID is assumed to be a permanent product constant.

Reconstruction uses the tracked `CaptureAssembler`, separately for each direction and conversation. It handles retries, sequence ordering and descending fragment chains, then accepts only messages whose exact length and **both CRC16 checksums** validate. Coalesced KCP segments are parsed separately; missing fragments are not fabricated. [Offline wire decoder](../../tools/luna_screen_wire.py), [control framing research](luna-screen-udp-control.md)

| Control measurement | Screen → camera | Camera → screen |
| --- | ---: | ---: |
| Complete CRC-valid RPC messages | 1,516 | 1,482 |
| Unique observed PUSH sequences | 1,529 | 1,623 |
| Observed sequence range | 0–1718 | 0–1711 |
| Missing sequence numbers within that range | 190 | 89 |
| Incomplete fragment groups | 3 | 3 |
| Rejected envelope groups | 0 | 5 |
| Conflicting repeated sequences | 0 | 0 |
| Duplicate PUSH segments | 64 | 403 |

There are 5,988 captured control UDP datagrams, including 954 marked as radio retries, and ten CRC-valid direct bootstrap datagrams. Missing sequence numbers describe gaps in the monitor capture, not necessarily loss at the receiving screen. Five camera-side envelope rejections are excluded from all semantic findings; the aggregate does not attribute each rejection to a particular corruption mechanism.

The sanitized reconstruction, exact frame/sequence/time markers and selected JSON values are in [private recovery evidence](../../.local/luna-recovery-control-analysis/recovery-evidence.json). The offline analyzer and evidence generator reside alongside it.

## Verified configuration mapping

The relevant routing is screen **`0x0814 → 0x0405`** camera, with reversed routing in replies. All RPC version values here are 1. The methods below belong to the screen RPC namespace, **not the phone UCD2/protobuf command namespace**.

| Operation | Service / method / category | Observed body layout |
| --- | --- | --- |
| Read complete configuration | 1 / 1 / 0 | Empty request body |
| Configuration reply | 1 / 1 / 2 | LE32 result; LE32 JSON byte length; JSON; eight opaque trailing bytes |
| Replace complete configuration | 1 / 2 / 0 | Eight opaque bytes; LE32 JSON byte length; complete JSON |
| Replacement reply | 1 / 2 / 2 | Four-byte result; matched successful examples are `00 00 00 00` |

The opaque eight-byte value in the observed replacement requests matches the trailing value in the readbacks and stays constant across this capture. Its meaning is unverified; it must not be discarded or promoted to a universal constant. All readback result values are zero. Replies are matched using reversed routing plus service, method and identifier, independently of KCP transport ACKs.

The two complete replacement-body variants have **50 top-level configuration properties and 87 scalar leaves**. Exactly two leaves differ; **85 remain identical**:

| Selected field | Recovery Off state | Recovery On state |
| --- | --- | --- |
| `iq_ilog_lut.enable` | `false` | `true` |
| `iq_ilog_lut.lut_type` | `kStandard` | `kILogStandard` |
| `iq_ilog_lut.lut_level` | 100 | 100 |
| `iq_color_mode.color_mode` | `kIlog` | `kIlog` |
| `iq_lut_config.lut_type` | `kStandard` | `kStandard` |
| `iq_lut_config.lut_level` | 3 | 3 |

The unchanged `iq_lut_config` is a distinct configuration object; it must not be conflated with `iq_ilog_lut`. A small sanitized [JSON shape fragment](../../.local/luna-recovery-control-analysis/lut-shape-fragment.json) preserves these fields for decoder work. It is deliberately **not a complete or proven writable RPC request**.

## Four fully observed alternations

The first available full readback, frame **25205**, camera SN **355–356**, at **15:13:04.854946 UTC**, has Recovery true / `kILogStandard`. Its request was not captured. The following four replacements, replies and before/after readbacks are all complete and CRC-valid.

Times in these tables are UTC; the date is 2026-09-11. Request/reply identifiers are decimal.

| Requested state | Request frame / screen SN | Request time | ID | Matched reply frame / camera SN | Reply time / result |
| --- | --- | --- | ---: | --- | --- |
| Off | 25240 / 472–473 | 15:13:04.883257 | 8285 | 25508 / 406 | 15:13:05.797951 / 0 |
| On | 25681 / 533–534 | 15:13:06.189284 | 8305 | 25889 / 479 | 15:13:07.034391 / 0 |
| Off | 26141 / 594–595 | 15:13:07.783331 | 8322 | 26359 / 548 | 15:13:08.648763 / 0 |
| On | 26579 / 660–661 | 15:13:09.374916 | 8340 | 26836 / 626 | 15:13:10.301378 / 0 |

| Replacement ID | Previous readback frame / state | Subsequent readback frame / camera SN | Readback time / state |
| ---: | --- | --- | --- |
| 8285 | 25205 / On | 25282 / 363–364 | 15:13:04.942561 / Off |
| 8305 | 25650 / Off | 25703 / 439–440 | 15:13:06.227456 / On |
| 8322 | 26101 / On | 26169 / 510–511 | 15:13:07.838005 / Off |
| 8340 | 26565 / Off | 26608 / 582–583 | 15:13:09.448616 / On |

The readback often changes before the replacement reply arrives. A stored configuration change is therefore not a precise timestamp for the encoder's first changed frame. For image comparison, use the independently decoded picture and its capture time rather than assuming immediate visual application at the request or readback.

Across the whole recovered interval there are **ten complete bulk replacement requests, nine captured matching replies, and thirty configuration readbacks**. Twenty-seven readbacks have a captured matching query. Collapsing consecutive identical readback states yields the initial On plus fifteen alternations, ending Off at frame **31627**, camera SN **1431–1432**, **15:13:27.687893 UTC**. Missing request fragments account for gaps in the complete-request evidence; no missing request is reconstructed from a later state value.

## Separating settings from navigation

The only two service 11/method 2 GUI replacements are:

- Frame **19673**, **15:12:51.724199**: `/gui/focus_set_page_id` → `kLiveviewSplitScreenPage`.
- Frame **23193**, **15:13:00.297109**: the same path → `kAAAPage`.

They precede the recovery alternations and do not track each On/Off change. They are navigation, not the verified Recovery state operation. The recurring service 1/method 5 writes observed here name `record_time_sec: 0` and `starlapse_type: kStarlapseNormal`; their payloads do not alternate with Recovery either.

The phone schema's photography option 73 remains separate evidence. This capture does not establish that phone command 9/option 73 controls the mapped screen RPC property, nor that the namespaces share numeric identifiers. [Phone option 73 source context](luna-recovery-command-candidates.md)

## Independent encoded-picture correlation

The separate media analysis recovered 756 complete H.264 access units. Fourteen include SPS/PPS/IDR and independently decode without errors. Each reports 556×314, H.264 High profile/level 2.1, 8-bit 4:2:0, with limited-range BT.709 metadata. Those tags do not themselves establish an I-Log transfer curve.

Two independently decoded pictures bracket the first Off/On pair:

| Media frame | UTC time | Correlated control state | Observed appearance |
| ---: | --- | --- | --- |
| 25534 | 15:13:05.843 | Off, following replacement 8285 and its reply | Flatter picture |
| 25911 | 15:13:07.061 | On, following replacement 8305 and its reply | Restored contrast/color |

The remaining independently decoded IDRs repeatedly show the same flat/restored alternation around later state changes. All fourteen are separately joined to their preceding configuration readback in the [control/video correlation](../../.local/luna-recovery-media-analysis/readback-video-correlation.json). The scene is largely stable but has camera nudges; this is a qualitative pipeline comparison, not a fitted LUT or a calibrated transfer-function measurement. [Private comparison image](../../.local/luna-recovery-media-analysis/recovery-off-on.png), [independent IDR decode report](../../.local/luna-recovery-media-analysis/idr-decode-report.json)

The difference is present in the incoming encoded screen video decoded outside the screen UI. Thus Recovery's effect on this feed occurs upstream of that independent decoder; it is not solely a LUT applied by the detachable screen after reception. **A separate flat feed while camera Recovery stays On remains unproven.**

## Additional startup/session evidence

This take fills a prior bootstrap gap. At frame **19453**, **15:12:51.178760**, screen control SN **0**, route **`0x0bfb → 0x07fc`**, service **2**, method **1**, category **0**, identifier **78080**, the request body is `02 00 00 00` (LE32 value 2). Its matched reply is frame **19466**, camera SN **3**, **15:12:51.235489**, category 2, body `00 00 00 00`.

Five further requests with the same routing/service/method/body appear during configuration-related pipeline changes. One receives nonzero body `d1 8a ff ff` at frame **27996**, followed by a later successful request/reply at frames **28020 / 28095**. The nonzero result is retained as observed bytes; its vendor-defined meaning is unknown. Capturing an initial request and response improves session understanding but does not yet establish a sufficient standalone screen-client connection recipe.

The direct kind-2 bootstrap contains five camera requests, frames **19420–19424**, followed by five screen replies, frames **19435, 19444, 19446, 19448, 19450**. Each payload is 13 bytes: one byte followed by three little-endian 32-bit values. The leading byte is camera 0 / screen 1; the first LE32 advances **5958–5962** and is echoed by the screen; the second is the observed control conversation `0x00200012`; the final value is camera **10** / screen **8**. The first word is therefore transaction-like, rather than the fixed value 2007 seen in a previous take. Its precise semantics and the final word's meaning remain unmapped.

The parent BLE audit found advertising traffic and no ATT hierarchy. It also found sniffer packet-time and runner wall-time disagreement, so BLE packet times must not be aligned with these Wi-Fi transitions without clock calibration. Advertising-only capture does not establish that BLE is never involved.

## Implementation boundary

The captured bulk JSON also contains exposure, white balance, focus, crop/ROI, stabilization, preview, photo and recording settings. Its property keys do not expose Wi-Fi credentials or device serials, and device identifiers are excluded from this note; the opaque eight-byte value remains uninterpreted. **Replaying the whole snapshot could overwrite unrelated current settings.**

No minimal single-field Recovery PATCH request has been demonstrated. The known GUI patch service is not evidence for an IQ-setting patch path. A future writer needs a validated current-state read/modify/write contract, preserved unrelated settings and opaque values, matching replies/readback, and an independently working screen session. The present result establishes the captured operation and its effect; it does not demonstrate equivalence to phone option 73 or establish an independent pre-LUT stream.

## Cleanup

Both owned recorders were stopped after the user's completion report. System Settings confirmed **Mouse House Connected**, and en0 returned to `192.168.1.87`. No camera-setting command was sent by this experiment and no app was launched on the physical iPhone. Captures, keys, full configuration snapshots and decoded pictures remain ignored local artifacts. [Private cleanup verification](../../captures/20260911T151140Z-luna-recovery-toggle-retry/cleanup-verification.json)
