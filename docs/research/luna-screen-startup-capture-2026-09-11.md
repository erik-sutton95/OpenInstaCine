# Luna screen startup: first independently decoded picture

Measured **2026-09-11** using the user's Luna Ultra. **The detachable screen's own wireless video is now decrypted and decoded**, including its original SPS, PPS and first IDR frame. This resolves the decoder-initialization gap in the [earlier reconnect capture](luna-screen-transport-capture-2026-09-11.md). It does not yet establish a pre-Color-Recovery feed or implement a replacement screen client.

## Operator sequence and capture

The user was instructed to disconnect phone camera apps, attach the screen, select 10-bit I-Log with Color Recovery enabled, normally power off the camera, wait for shutdown plus ten seconds, power on, then detach after live preview appeared. After thirty seconds of detached preview, they checked the selected value of “preview reset to:” without changing it and returned to live view.

The user reported **“done, and on”**. Record the detached selection as **On** and the sequence as operator-confirmed, not as settings independently queried by our client. The report time does not establish exact physical transition times. No Off comparison was performed in this take.

Private evidence is in `captures/20260911T140806Z-luna-screen-startup-confirmed/`:

- Original `startup.pcapng`: **43,390,164 bytes, 40,012 packets**.
- Capture interval: **14:08:07.469–14:12:37.767 UTC**. Initial radio settling includes 172 packets on 2412 MHz; the subsequent 39,840 are on the screen's observed **2422 MHz / channel 3**.
- `operator-done.json`, `radio.json`, capture log, handshake inventory, decrypted UDP exports and offline protocol analysis preserve the take's provenance.
- Original capture bytes were not repaired, overwritten or replayed to a device.

## Decryption despite a damaged handshake packet

The four observed WPA2 handshake messages are frames **250, 253, 255 and 256**, around **14:11:08.960–14:11:08.997 UTC**. Frames 250, 255 and 256 pass their recorded 802.11 FCS. Frame **253**, message 2, has a bad radio FCS, malformed content, and an invalid whole-message MIC. The ordinary PMK-based Wireshark profile did not decrypt this take automatically.

Nevertheless, message 2's **SNonce is intact**. Using the already owned camera password/SSID, the AP/station addresses from good message 1, and the two captured nonces yields a KCK that independently validates the MICs of both **message 3 and message 4**. This establishes usable key-derivation inputs without pretending the damaged message itself is valid.

The offline derivation uses the standard WPA2 pairwise-key expansion:

1. PMK: PBKDF2-HMAC-SHA1 over password and SSID, 4,096 iterations, 32-byte result.
2. Expansion context: lexicographically ordered AP/station MACs followed by lexicographically ordered ANonce/SNonce. Nonces occupy bytes **17–48** of the complete EAPOL-Key packet, including its four-byte EAPOL header.
3. Expand with HMAC-SHA1, label `Pairwise key expansion`, a zero separator and zero-based one-byte block counters. KCK is PTK bytes 0–15; the CCMP temporal key is bytes 32–47.
4. Validate each held-out EAPOL MIC with HMAC-SHA1 truncated to 16 bytes, zeroing bytes **81–96** of that EAPOL packet during calculation. Both messages use descriptor version 2.
5. Supply only the derived temporal key to a separate private Wireshark profile using the supported `tk` key type. Wireshark documents direct temporal-key decryption without a usable four-way-handshake reconstruction. [Wireshark WLAN key documentation][wireshark-keys]

This produced **33,657 decrypted, radio-FCS-good UDP datagrams** from the unchanged capture. Including two additionally decrypted bad-radio-FCS video datagrams did not increase the number of complete CRC-valid video messages; the primary analysis retains the FCS-good export. Both application-envelope CRC16s are also checked after KCP reassembly.

The temporal key is credential-equivalent and private under `.local/20260911T140806Z-luna-screen-startup-confirmed-decrypt-profile/`, with restrictive permissions. It belongs to this association. Do not reuse it as a permanent camera credential or publish it. The take's `decryption-report.json` records the validation without key material.

## Transport and decoder result

The observed IP addresses and port pairs match the earlier take, but the KCP conversations **changed**:

| Channel | Endpoints | This conversation | First captured PUSH sequence |
| --- | --- | --- | --- |
| Camera control | `192.168.42.1:6000 → 192.168.42.253:6021` | `0x0020000a` | 0 |
| Screen control | Reverse | `0x0020000a` | 0 |
| Camera video | `192.168.42.1:6002 → 192.168.42.253:6023` | `0x0020000b` | 0 |
| Screen video ACKs | Reverse | `0x0020000b` | No PUSH messages |

The prior conversations were `0x001e0007` and `0x001e0008`. These values must remain session inputs, not product constants. The existing [offline parser](../../tools/luna_screen_wire.py) handles the new conversations without code changes.

Video accounting on the FCS-good export:

- **22,689 PUSH segments**, 2,096 identical retries, zero conflicting retransmissions.
- **1,490 complete messages**, all passing exact envelope length and both CRC16 checks.
- **634 incomplete groups** and **73 invalid-envelope suffix groups** excluded.
- **20,600,485 H.264 bytes** in complete access units.
- NAL inventory: 1,490 AUDs, 1,489 non-IDR slices, **one SPS, one PPS and one IDR**.

