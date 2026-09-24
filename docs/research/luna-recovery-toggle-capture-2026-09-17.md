# Luna Color Recovery: controlled screen capture with operator-marked taps

Measured **2026-09-17** from the finalized private capture `20260917T104801Z-luna-recovery-toggle-run5/recovery.pcapng` and its decrypted `udp.tsv`. Analysis was entirely offline and sent no commands. Offline key derivation independently validated the captured EAPOL message 3 and 4 MICs.


> **Status, 2026-09-17:** the command is mapped, and writing it from a Mac works.
> Sections are chronological, so earlier ones state problems later ones solve.
> For the current picture read **Solved: Color Recovery written from the Mac** at
> the end, and [the implementation guide](../implementation/luna-color-recovery.md).

**Three deliberate operator taps produced exactly three configuration writes, in the reported order, and the camera's own readback followed each one within 33–59 ms.** This supersedes the timing ambiguity of the [2026-09-11 take](luna-recovery-toggle-capture-2026-09-11.md), which recorded fifteen rapid readback transitions against four reported taps. It does not change the unresolved write path from a Mac endpoint.

## Operator marks versus captured writes

Each mark is the moment the operator reported the change in the session transcript, recorded to `20260917T104801Z-luna-recovery-toggle-run5/operator-log.txt`. The operator tapped and then typed, so every write correctly precedes its mark.

| Operator mark, UTC | Reported change | Captured write, UTC | Frame | `enable` | `lut_type` |
| --- | --- | --- | ---: | --- | --- |
| 10:54:38.3 | Off → On | 10:54:36.696276 | 86671 | `true` | `kILogStandard` |
| 10:55:11.5 | On → Off | 10:55:05.262259 | 94325 | `false` | `kStandard` |
| 10:55:45.1 | Off → On | 10:55:38.563556 | 104355 | `true` | `kILogStandard` |

The baseline before the first write was operator-reported Off. The captured write sequence is `true, false, true` with no additional writes in the interval, so no unreported transition intervenes.

## Camera readback follows each write

The readback is the camera answering a configuration query, source `0x0405`, so it reports the body's stored value rather than echoing the request.

| Readback, UTC | Frame | `enable` | Follows write | Lag |
| --- | ---: | --- | --- | ---: |
| 10:55:05.232480 | 94305 | `true` | prior On state holding | — |
| 10:55:05.321187 | 94345 | `false` | 10:55:05.262259 | 59 ms |
| 10:55:38.596752 | 104370 | `true` | 10:55:38.563556 | 33 ms |

The first readback transition captured for the opening On write fell outside the matched-pair window; its state is nonetheless confirmed by the 10:55:05.232480 readback showing `true` immediately before the Off write. Readback lag is not a claim about when the encoder's first changed picture is emitted.

## Verified configuration mapping

Routing is screen `0x0814 → 0x0405` camera, RPC service 1 / method 2, the full-configuration replace. Two leaves move together:

| Field | Recovery Off | Recovery On |
| --- | --- | --- |
| `iq_ilog_lut.enable` | `false` | `true` |
| `iq_ilog_lut.lut_type` | `kStandard` | `kILogStandard` |
| `iq_color_mode.color_mode` | `kIlog` | `kIlog` |
| `iq_lut_config.lut_type` | `kStandard` | `kStandard` |
| `iq_lut_config.lut_level` | 2 | 2 |

`iq_lut_config` is a distinct object and must not be conflated with `iq_ilog_lut`. Its `lut_level` reads 2 in this take against 3 on 2026-09-11, confirming the bulk replace carries unrelated current settings whose values are session-specific. **Replaying a whole captured snapshot could overwrite unrelated settings.**

## Reconstruction and completeness

| Control measurement | Value |
| --- | ---: |
| Decrypted UDP datagrams | 40,607 |
| Control datagrams, ports 6000 ↔ 6021 | 14,713 |
| Complete CRC-valid RPC messages | 7,277 |
| Direct bootstrap datagrams | 5 |
| Complete configuration writes | 3 |
| Configuration readbacks | 4 |

Reconstruction used the tracked `CaptureAssembler`, separately per direction and conversation, accepting only messages whose exact length and both CRC16 checksums validate. Decrypted endpoints are camera `192.168.42.1` and screen `192.168.42.253`, control on `6000 ↔ 6021` and media on `6002 ↔ 6023`. Capture interval 10:53:39.965553–10:56:26.101309 UTC. [Offline wire decoder](../../tools/luna_screen_wire.py), [extraction analyzer](../../.local/luna-analyze-recovery-take.py)

## Capture procedure and its hardware constraints

Obtaining a decryptable take required identifying which physical action yields a WPA2 four-way handshake. Three constraints were established by trial:

1. **The screen's power button also power-cycles the camera body.** There is no screen-only restart on Luna Ultra.
2. **The screen reconnects from a cached pairwise key**, emitting no EAPOL, after attach/detach and after leaving and re-entering radio range. Neither yields keys. A full four-way handshake was observed only on the screen's first association after a camera reboot, which clears the camera's cached-key table.
3. **The 2.4 GHz link channel is reassigned on each camera reboot.** Channels 9, 2, 3 and 3 were observed in one session. The older hardcoded channel-3 capture binary is unreliable; use the parameterized runner and verify by received traffic, because the CoreWLAN channel readback can be stale.

With the screen attached, only the 5 GHz phone AP is advertised; the 2.4 GHz screen link appears once the screen is detached. An associated but idle screen emits only QoS Null keepalives, so a low frame count indicates idleness rather than a wrong channel. The screen link uses the same SSID and PSK as the phone AP, which is why offline derivation from the owned credentials validates.

