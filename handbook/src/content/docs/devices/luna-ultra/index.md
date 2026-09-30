---
title: Luna Ultra
description: Luna Ultra firmware 1.1.15 survey organized by command family, shooting mode, media output and evidence.
---

This reference records the Insta360 Luna Ultra as OpenInstaCine talks to it.
The protocol was first mapped on camera firmware **v1.0.288** with the
**Insta360 iOS app 2.33.0** (September 2026), then re-verified command by
command on **firmware v1.1.15** (25 to 30 September 2026) with our own Mac and
iPhone clients, plus official-app captures on the same firmware. OpenInstaCine
support is documented separately in the [iOS](../../apps/ios/) and
[Android](../../apps/android/) pages.

Firmware updates can change the menu and protocol behavior, so retain the
version when comparing results. Everything below applies to v1.1.15 unless it
says otherwise.

## Find a command or capability

| Reference | Contents |
| --- | --- |
| [Command comparison](./commands/) | Command families, differences from the DJI Osmo protocol, and links to the evidence |
| [Shooting modes and formats](./modes/) | Video, Timelapse, TimeShift, Slow Motion, PureVideo, Photo and Pano; mode banks; the accepted resolution list |
| [Exposure, focus and audio](./settings/) | ISO, shutter, EV, white balance, color, sharpness, filters, AF mode, metering, audio and timecode |
| [Zoom and gimbal controls](./controls/) | Zoom to 15x, gimbal modes and speed, stick, recenter, flip, absolute angle, head tracking and Deep Track |
| [Original media](./media/) | Recording, photo, file lists, metadata, NV12 thumbnails, HTTP originals and `.lrv` proxies, delete |
| [Connection and reconnect](./connection/) | Bluetooth wake, Wi-Fi lifetime, session keep-alive, polls and reconnect evidence |
| [Coverage and implementation](./coverage/) | What is verified, what the official app does that OpenInstaCine does not, and remaining gaps |

Shared framing and reusable commands remain in the
[command catalog](../../protocol/commands/). The pages here preserve the Luna
Ultra values, restrictions and evidence needed to apply them.

## How to read the evidence

| Evidence | What it establishes |
| --- | --- |
| **Schema** | A community protobuf schema or the official app's generated message classes name the field or command. Not proof that this body or firmware implements it. |
| **Observed** | An official Insta360 app request or camera reply was captured on this camera and decoded. |
| **Accepted** | Our own client sent the request and the camera replied 200. A 200 alone does not prove the value was stored or took effect. |
| **Verified** | Our client sent the request and a separate GET read the value back, or the effect was seen in the live picture or on the camera. |
| **Unknown** | No sufficient evidence yet. |

The survey recorded the official app's phone traffic on the camera network and
our own client's traffic. Private footage, credentials, identifiers, serial
numbers and raw captures are excluded from this reference. The chronological
research logs are in the repository under
[`docs/research/`](https://github.com/erik-sutton95/OpenInstaCine/tree/main/docs/research);
the firmware 1.1.15 record is
[`luna-fw-1.1.15-verification.md`](https://github.com/erik-sutton95/OpenInstaCine/blob/main/docs/research/luna-fw-1.1.15-verification.md).

## Sources

- Community protobuf schema
  [iliakonnov/insta360-nas](https://github.com/iliakonnov/insta360-nas/blob/b78dddb9cd9bc2cf632871646c6f5af238e582d4/insta360-server/insta360_messages.proto)
  (pinned commit), later checked against the message classes in the official
  Android app 2.34.5.
- The Bluetooth bootstrap was learned with the help of
  [luna-ai-cut](https://github.com/diamondfsd/luna-ai-cut) (MIT), and hardware
  notes from
  [insta360-luna-ultra-desktop](https://github.com/Ripwords/insta360-luna-ultra-desktop).
- Everything else was mapped from our own Bluetooth and Wi-Fi captures and our
  own client's requests.
