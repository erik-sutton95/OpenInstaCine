# Luna Ultra detachable-screen radio and video-link research

Research date: **2026-09-11**. This note records official hardware/manual evidence and public protocol-source candidates. It performed no hardware operations and does not claim to have captured or decoded the screen link. The user has detached the screen; the local capture investigation is separate.

**The detached screen is a justified new capture target: Insta360 documents Wi-Fi image transmission and a separate 2.4 GHz screen radio. Whether that link carries pre-Color-Recovery I-Log remains unknown.** “Pre-LUT” means unconverted I-Log preview values, not sensor RAW.

## Documented radio facts

| Item | Evidence | Implication for capture |
| --- | --- | --- |
| Camera-body WLAN | Wi-Fi 6, 802.11 a/b/g/n/ac/ax. [Official hardware specifications][hardware] | Do not transfer the phone connection's radio settings to the screen automatically. |
| Screen WLAN | Wi-Fi 4, 802.11 b/g/n. [Official hardware specifications][hardware] | It is an 802.11 target. |
| Screen frequency | 2.4–2.4835 GHz; body additionally lists 5.15–5.85 GHz. [Official store specifications][store] | Start screen-link discovery in 2.4 GHz. The store's specification text was available in the search index; direct page rendering did not expose that section during this research. |
| Screen image link | The manual explicitly identifies Wi-Fi as the transport used for its detached-screen image-distance test. [User Manual v1.1, printed page 21][manual] | BLE captures alone cannot contain that Wi-Fi video link. |
| Display and battery | Screen: 318×564 OLED and 210 mAh battery. [Official hardware specifications][hardware] | Display dimensions do not establish transmitted video dimensions or codec. |

The screen guide also contains an inconsistent FAQ claiming no independent battery. The hardware specification and manual's detached-operation description contradict that claim. It should not be used to reason that the detached screen is powered or linked through the body. [Screen guide][remote], [hardware specifications][hardware]

## Regulatory evidence: candidate screen identity

Arashi Vision's filing identifies a **Detachable Touchscreen Remote, model CINSBBTT, FCC ID 2AWWH-CINSBBTT**. This is a regulatory model lead; match the user's physical label before treating it as positive attribution of that exact unit. The manufacturer attestation names the model and product. [Arashi Vision attestation, mirrored original PDF][attestation]

The actual DEKRA test reports, read as PDFs, add these details:

- **Wi-Fi report 2610076R.711B**, printed pages 10–12: hardware V10, software V1.2.51, 802.11 b/g/n, SISO, 2412–2462 MHz; test modes include 802.11n HT20 on channels 1, 6 and 11. These are FCC test conditions, not a claim about the user's current firmware or European channel selection. Its laboratory setup lists ADB; this does not establish retail ADB availability or a retail connection method. [Wi-Fi test report][wifi-report]
- **BLE report**, printed page 10: hardware V10/software V1.2.51, GFSK, 40 channels, LE 1M at 1 Mbit/s. This confirms BLE radio capability for the tested screen but does not identify which control, discovery or pairing functions use it. [BLE test report][ble-report]

The accessible filing index lists operational description, schematics and block diagram as metadata only. They were not available as evidence here; no chipset or internal video-pipeline identification is claimed. [Filing index][filing]

## Pairing and topology

The official screen guide says pairing to another compatible body is completed by attaching the screen and performing the documented cold restart. It also states that Luna Ultra and Luna Pro screens are not interchangeable. This establishes physical attachment as part of the supported pairing procedure; it does not disclose whether attachment provisions Wi-Fi credentials, keys or some other identity. Do not infer the pairing bytes or reset an existing pair merely to reproduce the instructions. [Screen guide, FAQs 2 and 4][remote]

No inspected official source specifies the screen's SSID/BSSID, AP/client/P2P role, IP subnet, port, transport framing, codec, link encryption or application encryption. In particular:

- A distinct screen radio does not prove a distinct subnet or credential set.
- If the phone is connected on 5 GHz while the screen is using its documented 2.4 GHz link, those are different radio channels; this alone does not tell us whether the body bridges them.
- Do not assume the screen uses the phone's `192.168.42.1:6666` UCD2 session. An initial radio capture filtered to that IP/port could exclude the evidence needed to discover the screen path.

These are capture implications and open questions, not measured topology.

## Public protocol candidates, not screen-link verification

