# Luna Ultra Color Recovery: implementation guide

Everything needed to read, set and detect Color Recovery on a Luna Ultra from a Mac. Verified 2026-09-17 on firmware **v1.0.288**. Evidence and derivation live in [the capture note](../research/luna-recovery-toggle-capture-2026-09-17.md) and [the client bootstrap note](../research/luna-screen-client-bootstrap.md); those are chronological research logs, this is the current state.

## Why it matters

Color Recovery bakes the conversion into the **phone protocol feed**, not just the detachable screen's own stream. Measured on a fixed scene, the same camera and the same 12-second method:

| Recovery | YAVG | SATAVG | YLOW | YHIGH |
| --- | ---: | ---: | ---: | ---: |
| On | 79.7–81.8 | 6.5–7.0 | 25–26 | 147–154 |
| Off | 93.3–94.4 | 3.0–3.2 | 49–50 | 134–137 |

Monitoring tools that assume flat log input operate on already-converted values while it is on. Turning it off yields the flat signature: black level lifts, highlights pull in, saturation roughly halves.

## The command

The detachable screen writes the camera's configuration over UDP/KCP.

```text
Envelope kind 0, source 0x0814, destination 0x0405
RPC      version 1, service 1, method 2, category 0, identifier
Body     8 opaque bytes + LE32 JSON length + complete configuration JSON
```

Two JSON leaves change together and nothing else:

| Field | Off | On |
| --- | --- | --- |
| `iq_ilog_lut.enable` | `false` | `true` |
| `iq_ilog_lut.lut_type` | `kStandard` | `kILogStandard` |

`iq_color_mode.color_mode` stays `kIlog`. `iq_lut_config` is a **different object**; do not conflate them. This is a full-configuration replace carrying 50 top-level properties and 73 scalar leaves, including exposure, white balance, focus and recording settings.

## The thing that makes it work: prime the KCP sequence

This was the single blocker for months of attempts, and it is not authorization, addressing or device identity.

**The camera resumes a long-lived KCP conversation rather than starting a new one.** A fresh client endpoint begins at sequence 0, while the camera's receive window is already in the thousands. Segments below its window are acknowledged at the transport layer and then discarded before reaching its application, which looks exactly like silent refusal.

```text
TX PUSH sn=0       una=0       len=22     # fresh endpoint
RX ACK  sn=0       una=14361              # camera: I expect 14361 next
TX PUSH sn=14362   una=0       len=22     # primed
RX ACK  sn=14362   una=14363              # accepted: window advanced
```

Procedure, implemented as `ScreenControl.prime` in `tools/luna_screen_live.py`:

1. Send the captured session start: service 2, method 1, category 0, route `0x0bfb → 0x07fc`, body `LE32(2)`.
2. Read the camera's next-expected sequence from the `una` field of its ACK.
3. `KCP.jump_send` to that value. `KCP.jump_recv` does the mirror for inbound.
4. Issue real requests.

The value **persists across client runs and across camera reboots within a session**, observed advancing 14361 → 14369 over several invocations. Never hardcode it; always learn it from the camera.

**The camera sends no application reply to this client.** It acts on what it receives without answering. Confirm delivery from the advancing `una`, never from an acknowledgement, and never treat silence as failure.

## Also answer the media channel

A real screen runs three conversations across two UDP port pairs and answers the camera's bootstrap on all of them within about 11 ms:

| Conversation | Ports | Role |
| --- | --- | --- |
| control | screen 6021 ↔ camera 6000 | configuration RPC |
| media ×2 | screen 6023 ↔ camera 6002 | video and audio |

A control-only client leaves the camera repeating its hello about once per second, against roughly every thirty seconds in a healthy session. `ScreenMedia` in `tools/luna_screen_live.py` answers the media bootstrap and keeps a KCP endpoint per conversation so the camera receives transport ACKs. It does not decode media.

## Regenerating the command bodies (required)

