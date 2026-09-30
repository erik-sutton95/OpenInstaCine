# Luna Ultra timecode (fw 1.1.15)

Research date: **2026-09-30**. Sources: the official Insta360 Android app 2.34.5 (decompiled, see
[luna-head-tracker-and-gimbal-angle.md](luna-head-tracker-and-gimbal-angle.md#provenance)), our
official-app captures on fw 1.1.15, and live tests from the DEBUG remote.

## Bottom line

- The camera's timecode is **time of day from its own clock**, running whether or not it records.
  The camera menu only switches timecode on or off and shows it on the preview. Its "Sync system
  time" says to connect the app for a more accurate time: the phone app is expected to set the clock.
- **Nothing on the phone protocol carries timecode.** No option, notification, clip metadata field
  or `tmcd` track (checked across 18 decoded official sessions and a 4.3 GB album capture). The
  official app's timecode code (`trcservice`, "TRC") is for the Mic Pro wireless mic over its own
  BLE protocol; its Luna TIME_CODE switch only stores a phone preference.
- OpenInstaCine sets the camera clock at every live start and derives the timecode of each live
  frame, which matches the camera's display.

## Setting the clock (proven)

| Request | Body | Notes |
| --- | --- | --- |
| cmd 7 SET_OPTIONS, types 12, 13, 175 | `{12: unix s, 13: seconds east of GMT (int32), 175: zone name}` | What the official app sends on every connect (whole seconds, so up to 1 s behind). The reply takes about 220 ms (camera processing). |
| cmd 214 SYNCTIME_ACCURATE | `{1: {1: s, 2: ms}, 2: count}` | Official app sends it twice (count 0, then 1). Accepted with an empty reply. After it, the camera clock matched the phone to the second on its screen. |

GET of 12, 13 or 175 returns nothing: the camera's time of day cannot be read back.

## Clocks (proven)

- **Frame clock**: every live media frame header carries a u64 millisecond stamp
  (`LunaMediaPacket.timestamp`, video 40 ms apart at 25 fps). It is monotonic since boot and does
  not move when the camera time is set.
- **MEDIA_TIME** (device option 29) is milliseconds too, but it follows the camera's wall clock:
  after the camera time was changed it read 2380.5 s behind the frame clock (they agreed in the
  official captures). It therefore cannot map frames to time of day.
- Clip `ExtraMetadata` 24 `first_frame_timestamp` (µs) is on the frame clock and lands on the live
  preview's frame grid (within half a frame in three clips).

## How the app derives timecode

`CameraSession.syncCameraClock` sets 12/13/175, then sends 214 twice stamped at send time (a GET
round trip on the camera AP is about 4 ms). `noteFrameClock` pins the frame clock to the phone clock
by the earliest frame arrival minus 90 ms (best-case capture to phone delay seen in the official
captures) and formats each frame's time of day as non-drop `HH:MM:SS:FF`
(`LunaShellMapping.timecode`; frames count at the recording rate, halved above 30). The status bar
shows `HH:MM:SS`, so the readout is within a frame or two of the camera's own timecode.