The community-published `insta360_messages.proto` at commit `b78dddb9cd9bc2cf632871646c6f5af238e582d4` contains the following useful markers. This is primary evidence of that source's definitions, not an official Luna protocol guarantee. [Pinned protobuf source][proto]

| Candidate | Definition |
| --- | --- |
| Notification 8308 | Screen battery update. |
| Notification 8309 | Screen connection status. Status message field 1 contains state. |
| State values | 0 initial; 1 attached; 2 detaching; 3 detached; 4 disconnected. |
| Options field 180 | Screen battery info: field 1 power type, field 2 battery level, field 3 connection state. |
| Firmware device IDs | 3 screen SoC; 4 screen MCU. FirmwareVersionInfo fields: 1 device ID, 2 software version, 3 hardware version. |

The same source has `StartLiveStream.client_type` at field 16, but its enum names only unknown, iOS, Android, beacon and beacon glasses. It supplies **no named detachable-screen value**. Do not equate beacon with this screen without a capture. It also includes `WtClientConnectionReq` and RTP-related WT structures, alongside flight-controller structures; their presence does not attribute that protocol to Luna's screen. [Pinned protobuf source][proto]

The independent Luna desktop project's extracted inventory corroborates the existence of detachable-screen battery/status protobuf files and notification names, without publishing a screen transport implementation. [Extracted protobuf inventory][proto-inventory], [notification-name inventory][message-inventory]

## What a useful capture must establish

These recommendations guide the separate hardware investigation:

1. Use a **2.4 GHz 802.11 monitor capture**, retaining radio headers, management/control frames and data. Discover peers and channel first, then stay on the identified channel for reconnection and sustained traffic. An ordinary associated interface generally captures its own traffic rather than all camera-to-screen unicast traffic. [Wireshark WLAN capture documentation][capture]
2. Keep the nRF52840 as a possible BLE discovery/control companion. Its supported PHYs are BLE, 802.15.4 and Nordic proprietary modes, not 802.11 b/g/n; sharing the 2.4 GHz band does not make it a Wi-Fi sniffer. [Nordic radio specification][nordic]
3. Attribute radio peers using the screen's attachment/connection transitions and sustained video behavior. Preserve association and key-exchange traffic during a normal reconnect. Do not assume the phone's credentials decrypt the screen association: WPA2 uses per-device session keys, and WPA3 requires more than a password plus captured handshake. Actual screen security remains unknown. [Wireshark decryption documentation][decrypt]
4. Establish whether recovered payloads use UCD2, RTP or another format before implementing a screen client. Metadata notifications about detachment do not themselves expose the video stream.
5. Only after recovering actual image samples can we distinguish camera-side Color Recovery from a LUT applied inside the screen. A screen that displays corrected color is consistent with either arrangement. Keep Color Recovery on for the requested test: success requires an independently obtained pre-LUT image while the screen retains its corrected view.

This research found a concrete radio target and capture markers, **not a confirmed pre-LUT route or a screen-client impersonation recipe**.

## Local capture observations

These measurements were made during the hardware investigation on 2026-09-11. Raw captures and identifiers remain in the ignored `captures/` directory:

- A CoreWLAN scan on `en0` found the camera's phone AP on **5 GHz channel 36**. The screen's 2.4 GHz peer/network was not positively identified.
- After the nRF sniffer reappeared over USB, a 20-second BLE capture contained **183 CRC-valid BE80 advertisements** matching the existing camera identity. It was an advertising capture with no ATT traffic; no separate remote identity was positively matched.
- Initial CoreWLAN channel selection returned **-3903** while the Mac was associated. This was resolved by calling `disassociate()` before `setWLANChannel()`, as required by the installed Apple `CWInterface.h` documentation. The Mac's default route remained Ethernet. A subsequent 20-second channel-3 management capture contained **197 packets**, including **192 Luna management frames**, with zero reported drops. Wi-Fi power and the original channel were restored afterward. Wireless Diagnostics' current Window menu showed only Assistant; its absence of a sniffer did not prevent CLI capture.
- The BLE follow capture started at **12:43:13 UTC for 180 seconds**. The user confirmed completion of the requested phone-app disconnect and screen attach/detach sequence at the retrospective marker time **12:44:46 UTC**. It contained **no decoded ATT**; a snapshot also showed no CRC-valid connection/data packets. This does not prove the screen never uses BLE: the exact physical timing and correct screen-link target remain unverified.
- A Wi-Fi scan after that sequence found the **same advertised Luna network name on 2.4 GHz channel 3**, rather than the earlier 5 GHz channel 36. The subsequent radio capture confirmed channel 3 / **2422 MHz**. The AP beacon advertises **RSN PSK authentication with CCMP**, and 20 MHz HT operation. This identifies a camera network and its advertised security, not yet the screen's association, key or video endpoint.
- The subsequent 180-second capture, `20260911T124800Z-luna-screen-wifi-reconnect`, filtered to that observed BSSID on channel 3, contained **three protected QoS-null packets and no EAPOL, association or video traffic**. It reported zero drops. The filter was independently checked offline against the earlier capture and matched all 192 Luna management frames; channel readback during capture was still 3. The additional requested screen reconnect and an updating detached-screen picture were not confirmed during this take. The absence of traffic therefore does not rule out another channel, changed BSSID, another network or a dormant screen link. Original channel and Wi-Fi power restoration succeeded after the timed capture.
- A subsequent normal Wi-Fi scan no longer showed the Luna-named AP. This is a time-specific scan observation, not proof that the camera or screen was powered off.
- Restoring channel and Wi-Fi power did not automatically restore association. The known normal network was subsequently rejoined through System Settings and verified as **Connected**; Ethernet remained the default route. `networksetup -setairportnetwork` had printed a join failure despite exit code 0, so its exit status alone must not be treated as restoration success.
- No app or firmware changes were made by that investigation.

The earlier iPhone RVI take, `20260911T123418Z-luna-color-recovery-rvi`, contains 104,093 TCP packets / 118,254,160 capture bytes. It stopped because the RVI network adapter detached, with zero capture drops reported. It began during an existing session; the phone sent only heartbeats. TCP reassembly and UCD2 parsing validated all 544 non-media checksums, with no parser leftovers. Four `8308` notifications contain wrapped battery values **93 → 92 → 91 → 90**, but no connection-state field; missing state must remain unknown. No `8309` occurred. Media-header inventory found only `0x20` (6,783 image packets), `0x30` (2,717 motion packets, all multiples of 56 bytes), and `0x40` (6,783 eight-byte scalar packets). Media checksums were not validated in this inventory. Exact detachment time and Color Recovery state were not recorded, so no causal or color-pipeline conclusion follows. The offline findings and analyzer are in `.local/luna-detached-rvi-audit/`.

At this point, the local work had **not decrypted camera-to-screen video** or established which peer carries it, and had not tested the screen stream's color encoding.

[hardware]: https://onlinemanual.insta360.com/lunaultra/en-us/specs/specs
[store]: https://store.insta360.com/cz/product/luna-series?c=6767&from=homepage
[manual]: https://wassets.insta360.com/common/4db5e6eff14241f78fc2b0bfce728688/Luna%20Ultra_User%20Manual_EN_v1.1.pdf
[remote]: https://onlinemanual.insta360.com/lunaultra/en-us/operation-tutorials/appearance/touchscreen-remote
[attestation]: https://manuals.plus/m/0da11a07ca03cbd8ed12e13869b4248e27f518465eb805a7b9c4a484cc182cad.pdf
[wifi-report]: https://fccid.io/m/c12544f445cd068337532d69c3db1fa4425d48bf266e01d9a0a87207a900d476.pdf
[ble-report]: https://fccid.io/m/0495d87e50f2945ab5078a53e457c624c257d683a04f8ce7b92a68bbfe2fbffd.pdf
[filing]: https://fccid.io/2AWWH-CINSBBTT
[proto]: https://github.com/iliakonnov/insta360-nas/blob/b78dddb9cd9bc2cf632871646c6f5af238e582d4/insta360-server/insta360_messages.proto
[proto-inventory]: https://github.com/Ripwords/insta360-luna-ultra-desktop/blob/426d643d302d6818a7d536b815ee15f73bb9c29d/docs/protocol-gap/proto-files.txt
[message-inventory]: https://github.com/Ripwords/insta360-luna-ultra-desktop/blob/426d643d302d6818a7d536b815ee15f73bb9c29d/docs/protocol-gap/message-codes.txt
[capture]: https://wiki.wireshark.org/CaptureSetup/WLAN
[nordic]: https://docs.nordicsemi.com/r/bundle/ps_nrf52840/page/radio.html
[decrypt]: https://wiki.wireshark.org/HowToDecrypt802.11