Working sequence: detach the screen and confirm picture, sweep 2.4 GHz for the channel, arm the capture there, reboot the camera, then detach again so the first association lands inside the capture.

## Implementation boundary

This take confirms the command and its effect on stored camera state. It does **not** change the unresolved items:

- No write from a Mac endpoint has succeeded. The camera KCP-acknowledges an identical CRC-valid write but does not dispatch an RPC reply. [Screen client bootstrap](luna-screen-client-bootstrap.md)
- Phone photography option 73 remains a no-op on v1.0.288 and is not shown equivalent to this screen RPC.
- No minimal single-field PATCH form is demonstrated; only the bulk replace is observed.
- This take did not decode media, so it adds no new evidence about where in the pipeline the conversion is applied. The 2026-09-11 take established that the effect is present in the encoded screen video, upstream of an independent decoder.

Captures, keys and decrypted exports remain ignored local artifacts.

## Phone-feed effect: A/B/A measurement, 2026-09-17

An open question until now was whether Color Recovery affects the **phone protocol feed** that OpenInstaCine monitors, or only the detachable screen's own stream. Every previous luma comparison in this repository used a control path that did not work, so those results carried no information.

This test used the only toggle proven to work, the physical screen, while the Mac recorded the phone feed over TCP 6666 with the existing client. The camera stayed in I-Log (photography option 35 = 2, confirmed by readback), pointed at a fixed scene, untouched between takes. Each take is 12 seconds; statistics come from an ffmpeg `signalstats` frame near the end of each recording.

| Take | Recovery | YAVG | SATAVG | YLOW | YHIGH | Recorded bytes |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 1 | On | 79.70 | 6.5535 | 26 | 149 | 5,928,524 |
| 2 | **Off** | 93.35 | 3.0230 | 49 | 137 | 4,606,035 |
| 3 | On | 80.84 | 6.5487 | 25 | 154 | 5,999,654 |

**Color Recovery changes the phone feed.** With it off the signal shows the expected flat-log signature: black level lifts from 26 to 49, highlights pull in from about 150 to 137, and average saturation halves. Returning to On restores saturation to within 0.1 percent of the first take and luma to within 1.4 percent, so the difference tracks the setting rather than drifting with time or scene. The reduced encoded size in the flat take is consistent with lower contrast, and is reported as an observation rather than a calibrated bitrate measurement.

These are relative comparisons of decoded statistics on one scene. They establish that the setting reaches this feed and in which direction; they are not a fitted transfer-function or LUT measurement, and they do not identify the exact pipeline stage.

### Consequence for monitoring

While Recovery is On, the phone feed carries the converted image. Monitoring tools that assume flat log input, such as false colour, waveform and preview LUTs, would therefore operate on already-converted values. Obtaining a flat feed requires setting Recovery off. That is now possible from a Mac; see **Solved: Color Recovery written from the Mac** below.

## Solved: Color Recovery written from the Mac, 2026-09-17

**The Mac can now set Color Recovery on the camera.** The obstacle was never authorization, addressing or device identity. It was a KCP transport defect in our client, described in the [bootstrap note](luna-screen-client-bootstrap.md): the camera resumes a long-lived conversation, and a fresh endpoint starting at sequence zero has every request acknowledged and then discarded below the receiver's window.

With the sequence primed, the camera accepts the write and acts on it. It still sends no application reply, so the earlier reading that the camera "declines to act" was wrong; it declines to *answer*, while acting on what it receives.

### Method

The client replays the byte-exact service 1 / method 2 body captured from this camera's own screen earlier the same day. The two recovered bodies carry 50 top-level properties and 73 scalar leaves and differ in exactly two, `iq_ilog_lut.enable` and `iq_ilog_lut.lut_type`, sharing one opaque eight-byte token. Replaying a captured snapshot rather than synthesising one avoids inventing values for the unrelated settings the bulk replace carries. The screen was attached throughout, so no physical screen control was used.

### Result

Measured on the phone feed, the same way as the physical-screen comparison above, scene fixed and camera untouched:

| Take | Commanded from | State | YAVG | SATAVG | YLOW | YHIGH |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| before | — | On (existing) | 81.84 | 7.025 | 26 | 147 |
| after | **Mac** | **Off** | 94.36 | 3.220 | 50 | 134 |
| after | **Mac** | **On** | 81.67 | 6.968 | 26 | 147 |

The Mac-commanded Off take reproduces the physical screen's Off signature (93.35 / 3.023 / 49 / 137) within noise, and returning to On restores luma to within 0.2 percent and saturation to within 0.8 percent of the baseline, with identical black and white points. Each write was fragmented into two KCP segments and the camera's next-expected sequence advanced by two per command, from 14365 to 14367 to 14369, confirming acceptance independently of the picture.

### Boundaries

The camera sends no reply or readback to this client, so state must be inferred from the feed or from a passive capture rather than read back over this path. The command remains a full-configuration replace: it carries exposure, white balance and other settings, so a synthesised body must be built from a current configuration, which this client cannot yet read. Replaying a stale snapshot will restore stale values for those unrelated settings. A minimal single-field PATCH form is still not demonstrated.

Implementation: `ScreenControl.prime`, `KCP.jump_send`, `KCP.jump_recv` and `ScreenMedia` in the tracked screen client; `.local/luna_recovery_set.py` sends the command, `.local/recovery-set-bodies.json` holds the captured bodies.