The first video message starts at frame **364 / 14:11:09.728 UTC**, covering KCP sequences **0–7**. It contains NAL types **9, 7, 8, 5** in the established service 2/method 3/category 1 media envelope. H.264 begins at message byte 102, with its exact length at bytes 98–101, as in the earlier take.

`ffprobe` reports:

| Property | Measured value |
| --- | --- |
| Codec/profile | H.264 High, level 2.1 |
| Displayed dimensions | **556 × 314** |
| Sample format | **8-bit `yuv420p`** |
| Range | Limited / TV |
| Colour metadata | BT.709 primaries, transfer and matrix |
| Decoder extradata | 41 bytes |

These are properties of this captured session, not a proven maximum resolution for the screen protocol. Frame-rate fields in a raw, incomplete elementary stream are not treated as measured capture cadence. BT.709 signalling alone does not establish whether pixel values carry I-Log or a viewing transform.

The isolated first access unit, `first-idr.h264`, decodes with FFmpeg without decoder errors and produces a complete **523,752-byte RGB frame**. Its pixels exactly match the saved `.local/luna-startup-first-frame.png`. The larger `.local/luna-startup-screen.h264` concatenates complete captured messages but still contains temporal gaps; it is not claimed as a continuous error-free video.

## Startup control and remaining uncertainty

Reassembly yields **1,945 camera-to-screen** and **2,280 screen-to-camera** complete CRC-valid control messages. The camera direction has one incomplete group and one invalid-envelope group. The first two control messages are a camera service 4/method 4/category 0 request and matching screen category 2 reply. Their semantics remain unknown.

At frame **360**, the camera sends a service **2/method 1/category 2** reply with a four-byte zero body, immediately before the first video message. Its corresponding screen request was not recovered: screen PUSH sequences **1–3** are missing between captured sequence 0 and sequence 4. This reply is a promising start-operation lead, but neither the missing request body nor the meanings of its parameters can be invented from the response. Fresh KCP sequences do not prove that every earlier pairing or application-session operation occurred over captured Wi-Fi.

No named `color_recovery`, `preview_reset`, `ilog`, `i-log` or `lut` selector was found in the recovered complete control bodies. Binary fields remain unmapped. The decoded picture looks contrasty and colour-restored with the operator-reported setting On; this is **visual inference**, not proof of which device applies the transform.

The next useful physical test is a fixed-scene **On → Off → On** comparison with decoder startup captured and setting transitions recorded. Compare incoming image values, associated control requests and whether the encoder restarts. An independent live client also still needs the missing start request and verified session handling. No claim is made that this route currently avoids app/screen coexistence restrictions.

## Cleanup and reproduction

The owned capture process was stopped. Normal Mac Wi-Fi was rejoined through System Settings and verified as **Connected**, with en0 back at `192.168.1.87`; Ethernet remained the default route. No connected-phone app was launched, and no camera command was transmitted by these tools. No further operator actions were requested during offline analysis.

Reproduce the primary video assembly with the saved private export:

```sh
python3 tools/luna_screen_capture.py \
  captures/20260911T140806Z-luna-screen-startup-confirmed/udp.tsv \
  --source-ip 192.168.42.1 --source-port 6002 --destination-port 6023 \
  --conversation 0x0020000b
```

Raw captures, credentials, device identifiers and decoded images remain ignored local artifacts. This note publishes protocol evidence only.

## Mac side-by-side playback

At the user's request, a local AVKit comparison window was built and opened with [the capture player](../../tools/luna_capture_compare.swift). Both sources are labelled **capture replay**, with independent capture times and no added LUT. This operation used local files only and made no new camera or network connections.

The left source is the earlier `20260911T123418Z-luna-color-recovery-rvi` phone capture, beginning around 12:34 UTC: **1280 × 720 HEVC**. TCP-follow reassembly and an accelerated UCD2 checksum implementation (cross-checked against the existing Python reference) validate **16,693 camera frames, zero checksum failures, zero leftover bytes**, including all **6,783 video messages**. A 750-frame clip begins at the first captured HEVC parameter-set/IDR group, video index 39, and is remuxed to MP4 without a LUT. This extends the prior RVI audit, which had not validated media checksums.

The right source is this 14:11 UTC screen capture. Its first **17 complete video messages / 0.633 seconds between capture timestamps** form a continuous sequence before the first gap. A separate clean-startup MP4 preserves those units. A longer viewing copy is transcoded from the incomplete reconstructed stream for native-player compatibility; it can contain decoder concealment and capture-gap artifacts, and its playback timing is not an original synchronized timeline. The window offers both versions and shared play/pause/restart controls.

Native UI inspection verified both pictures visible. In this comparison the phone image appears flatter and the screen image more contrasty. Their capture times, camera framing and confirmed setting provenance differ, so **this visual difference cannot establish a simultaneous pre-LUT screen route**. The phone capture's Color Recovery state remains unknown. Use the planned controlled On/Off comparison to determine whether transmitted pixels change with the screen option.

The opened app and media remain under `.local/luna-capture-compare/`. To rebuild the reusable viewer, compile the Swift source and supply three media paths followed by two explicit source captions; metadata is not inferred from filenames.

[wireshark-keys]: https://www.wireshark.org/docs/wsug_html_chunked/Ch80211Keys.html
