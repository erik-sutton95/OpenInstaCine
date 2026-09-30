---
title: UCD2 transport
description: TCP port 6666, the preface and greeting, heartbeats, authorization and reassembly.
---

After the phone has joined the camera [network](../wifi/), control and live view
share one TCP connection. Framing is [UCD2](../ucd2-frame/); every TCP message is
plain.

## Open the session

Connect to **`192.168.42.1:6666`**, then:

1. Send the 17-byte preface:

   ```text
   11 00 00 00 06 00 00 af fa af fa af fa af fa af fa
   ```

   It resembles an older Insta360 SYNC frame with a different magic. The camera
   answers with a UCD2 greeting, not an echo.
2. Wait for the camera's **type-5** greeting.
3. Start heartbeats: OpenInstaCine sends an empty type-5 frame every **2 s**.
   The official app on firmware 1.1.15 sends one after the preface and then none;
   the camera sends type 5 at 1 Hz.
4. Read device information (cmd 8), then check authorization (cmd **39**) with
   the same saved UUID used over BLE. Status 0 proceeds.
5. Read capture status (cmd 15), wake the gimbal (cmd 118 `{1:5}`), and start
   [live view](../live-view/) (cmd 1). Acknowledge the live-start reply before
   reporting the session live; the first decoded frame is a separate signal.

On close, attempt a live stop (cmd 2) if the start might have reached the camera,
then close the socket and clear every pending request.

| Command | Meaning |
| --- | --- |
| 8 / 7 | Get / set device options |
| 39 | Authorization check (plain, same UUID as BLE) |
| 15 | Current capture status |
| 118 | Camera file-access state: 5 shooting view (wakes the gimbal), 1 media |
| 1 / 2 | Start / stop live stream |

### Official-app startup

The official app's reconnect also sends a SetOptions with the phone's local time
and timezone, many option reads, a file-list and cloud-status burst, and command
265 (`GET_EXCEPTION_LOG_REPORT`). Command 83 gets **500** and later commands
continue, so record per-command outcomes: a valid checksum or an open socket does
not mean every operation succeeded. None of the cloud or log commands are needed
for live view.

## Reassembly

TCP delivers arbitrary fragments and coalesced frames. `UCD2Reassembler` accepts
any split: it keeps a cursor while draining a batch, checksums against the
buffered bytes, and compacts between batches instead of shifting the stream for
every video packet. The default frame limit is 4 MiB. An oversized header or a
bad checksum is skipped and counted, and the next valid frame is recovered; the
adapter decides whether that warrants a disconnect. Feed it moderate chunks (for
example 64 KiB).

Protobuf parsing validates the whole message before exposing fields, caps a
message at 1 MiB and 16,384 fields by default, checks varint overflow and length
bounds, and rejects groups.

## Request correlation

Replies echo the request ID with the request bit set. The Apple adapter keys each
outstanding request by transport generation plus operation ID and completes it
only after both a valid reply and, on BLE, the write completion, which covers a
notification that arrives before the write acknowledgment. The camera can also
send an unmatched 200 (for example the URI of a new photo, see
[Original media](../../devices/luna-ultra/media/#recording-and-photos)).
