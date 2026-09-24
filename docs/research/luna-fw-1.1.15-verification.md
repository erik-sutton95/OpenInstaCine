# Luna Ultra firmware v1.1.15 hardware verification

Date: 2026-09-25 (night session, 00:56 to 02:10 CEST). Camera: Luna Ultra,
serial suffix QFN7, freshly updated from v1.0.288 to **v1.1.15**. Client: the
Mac over the camera AP (en0 192.168.42.136, camera 192.168.42.1, TCP 6666),
using our saved authorized identity. Tool: `tools/LunaProbe` (Swift,
Network.framework, depends on `Adapters/Insta360Protocol` by path).

Evidence label for everything below: **Verified on v1.1.15** means our own
client sent the package encoder's bytes and read the value back from the
camera in a separate GET (or observed the effect in live video).

Raw logs (private, not committed): `.local/fw1115/sweep.log` (every probe
run), `originals-get.txt` / `originals.json` (state before any change),
`final-get.txt` (after restore), `res-results.txt` and
`res-retest-results.txt` (resolution sweep), `record.log`, `photo.log`,
`live-*.hevc`.

## How to reproduce

```sh
cd tools/LunaProbe && swift build
.build/debug/LunaProbe info|status|get|files
.build/debug/LunaProbe set <thing> <value>   # BEFORE, TX bytes, REPLY, AFTER (polled)
.build/debug/LunaProbe live 8 out.hevc
.build/debug/LunaProbe record 3 ; .build/debug/LunaProbe photo
.build/debug/LunaProbe delete <uri>          # only URIs in .local/lunaprobe-created.txt
.build/debug/LunaProbe http <uri> 1 0-1023 out.bin
.build/debug/LunaProbe raw <code> <hexbody>
```

`set` polls the readback for up to `LUNA_WAIT` seconds (default 4) until it
differs from BEFORE, and prints the latency. `--fm N` sets the FunctionMode
field. `delete` refuses any URI that `record`/`photo` did not create.

## Headline findings

1. **Session, auth, live, record, photo, delete all still work** with the
   v1.0.288 bytes (preface, greeting, cmd 8, cmd 39, live body
   `10012080f702382b500e6001`, cmd 4 `0801`, empty cmd 5, empty cmd 3, cmd 12).
2. **FunctionMode is ignored.** GET and SET act on the bank of the *current
   shooting mode* regardless of field 2/3. Every fm returned identical values
   in video mode; in slow motion every fm returned the slow-motion bank (res
   214, program 5), and a SET with fm 21 while in video mode wrote the video
   bank.
3. **GET type 13 clobbers field 39.** The camera answers type 13 by writing
   field 39 = 0. A GET listing `[39, 13]` therefore reports WB auto even when a
   kelvin is stored; `[13, 39]` or `[39]` alone reports correctly.
4. **Manual exposure encoder bug (fixed).** With the ISO top-limit sentinel
   (type 24 = 4294964096) the camera converts program 3 to program 2, drops the
   ISO and stores 24 = 3200. Types `[21, 100]` store program 3 + ISO + shutter.
5. **Omitted zero is ignored for FOV 33 (fixed).** Explicit `33 = 0` works;
   explicit zero also works for 18, 39 and 93.
6. **Zoom max is 15.0** (was 12 in our guard). Values above 15 or below 1 are
   ignored, not clamped. Zoom ramps: a GET 0.27 s after SET 4 read 3.652.
7. **HTTP media needs an open control session.** With no TCP session,
   `GET /storage_internal/...` returns **401** (nginx 1.24.0, no
   `WWW-Authenticate`). With a session open (after cmd 118 state 1) the same
   Range request returns 206. Whether cmd 118 is strictly required was not
   isolated (a grant from an earlier 118 may persist within the camera).
8. **New notification 8334** (not in the pinned schema): same shape as 8293,
   fires for filter 18 / strength 104 changes, including those implied by a
   color change (Dolby sets strength 3). Now decoded as `.photographyChanged`.
9. **Long shutters are honoured.** Manual ISO 6400: 1/25 gives 25.9 fps
   preview, 1/15 gives 14.8 fps, 1/10 gives 10.5 fps, 1/5 gives 4.98 fps, with
   rising luma. The preview frame rate follows the shutter.
