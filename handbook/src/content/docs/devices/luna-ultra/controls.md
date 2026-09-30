---
title: Luna Ultra zoom and gimbal controls
description: Digital zoom to 15x, gimbal modes and speed, stick, recenter and flip, absolute angle, head tracking and Deep Track.
---

Part of the [Luna Ultra reference](../).
Read the overview for firmware, survey scope and evidence levels.

## Zoom

Zoom is photography option **53** `ZOOM_SCALE`, a double, written with cmd 9.
The dedicated zoom commands 170 and 171 exist in the schema but the official app
never uses them.

| Item | Firmware 1.1.15 |
| --- | --- |
| Range | 1.0 to **15.0** (was 12 in older notes). Values above 15 or below 1 are ignored, not clamped |
| Official presets | 1, 2, 3, 6, 15; the zoom bar streams type 53 every 10 to 25 ms |
| Ramp | The camera ramps: a GET 0.27 s after a SET of 4 read 3.652 |
| Mode switch | Resets zoom to 1.0 (notification 8334 `{53: 1.0}`) |

OpenInstaCine offers chips 1x, 2x, 3x, 6x and 15x plus pinch.

## Gimbal mode and speed

Both are fields of photography option **91** `GIMBAL_OPTIONS`:

| Field | Meaning | Values |
| --- | --- | --- |
| 4 | Mode | 1 FPV, 2 Roll Lock, 3 Roll & Tilt, 4 FPV-V. 5 (lock) is stored but the official app never offers it; 6 is not supported |
| 2 | Follow speed | 1 Slow, 2 Default, 3 Fast. 4 (sensitive) is stored |

Option 92 `GIMBAL_STATUS` and notification 8302 `PTZ_STATE` carry limit, stall
and sleep flags, not a pose.

## Gimbal motion

Gimbal motion is cmd **226** `GIMBAL_CONTROL`:

| Field | Name | Notes |
| --- | --- | --- |
| 1 | `gimbal_action` | 1 MOVE, 2 BACK_CENTER, 3 FLIP, 4 CALI, 5 SET_ANGLE, 6 GET_ANGLE |
| 2 | `virtual_rc` | `up_down` (1) and `left_right` (2), sint32 zigzag |
| 4 | | The official app sends 4 = 4 on every MOVE and release, in every gimbal mode. Not the mode; meaning unproven |
| 5 | `angle` | `{roll 1, pitch 2, yaw 3}` floats, for SET_ANGLE |

### Stick, recenter and flip

| Action | Wire | Evidence |
| --- | --- | --- |
| Stick | action 1 with `virtual_rc`: up +, down -, right +, left -, saturating at about ±99; sent every 50 ms by the official app | Observed and verified |
| Release | action 1 with an **empty** `virtual_rc`, not action 2 | Observed |
| Recenter | action 2; the official app also sends cmd 238 (cancel tracking) | Observed |
| Flip | action 3 | Observed |

The stick is a rate command: about 0.635°/s per unit on pan and 0.54 on tilt
(99 units is about 63 and 53°/s), with an ease-in of about 0.23 s and a stop in
about 0.25 s. Send the release twice, 150 ms apart, from a task that cannot be
cancelled, or the head keeps moving.

### Absolute angle

SET_ANGLE and GET_ANGLE are in the schema but the official app never sends them.
They work on firmware 1.1.15:

```text
SET_ANGLE pitch 10.0, yaw 30.0:  08 05  2a 0a  15 00 00 20 41  1d 00 00 f0 41
GET_ANGLE:                       08 06
```

| Item | Result |
| --- | --- |
| Units and frame | Degrees, gimbal relative to the handle. Yaw right and pitch up are positive. Roll always reads 0 |
| SET reply | `GimbalControlResp` with `grf = 1` and the pose before the move when accepted. An empty body means rejected (yaw outside -180 to 180) |
| GET reply | `grf = 0` once on target, `grf = 1` while travelling or when the target is out of reach |
| Reach (Roll Lock) | Pitch -57.3° to +90°. Yaw is one arc of about 293° with a hard-stop gap from about -125° to -58°; the firmware routes around it |
| Slew | About 75 to 90°/s whatever the follow speed. A 90° step settles in about 1.6 s |
| Modes | Works in Roll Lock, Roll & Tilt, FPV and FPV-V |
| Cost | A GET round trip is 20 to 40 ms on the camera network; polling at 10 Hz is cheap |

Firmware 1.1.15 plans every SET as its own start-and-stop move, so a stream of
SETs judders at the send rate (8 to 16°/s of jitter at 15 to 100 Hz) where a
constant stick value has almost none. OpenInstaCine therefore uses SET_ANGLE for
slow, planned moves (Level and Motion Control, streamed at 30 Hz) and the stick
for head tracking.

### Level, Motion Control and head tracking

| Feature | How it drives the Luna | Result |
| --- | --- | --- |
| Double-tap Level | SET_ANGLE to the GET pitch minus the camera-head IMU's gravity pitch, keeping yaw; a second pass if still more than 0.3° off | Within 0.4° of level in about 2 s |
| Motion Control A to B (to C) | Waypoints from GET_ANGLE; the session interpolates legs and streams SET_ANGLE at 30 Hz | Mean 0.6° off the A to B line; ends on the last point. Loop, pause, resume and stop verified |
| AirPods head tracking | Stick at 30 Hz, closed on GET_ANGLE: head rate and acceleration fed forward plus a pull toward the exact angle | 1.8° RMS on a 20° / 3 s sine, about 0.02 s lag. Faster than 63°/s the stick saturates |

The camera-head IMU arrives in live media subtype `0x30` (see
[Live view](../../../protocol/live-view/#media-subtypes)).

The Insta360 POV Head Tracker accessory talks to the camera directly; the phone
app never relays its attitude, and an iPhone cannot stand in for it. Absolute
angle control makes that unnecessary.

## Deep Track

| UI | Wire |
| --- | --- |
| Draw a box | cmd **237** `OPEN_TRACKING_WITH_RECT` `{1: ms, 2 x, 3 y, 4 w, 5 h}` (floats, preview fractions); reply `{}` |
| Cancel | cmd **238** `CANCEL_TRACKING`; notification **8315** `{1:4, 2:2, 3:5, 4:0}` |
| Tracking Framing button | cmd 245 `GET_PRESET_COMPOSITION` |
| Framing grid point (3 × 3) | cmd 244 `SET_PRESET_COMPOSITION` `{1: ms, 2 x, 3 y, 4 w, 5 h}`; the gimbal re-frames the subject there |

**Tracking state is in the video stream, not in notifications.** While Deep
Track runs, every video frame is followed by a media frame with subtype
**`0x85`**: protobuf `{1: ms, 2: state, 3: 0, 4: {1 x, 2 y, 3 w, 4 h}}`, floats
in top-left preview fractions. States: **5** idle, **2** tracking (the box
follows the subject), **3** lost (the box stays at the last position). Covering
the subject gave lost after about a second; the camera re-acquired on its own
after 10 s. 8315 only arrives on cancel.

The phone sends nothing per frame while tracking: the camera drives the gimbal
itself. Recording and the stick keep working during tracking.

### Gimbal wake

The gimbal sleeps pointing down until an app enters the shooting view. The
official app sends cmd **118** `{1:5}` when it enters live view (8302 field 5
goes from 1 to 0 about 50 ms later) and `{1:1}` when it leaves for the album,
which folds the gimbal down. Without the wake, the picture can look grey or black
and the stick does nothing. OpenInstaCine sends `{1:5}` before every live start.