`set_recovery` replays a byte-exact configuration body. Those bodies live in **`.local/recovery-set-bodies.json`, which is gitignored**, as are the captures they derive from. A fresh checkout will not have them and must regenerate them from a decrypted capture of the screen toggling Recovery.

1. Take a decryptable capture following [the capture procedure](#capture-procedure-for-a-fresh-camera) below, producing `<folder>/udp.tsv`.
2. Extract complete service 1 / method 2 requests with `CaptureAssembler` from `tools/luna_screen_wire.py`, filtered to screen→camera (source port 6021).
3. For each, the RPC body is `token[8] + LE32(json_len) + json`. Key them by `iq_ilog_lut.enable`.
4. Verify the two bodies differ in **exactly** `/iq_ilog_lut/enable` and `/iq_ilog_lut/lut_type` before saving, and that both carry the same opaque token.

Synthesising a body from scratch is not currently possible because this client has no working read path, so the unrelated settings would have to be invented. **Replaying a stale snapshot restores that snapshot's exposure, white balance and other values.** This is the most significant limitation of the current approach.

## Runbook

The camera powers its Wi-Fi down when the screen is attached, so the access point must be woken first.

```sh
.venv/bin/python tools/luna_ble.py --name XBQFN7      # wake the AP; camera must be paired
networksetup -setairportnetwork en0 "$SSID" "$PASSWORD"
networksetup -setmanual Wi-Fi 192.168.42.253 255.255.255.0 192.168.42.1
/usr/bin/python3 tools/luna_recovery_lab.py           # viewer + toggle, prints a local URL
```

The Mac must hold **192.168.42.253**, the screen's address, and the screen should be **attached** so it is not competing for it. Ethernet can stay the default route. Restore with `networksetup -setdhcp Wi-Fi`.

## Detecting state without a readback

Because the camera never reports its state on this path, a client cannot ask. Two options:

- **Passive capture.** Sniff the screen link and parse `iq_ilog_lut.enable` from configuration traffic. Accurate, but needs monitor mode and a present screen.
- **Infer from the picture.** Saturation separates the states cleanly. Its absolute value is scene-dependent, so do not use a fixed threshold. The lab calibrates against readings taken after each commanded change and classifies by nearest, which is scene-independent and self-correcting.

The lab obtains statistics by splitting the decode graph, sampling at 1 fps through `signalstats`. Note that `metadata=print:file=` is **buffered and never flushes live**; print to the log stream and tail that instead. Allow about four seconds after a change before sampling, then take a median of several readings: the camera encoder, the stream and the sampler together lag enough that a single early sample records the previous state.

## Current limitations

1. **No read path.** The camera does not answer configuration reads from this client, so there is no readback and no way to build a body from current settings.
2. **Bulk replace only.** No minimal single-field PATCH form is demonstrated. Every write carries unrelated settings.
3. **Snapshot staleness.** Replayed bodies restore the captured session's unrelated settings.
4. **Capture-derived inputs.** The command bodies must be regenerated per camera from a decrypted capture.

Resolving 1 would resolve 2 and 3 together, since a current configuration could then be read, modified in place and written back. The open lead is that the real screen performs a substantial opening sequence our client does not: a continuous service 4 method 1 upstream of 678-byte bodies carrying the ASCII magic `IDUA`, about sixteen per second, plus small service 5117 status messages on route `0x17fe → 0x07ff`. The camera's first application message follows roughly 484 ms after that begins.

## Capture procedure for a fresh camera

A decryptable capture requires the WPA2 four-way handshake, and only one physical action produces one.

1. The screen's power button **also power-cycles the body**; there is no screen-only restart.
2. The screen reconnects from a cached key, emitting no handshake, after attach/detach and after leaving and re-entering range. Neither yields keys.
3. A full handshake occurs only on the screen's **first association after a camera reboot**, which clears the camera's cached-key table.
4. The 2.4 GHz link channel is reassigned on every camera reboot; 9, 2 and 3 were seen in one session. Verify by received traffic, because the CoreWLAN channel readback can be stale.

Sequence: detach the screen and confirm a picture, sweep 2.4 GHz for the channel, arm the capture there, reboot the camera, then detach again so the first association lands inside the capture. Derive keys with `.local/luna-wpa-offline.py <pcapng> <profile>`, which must report verified message kinds 3 and 4, and writes `udp.tsv` beside the capture.

With the screen attached only the 5 GHz phone AP is advertised. An associated but idle screen emits only QoS Null keepalives, so a low frame count means idle, not wrong channel.

## Code map

| Path | Tracked | Role |
| --- | --- | --- |
| `tools/luna_screen_wire.py` | yes | envelope/RPC/KCP decoding, `CaptureAssembler` |
| `tools/luna_screen_live.py` | no | live client: `ScreenControl.prime`, `KCP.jump_send`/`jump_recv`, `ScreenMedia`, `set_recovery` |
| `tools/luna_recovery_lab.py` | no | viewer, toggle, picture-based detection, local HTTP UI |
| `tools/luna_recovery_lab.html` | no | the page |
| `tools/luna_ble.py` | yes | BLE bootstrap that wakes the access point |
| `.local/luna_recovery_set.py` | ignored | headless one-shot setter |
| `.local/luna_allchannel_probe.py` | ignored | read-only bootstrap/priming reproducer |
| `.local/recovery-set-bodies.json` | ignored | extracted command bodies, regenerate per camera |

The three `tools/` entries marked untracked are working code that is not yet committed.

## In the app

The Apple app turns Color Recovery **off automatically** whenever it connects, so monitoring never runs on converted video.

| Piece | Where |
| --- | --- |
| Screen RPC client, KCP bindings, priming, media responder | `Adapters/Insta360Apple/Sources/Insta360Apple/LunaScreenRecovery.swift` |
| Connect flow, automatic off, manual override | `Adapters/Insta360Apple/Sources/Insta360Apple/LunaCameraBackend.swift` |
| Address check and operator instruction | `Adapters/Insta360Apple/Sources/Insta360Apple/LunaWiFi.swift` |
| Shipped command bodies | `Apps/Apple/OpenInstaCine/RecoveryBodies.json`, bundled as a resource |
| Invariant guard | `tools/test_recovery_bodies.py`, runs under `just check` |

Flow, in `connect`: join Wi-Fi, report the address problem if there is one, start the recovery-off task, open video, and once streaming await that task. Recovery-off therefore overlaps the video handshake instead of delaying first picture, and is confirmed before the session is considered up. It runs on **every** connect path, including reconnects that reuse stored credentials. `turnColorRecoveryOff` always sends OFF rather than toggling: unknown is not off, and treating it as off was the client bug that made the lab's button appear reversed.

Manual control stays available through the `colorRecovery` camera control, which routes to `LunaScreenRecovery.setRecovery`.

### The address requirement is the thing that will bite you

The camera invites **only** `192.168.42.253`, the detachable screen's address. From an ordinary DHCP lease it sends no invitation, so there is no conversation, nothing to prime, and the write cannot happen. The app cannot fix this itself: `Process` is unavailable on Mac Catalyst and iOS has no API for a manual address. So `LunaWiFi.screenAddressInstruction()` returns platform-specific wording and the backend surfaces it as a note the moment it connects, rather than letting the write fail later with a bare timeout.

Set the camera Wi-Fi to that address manually, mask `255.255.255.0`, router `192.168.42.1`. Claiming it while the real screen is detached and associated would collide; attach the screen, or accept that the screen loses its link.

Because the address must be settled before any socket opens, do not move the check later in `connect`. Changing the address after the video socket exists drops the feed.

### Verified on iPhone, 2026-09-17

With the manual address set once in iOS Settings, the app on an iPhone 16 Pro Max (iOS 27.0) establishes the screen conversation, primes, writes, and the camera accepts:

```text
luna: holding the screen address
screen: conversation=0x25003a primed=1 media=true
screen: body=2636 before=1 after=3
luna: Color Recovery OFF accepted
```

The window advancing by two per write is the same acceptance signature as on the Mac. Two things were needed on device beyond the address. Acceptance is **intermittent**: three attempts failed and a fourth succeeded with no other difference, so `setRecovery` now retries up to three times, re-priming between attempts. And the acceptance window was widened from 1.5 s to 6 s, since a 2.6 KB body fragments across segments and needs a retransmit window rather than one round trip. End to end the automatic off takes roughly nine seconds after the feed opens, most of it the bootstrap settling; that is a tuning opportunity, not a correctness issue.

The `NSLog` wire tracing in `LunaScreenRecovery` is deliberately left in for now. It made the sequence numbers visible through `devicectl` console, which OSLog output does not reach, and was how the fragment sequences were confirmed.

### Build status

`just apple-build` (iOS Simulator) succeeds, and the `Insta360Apple` scheme builds for Mac Catalyst. The full Catalyst app build currently fails in the untracked `Shared/Apple/MonitorShell/PlaybackAudio.swift`, which uses `MTAudioProcessingTap` symbols unavailable on Catalyst. That is unrelated to Color Recovery and predates this work.

## Why the screen's address is required, tested rather than assumed

A reasonable objection is that the client should not have to impersonate the screen at all: stay an ordinary app client and send the same command. Both halves of that were tested on 2026-09-17 and neither works on v1.0.288.

**The phone protocol does not expose this configuration.** Sweeping the read commands the official app uses (8, 15, 38, 43, 55, 59, 64, 66, 68, 118, 179, 216, 217) found no response containing `iq_ilog_lut`, `iq_color_mode`, `lut_type` or any `iq_` key. `PHONE_COMMAND_GET_CAMERA_PARAMS_JSON` (216) exists in the published schema and the camera answers 200 with an **empty body**. The two substantial responses are clip metadata: 38 returns 9,102 bytes of file paths and lens calibration, 66 returns 857 bytes. Photography option 73 remains the only phone-side handle and is a no-op. The `iq_*` namespace simply is not reachable over TCP 6666.

**The screen protocol does not answer another address.** From an ordinary DHCP lease (192.168.42.136), binding the screen's ports and sending the kind-2 solicitation directly to the camera produced **zero datagrams in reply**. The camera does not invite, does not answer a solicitation, and never opens a conversation. Without a conversation there is no identifier and no sequence, so there is nothing to send the command into.

So the address is not a stylistic choice about impersonation. The camera binds this entire namespace to whatever occupies `192.168.42.253`, and grants it to nothing else. What would remove the requirement is firmware making option 73 functional, or discovering a phone command that carries the same configuration; neither exists on v1.0.288.

## Is there a pre-conversion feed we missed? Tested 2026-09-17

With Recovery **on** (black level 17, converted), every `StartLiveStream` variant the schema exposes was requested from the Mac over the phone protocol and measured the same way:

| Variant | Request change | YLOW | Result |
| --- | --- | ---: | --- |
| baseline | current app request | 17 | converted |
| two_streams | `previewStreamNum = 2` (with `resolution1` already set) | 17 | converted, no second stream appeared |
| client_beacon | `client_type = BEACON` | 17 | converted |
| client_glasses | `client_type = BEACON_GLASSES` | 17 | converted |
| is_for_live | `isForLive = true` | 17 | converted |
| client_ios | `client_type = IOS` | 17 | converted |

The media channel carried the same three subtypes in every case (32 image, 48 motion, 64 scalar); the two-stream request produced no additional stream. The detachable screen's link carries exactly one video conversation, the other media conversation is bootstrap only. Command 38 and 66 responses are clip metadata. **No pre-conversion feed exists on either surface on v1.0.288.** The conversion is applied upstream of every encoder the camera exposes, so the only ways to a flat feed are turning Recovery off or inverting the conversion in the monitor.