10. **Wi-Fi AP turns off when the official app's session ends.** After
    terminating the official app the AP vanished for over 2 minutes; the BLE
    bootstrap (`tools/luna_ble.py --name XBQFN7`, no `--authorize`) woke it and
    confirmed BLE still works on v1.1.15 (camera reports `v1.1.15`; new empty
    BLE notification 8215 `CAM_WIFI_START`). en0 also dropped once mid-sweep
    and rejoined immediately.

## Original state (restored at the end)

Video mode (40 = 100, 41 = 0). Video bank: sharpness 1 (reported), EV 0,
filter 0, still and video exposure program 2 / ISO 0 / 1/50, ISO limit 0,
res 48 (4K25), FOV 0, color 2 (I-Log), WB auto, photo res 29, zoom 1.0,
63 = 0, 72 = 0, gimbal (rc 2, follow 3, sens 3, mode 2 Roll Lock), AF 3,
pano type 1, IQ 3A 2, filter strength 2. Omitted: 13, 42, 43, 73.
Slow-motion bank: res 214, program 5. Media: 3 files (1 JPG, 2 MP4) plus 2
LRV. After restore, `get` for all fm matched `originals-get.txt` byte for
byte, slow-motion res is 214 again, the media list is the same 3 / 5 URIs.

One caveat: in I-Log the camera reports sharpness 1 no matter what is stored
(see below), so the Standard-mode sharpness before this session is unknown.
It was restored to 1, the value the camera reported.

## Setter results

Reply is the outer message code; every SET below replied 200 with the set
types echoed in field 1 unless stated. Readback is a separate GET.

### Photography options (cmd 9)

| Command | Sent | Readback after | Result | Notes |
| --- | --- | --- | --- | --- |
| `setSharpness` (Standard) | 0, 1, 2 | 0, 1, 2 (0.27 s) | PASS | |
| `setSharpness` (I-Log) | 0, 2 | 1, 1 | PASS* | I-Log pins the *reported* value to 1; the SET is stored and shows after switching to Standard |
| `setExposureBias` | +0.3, -0.7, +2, -2, 0 | wire 6, 13, 40, 39, (0) = +0.3, -0.7, +2.0, -2.0, 0 | PASS | sint32 zigzag of tenths confirmed for negatives |
| `setColorMode` | Standard 1 | 1 | PASS | reply took 1.19 s (pipeline switch) |
| `setColorMode` | I-Log 2 | 2 | PASS | |
| `setColorMode` | Dolby 5 | 5 | PASS | worked in shutter priority 1/50; 8334 sets strength 3 |
| `setColorMode` | Vivid 3 | 1 | FAIL (camera) | 200 but stored as Standard |
| `setColorMode` | HDR 4 | unchanged | FAIL (camera) | 200, ignored |
| `setWhiteBalanceKelvin` | 2000, 2500, 3200, 4000, 5600, 6500, 8000, 10000 | same values | PASS | applies after **3.5 to 3.9 s**; readback must not list 13 after 39 |
| `setWhiteBalanceAuto` | auto | 0 | PASS | 3.8 s |
| `setPhotographyValue(.whiteBalance, 1)` | 13 = 1 | (GET 13 returns 39 = 0) | n/a | preset field has no readable effect |
| `setVideoExposure(.automatic)` | program 0 | program 0, ISO 0, shutter 0 | PASS | |
| `setVideoExposure(.isoPriority)` | 100, 160, 400, 800, 1600, 3200, 6400 | same | PASS | 50 and 12800 also stored verbatim: storage does not validate range |
| `setVideoExposure(.shutterPriority)` | 1/5, 1/10, 1/15, 1/25, 1/30, 1/50, 1/100, 1/250, 1/1000, 1/4000, 1/8000 | same doubles | PASS | also 1/2, 1 s, 1/16000 stored verbatim; 24 reads 3200 |
| `setVideoExposure(.manual, shutter)` | program 3, no ISO, sentinel 24 | program 2 | PASS (as official) | camera maps manual + auto ISO to program 2 |
| `setManualExposure` (old encoder) | 3 / 400 / 1/50 + sentinel 24 | program 2, ISO 0 | **FAIL, fixed** | |
| `setManualExposure` (fixed) | 3 / 800 / 1/60, 3 / 200 / 1/25, 3 / 6400 / 1/5 | same | PASS | types [21, 100] |
| `setPhotographyValue(.videoISOTopLimit)` | 6400, 0 | 6400, 0 | PASS | |
| `setZoomScale` | 1.5, 2, 4, 8, 12, 1 | same (4 read 3.652 mid-ramp) | PASS | |
| raw zoom | 12.5, 15 | 12.5, 15 | PASS | new max 15 |
| raw zoom | 20, 15.5, 0.5 | previous value kept | ignored | not clamped |
| `setRecordResolution` | see resolution list | 8293 within 0.04 s | PASS | rejected values: 200, no 8293, value unchanged |
| `setGimbalMode` | 1, 3, 4, 5, 2 | same | PASS | 5 (`lock`) stores |
| `setGimbalMode` | 6 | unchanged | FAIL (camera) | not supported |
| `setGimbalFollowSpeed` | 1, 2, 4, 3 | same | PASS | 4 (`sensitive`) stores |
| `setTapFocus` | (0.5, 0.5) | AF mode 3 unchanged | PASS (action) | 200; no stored state |
| `setPhotographyValue(.gammaMode)` (filter) | 1, 0 | 1, 0 | PASS | 8334 fires |
| `setPhotographyValue(.gammaModeLevel)` | 3, 2 | 3, 2 | PASS | 8334 fires |
| `setPhotographyValue(.fovType)` | 1, then 0 omitted | 1, **1** | **FAIL, fixed** | explicit 0 stores 0 |
| `setPhotographyValue(.afMode)` | 1, 3 | 1, 3 | PASS | explicit 0 also stores |
| `setPhotographyValue(.flowStateLevel)` | 1 | omitted | no effect | field never reported |
| `setPhotographyValue(.darkEIS)` | 1 | omitted | no effect | cmd 157 still 1 |
| `setPhotographyValue(.iLogSwitch)` | 1 | false | no effect | |
| `setColorRecoveryFlag` | 1, 0 | 73 omitted | no effect | same as v1.0.288 |

