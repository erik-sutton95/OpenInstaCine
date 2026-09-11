# Luna detached-screen transport: captured and decrypted

Date: **2026-09-11**. Camera: the user's Luna Ultra; the established camera firmware baseline is v1.0.288, not independently queried during this passive take. Scope: the screen's own wireless connection, with phone camera apps disconnected. This is a packet-analysis result, not an implemented screen client or a verified pre-LUT capability.

## Result

We captured the detached screen's normal attach/detach reconnect, recovered its complete WPA2 handshake, and decrypted its IP traffic using the camera credentials already obtained by our authorized BLE client. The screen uses a **different transport from the phone preview**:

| Direction | Observed endpoints | Contents |
| --- | --- | --- |
| Camera → screen | `192.168.42.1:6000` → `192.168.42.253:6021` UDP | KCP conversation `0x001e0007`, control/RPC traffic |
| Screen → camera | `192.168.42.253:6021` → `192.168.42.1:6000` UDP | Control requests and acknowledgments |
| Camera → screen | `192.168.42.1:6002` → `192.168.42.253:6023` UDP | KCP conversation `0x001e0008`, H.264 video messages |
| Screen → camera | `192.168.42.253:6023` → `192.168.42.1:6002` UDP | KCP acknowledgments and bootstrap traffic |

These addresses/ports are observed values, not established constants for all firmware or models. The previously verified phone client uses TCP port 6666 with UCD2 framing and HEVC video. Neither its session commands nor its media parser can simply be applied to this UDP transport.

**The pre-Color-Recovery question remains open.** Actual H.264 payloads are present after Wi-Fi decryption, but the available reconnect take lacks the decoder setup needed to produce a usable picture. No claim is made that this feed is I-Log, that Color Recovery is applied inside the screen, or that simultaneous app and screen preview works.

## Capture and attribution

The private session is `captures/20260911T130348Z-luna-screen-confirmed-live/`. It contains the initial management capture, full `reconnect.pcapng` (72,102,064 bytes), action markers, capture logs, and decrypted UDP inventory. The user confirmed an updating picture on the detached screen before the take, then performed attachment for ten seconds, detachment, and continued live preview, reporting completion afterward. Action markers are retrospective report times; exact physical transition times must not be inferred from them.

The camera network was visible on **channel 3 / 2422 MHz**, advertising RSN PSK authentication and CCMP. Packet frames **9394, 9397, 9400, and 9401** contain handshake messages 1–4 between the camera and the peer subsequently communicating as `192.168.42.253`; frame 9402 repeats message 4. Their radio bad-FCS flags are false. The exchange occurs at approximately **13:05:26.193–13:05:26.223 UTC**. The known camera password and SSID derive a working WPA2 key for this association. Wireshark documents the requirement for both key material and the captured per-device handshake. [Wireshark decryption guide][decrypt]

The decryption profile is private under `.local/luna-screen-decrypt-profile/`; its derived key is credential-equivalent and must not be published. Raw packet captures, device identifiers, decoded payloads and any eventual images also remain ignored local artifacts.

## Transport and video framing

Both channels have the standard **24-byte KCP segment header**: little-endian conversation ID, command, fragment count, receive window, timestamp, segment sequence, acknowledged sequence boundary, and payload length. Commands `0x51` and `0x52` correspond to PUSH and ACK. A UDP datagram can contain multiple KCP segments. Do not equate datagrams with complete messages, and do not append retransmissions to a video stream. [KCP implementation][kcp]

There is also a short bootstrap exchange outside the ordinary KCP segment format. The [control analysis](luna-screen-udp-control.md) records that exchange and the reconstructed RPC envelope. Its field meanings beyond their observed structure remain partly unknown; no packets have been replayed to the camera.

For camera-to-screen video, offline reassembly of the selected good-radio-FCS UDP records found:

- 32,837 KCP PUSH segments, comprising **31,542 distinct sequence numbers** and 1,295 exact duplicates; no conflicting payloads for a sequence number and no truncated KCP segment bodies in this extracted set.
- **1,752 complete, recognizable application messages**. All have the observed 12-byte envelope and an exact 24-bit payload length in bytes 5–7. An additional 1,481 sequence groups have internal/end gaps; 190 contiguous suffix groups lack a recognizable message prefix and are also excluded. A suffix reaching fragment zero is not proof that its first fragment was captured.
- Each accepted video message has an H.264 Annex-B access-unit delimiter at byte **102**. The preceding 32-bit little-endian value equals the remaining video length for every accepted message.
- Each accepted access unit contains NAL type **9** (access-unit delimiter) and type **1** (non-IDR coded slice). A wider check of 3,091 available video first fragments also found no SPS, PPS or IDR NALs.

The available messages therefore do **not** suffice to initialize a decoder. `ffprobe` recognizes H.264 but cannot establish picture dimensions or pixel format. The concatenated local `.h264` artifact is an incomplete temporal sequence for analysis, not a playable or validated preview. The offline extractor and summaries are under `.local/luna-screen-video/`.

The ongoing KCP sequence numbers and RPC request IDs support the inference that the attach/detach operation resumed an existing logical stream rather than its initial encoder/session setup. The control analysis also found no SPS/PPS in its complete messages. Missing captured segments still limit negative conclusions. A capture that begins before a fresh screen/camera streaming session is the next useful way to obtain decoder configuration and the initial independently decodable picture.

## User's Color Recovery observation

After the take, the user reported that the I-Log menu calls the setting **“Color recovery” while attached** and **“preview reset to:” while detached**. The selectable choices and current selected value were requested but had not yet been supplied when this note was written. Record the wording as an operator observation; do not invent a setting value or map it to a protocol field.

The label difference is a reason to investigate a screen-specific preview control. It does not by itself locate the transform. Establish the incoming image encoding using decoded samples and a controlled scene, then compare settings one at a time while recording the associated control messages. A successful pre-LUT result requires unconverted incoming I-Log values while the desired corrected screen view remains enabled.

## Mac capture behavior and cleanup

CoreWLAN channel selection requires the Mac to be disassociated. More subtly, **opening/closing a monitor capture can let the radio move away from the requested channel**. During this take, the first management capture contained channel-3 packets, but the next capture initially received packets on other channels even while `wlanChannel()` reported 3. Explicitly retuning after the full capture opened restored sustained channel-3 traffic; the most recent radiotap frequencies were checked before the user was instructed to reconnect.

For future takes, verify actual recent packet frequencies; interface readback alone is insufficient. Retain management/handshake traffic during target discovery so a changed association is not excluded by an old MAC-only filter. A short discovery pass may use truncated headers; the actual media take requires full packet lengths.

All capture processes from this take were stopped. Wi-Fi power and channel were restored, then System Settings rejoined the normal known network and visibly reported Connected. The Mac regained its original `192.168.1.87` address; Ethernet remained the default route. No camera settings, app binaries or firmware were changed by the tools in this investigation.

[decrypt]: https://wiki.wireshark.org/HowToDecrypt802.11
[kcp]: https://github.com/skywind3000/kcp/blob/b1a7a2101dcbb96017681a500d6b82bbe5a88766/ikcp.c#L789
