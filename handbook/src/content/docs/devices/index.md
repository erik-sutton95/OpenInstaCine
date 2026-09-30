---
title: Insta360 Devices
description: Device-specific command sets, capability surveys, and evidence for Insta360 cameras.
---

These references describe behavior observed on specific Insta360 models and
firmware. Use them alongside the [shared command catalog](../protocol/commands/).
A matching command code does not establish matching payloads, capabilities, or
app support.

| Device | Reference scope |
| --- | --- |
| [Luna Ultra](./luna-ultra/) | Firmware 1.1.15 verification and official-app survey: modes, formats, exposure, focus, zoom, gimbal, Deep Track, media, timecode and connection |

## How to use the references

Start with the device's firmware and evidence scope. Follow its command details
for model-specific values and restrictions. Use
[Shared protocol](../protocol/connection/) for framing, encryption, connection
sequencing and common command definitions.

Evidence levels distinguish a schema entry, an observed official-app request, an
accepted reply, a separate readback, and a physical effect on the camera. An
untested control stays untested even when the schema names it. Hardware surveys
are implementation references, not a statement that either OpenInstaCine app
supports every surveyed feature.

The Luna Ultra is the only camera surveyed so far. Other Insta360 models share
parts of the message schema, but nothing here has been checked on them.