### Device options, gimbal, tracking

| Command | Sent | Reply | Readback / effect | Result |
| --- | --- | --- | --- | --- |
| `LunaShootingMode.timelapse` | 41 = 2 | 200 | 8275 (100, 2, sensor 3), mode reads timelapse | PASS |
| `.timeShift` | 41 = 4 | 200 | 8275 (100, 4, 3) | PASS |
| `.slowMotion` | 41 = 9 | 200 | 8275 (100, 9, 3), 8234 1280x720@29 | PASS |
| `.pureVideo` | 41 = 11 | 200 | 8275 (100, 11, 3) | PASS |
| `.photo` | 40 = 0 | 200 | 8275 (0, 100, 3) | PASS |
| `.pano` | 40 = 8 | 200 | 8275 (8, 100, sensor 1) | PASS |
| `.video` | 41 omitted | 200 | 8275 (100, 0, 3) | PASS |
| `gimbalMove` | (40, 0), (0, -40), 0.5 s each, then release | 200, 200 | | PASS |
| `gimbalStick` | pan 0.3 | 200 | | PASS |
| `gimbalRecenterRequest` / `gimbalFlipRequest` | | 200 | | PASS |
| `openTracking` | (0.4, 0.35, 0.2, 0.3) | 200 | | PASS |
| `cancelTrackingRequest` | | 200 | | PASS |

Mode banks: see finding 2. `LunaShootingMode.functionMode` is harmless but no
longer selects anything on v1.1.15.

## Accepted RecordResolution values in video mode

58 values stored (8293 fired). This is the format menu for normal video:

| Geometry | Accepted fps (enum) |
| --- | --- |
| 7680x4320 (8K) | 24 (210), 25 (211), 30 (154) |
| 7680x3268 (8K 2.35:1) | 24 (219), 25 (212), 30 (213) |
| 3840x2160 (4K) | 24 (49), 25 (48), 30 (24), 48 (258), 50 (92), 60 (23), 100 (220), 120 (214) |
| 3840x1632 (4K 2.35:1) | 24 (440), 25 (439), 30 (438), 48 (437), 50 (436), 60 (435), 100 (434), 120 (433) |
| 2688x1520 (2.7K) | 24 (248), 25 (247), 30 (246), 48 (331), 50 (245), 60 (244), 100 (243), 120 (242) |
| 1920x1080 | 24 (53), 25 (52), 30 (29), 48 (260), 50 (81), 60 (40), 100 (150), 120 (28), 200 (26), 240 (27) |
| 2160x3840 (9:16 4K) | 24 (126), 25 (125), 30 (124) |
| 1728x3072 (9:16 3K) | 24 (455), 25 (454), 30 (453), 48 (452), 50 (451), 60 (450) |
| 1520x2688 (9:16 2.7K) | 24 (445), 48 (468), 50 (442), 60 (441) |
| 1080x1920 (9:16) | 24 (85), 25 (71), 30 (64), 48 (298), 50 (82), 60 (68) |

Method: 289 schema candidates (16:9, 9:16, 4:3, 3:4, 2.35:1, long side at
least 1920). The fast sweep falsely rejected 71, 85, 125 and 454 (the camera
drops a change that arrives while it is still reconfiguring); a second pass
with 2 s settle re-tested every reject sharing an accepted geometry. Still
rejected: 1080x1920 100/120/200/240, 2160x3840 48/50/60/100/120/180, 4K 15 and
180, 1620x2880 all, 1520x2688 100/120. No 4:3, 3:4, 2.7K 16:9 (2720x1530),
5.3K, 6K or 8K 4:3 value was accepted. Whether the high-rate values (100 to
240) record at that rate in *normal* video mode was not tested; slow motion
has its own bank (default 214).

## Capture, media

| Step | Sent | Reply | Observed | Result |
| --- | --- | --- | --- | --- |
| Record start | cmd 4 `0801` | 200 empty, after 1.05 s | 8208 state 1 at +0.25 s | PASS |
| Capture status while recording | cmd 15 | 200 | state 1, `capture_time` 0, 1, 2 (seconds) | PASS |
| Record stop | cmd 5 empty | 200 **empty** | 8208 state 0 after 1.9 s | PASS; no URI in reply (`stoppedVideo` returns nil) |
| New clip in list | cmd 38 / cmd 13 | 200 | `VID_20260925_013429_004.mp4` 3840x2160 25 fps, 3.24 s, 12.1 MB, H.265, plus `LRV_...lrv` | PASS (found by list diff) |
| Thumbnail | cmd 11 type 2 | 200, 1382440 bytes | header `01 00 00 00 28 18 15 00 01 ...` 1280x720 NV12 | PASS (PNG rendered; frame dark) |
| Metadata | cmd 11 type 1 | 200 | same fields as cmd 38 | PASS |
| LRV header | HTTP Range 0-1023 | 401 without session; 206 with session | `ftypmp42`, total 10298847 bytes | PASS with session |
| Delete clip | cmd 12 MP4 URI | 200 | MP4 and its LRV both gone (5 URIs again) | PASS |
| Photo (photo mode) | cmd 3 empty | 200 empty after 3.3 s | 8208 state 4, then 0; `IMG_20260925_013542_004.jpg` 3520x2644 | PASS (no ExtraMetadata needed) |
| Photo thumbnail | cmd 11 type 2 | 200 | 1024x768 NV12 | PASS (rendered correctly) |
| Delete photo | cmd 12 | 200 | gone | PASS |

Only these two probe-created items were deleted. No format, Wi-Fi, network or
firmware command was sent.

## Battery, storage, remaining time

| Quantity | Source on v1.1.15 | Units / notes |
| --- | --- | --- |
| Camera battery % | cmd 8 option **11** field 2 | percent; read 100. Option 11 now also carries field 4 = 0 (unknown) |
| Camera charging | option 11 field 1 (`powerType`) | 1 while on power at 100 %. No unplug test was possible tonight, so "0 = on battery" remains unverified |
| Screen battery | option 180 fields 1/2, connection field 3; notification **8308** | 8308 fired during recording with powerType 1 to 0 at 100 % (likely charge-complete or unplug; not isolated) |
| Battery notification 8195 / 8196 | not seen | still poll option 11 |
| Storage free/total (active) | option **20** fields 2/3 | bytes: 49903960064 free of 50490900480 |
| Storage per location | option **176** (repeated), 177 = active location | inner (2): PASS 0; SD (3): **state 2 NOSPACE**, 163176448 free of 268161024 bytes (a small card is inserted) |
| Storage change notification | 8198 (state, location, kind) | no byte counts; re-poll 20/176 |
| Remaining record time | photography option **99**, repeated (seconds, location) | seconds: inner 4630 s (77 min at 4K25, implies about 86 Mbit/s budget); SD 0 |
| Capture elapsed | cmd 15 field 1.2 | seconds (8208 notification still says 0) |

## Live preview facts

| Item | Standard | I-Log |
| --- | --- | --- |
| Start live body | unchanged, reply 200 in 0.036 s | same |
| 8234 | 1280x720, 25 fps, H.265, flowStateBase true | same |
| First video packet / first keyframe | 0.395 s after TX | 0.392 s |
| Measured rate | 25.2 fps wall, tick delta 40 | 25.3 fps |
| Keyframe interval | IDR_W_RADL every 50 frames (2 s); VPS/SPS/PPS before each | same |
| SPS/VUI (ffprobe) | HEVC Main, yuv420p, tv range, BT.709 primaries/matrix/**transfer** | **identical tags** (log picture is tagged BT.709) |
| Luma (dark scene) | YAVG 18.9, Y 8 to 253, SATAVG 0.5 | YAVG 37.0, Y 34 to 43, SATAVG 0.0 |
| Media subtypes | 0x20 video 193, 0x40 193, 0x30 77 per 8 s | |

The room was nearly dark, so only the black pedestal is a reliable
comparison: I-Log preview black sits near Y 37 versus about 16 to 19 in
Standard, i.e. the preview carries the log curve (no recovery LUT) while the
VUI still says BT.709. Slow motion mode changed 8234 to 1280x720@29.

Long shutter (manual ISO 6400, Standard): preview fps 25.9 / 14.8 / 10.5 /
4.98 at 1/25 / 1/15 / 1/10 / 1/5; YAVG 19.6 at 1/25 versus 24.0 at 1/5.

## Official app on v1.1.15 (task 5): blocked

Two RVI captures (`.local/official-fw1115-startup.pcap`, 60 s, host filter;
`.local/official-fw1115-startup-2.pcap`, 90 s, subnet filter) after launching
Insta360 via `devicectl`. Neither contains any TCP to the camera: the first has
only camera ARP for a stale 192.168.42.253, the second nothing on
192.168.42.0/24. The app evidently needs a UI tap (or its BLE flow) to join and
connect, and UI automation was unavailable. No v1.1.15 official-app request
diff exists yet; the changes listed above come from our own client. The app
was left terminated.

## Package changes made from this session

All in `Adapters/Insta360Protocol`, each with a regression test in
`LunaControlTests.swift` (`swift test`: 40 XCTest cases, 0 failures):

1. `setVideoExposure(program: .manual, iso: > 0)` / `setManualExposure` now
   send types `[21, 100]` without the ISO top-limit sentinel.
2. `setPhotographyValue` encodes zero explicitly; `setWhiteBalanceAuto` keeps
   the official omitted shape.
3. `setZoomScale` accepts up to `maximumZoomScale` = 15.
4. `LunaNotification` decodes 8334 as `.photographyChanged`.
5. Doc comments: GET 13 quirk, `capture_time` is seconds.

## Open items

- Official-app v1.1.15 traffic (needs a person or UI automation to tap Connect).
- Charging flag semantics (needs an unplug/replug while polling option 11).
- Whether HTTP needs cmd 118 or only a live session (needs a camera reboot to
  clear any grant, then a session without 118).
- 8302 now fires periodically with `sleep = true` while GET 92 reports all
  false; meaning unknown.
- The recorded clip thumbnail was black while the photo was not; the scene
  was dark and the video bank still had a manual ISO 200 1/25 test exposure.
