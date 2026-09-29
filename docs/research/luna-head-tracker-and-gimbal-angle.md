# Luna Ultra: POV Head Tracker link and absolute gimbal angle

Research date: **2026-09-29**. Source: static analysis of the official Insta360 Android app. No camera, phone or tracker was touched. Every claim below is labelled:

| Label | Meaning |
| --- | --- |
| **Proven (app)** | Read directly from decompiled app code or generated protobuf classes. |
| **Inferred** | Follows from app evidence, but no hardware has confirmed it. |
| **Unknown** | The app does not contain the answer. |

## Bottom line

1. **The iPhone does not need to emulate the head tracker.** The app's protobuf schema has an absolute-angle gimbal command: `PHONE_COMMAND_GIMBAL_CONTROL` (226) with `gimbal_action = GIMBAL_ACTION_SET_ANGLE (5)` and a new field `angle = 5` holding `{roll = 1, pitch = 2, yaw = 3}` as `float`. `GIMBAL_ACTION_GET_ANGLE (6)` has a matching `GimbalControlResp {int32 grf = 1; float roll = 2; float pitch = 3; float yaw = 4}`. **Proven (app)** at the schema level. The app itself never sends SET_ANGLE or GET_ANGLE, so Luna firmware support, units and reference frame remain **Unknown** until a live test.
2. **Emulating the tracker from an iPhone is not practical, and the app cannot show us how to do it.** The POV Head Tracker is `RemoteType.INSTA360_TM2`. It is a Bestechnic BES1502P audio-class SoC (OTA file `best1502p_ibrt_master.bin`), and the app finds it over **BR/EDR Classic** as well as BLE. The protocol between tracker and camera lives only in the camera and tracker firmware. The app never relays attitude data. iOS cannot present itself as a Classic Bluetooth device, and it cannot set an arbitrary BLE name, MAC address or manufacturer data. **Proven (app)** for the SoC, the dual-mode scan and the missing relay. The camera-side protocol is **Unknown**.

## Provenance

| Item | Value |
| --- | --- |
| Package | `com.arashivision.insta360akiko`, versionName **2.34.5**, versionCode 526204, minSdk 28, targetSdk 35 |
| Source | APKCombo mirror of the Play build (APKMirror's download page was behind a Cloudflare challenge) |
| APK SHA-256 | `950a259aa7fc4b552b2d2ea055ac0e20e9b00246765cfd5eaac8fe108111ff99` |
| Signer | `CN=arashivision`, cert SHA-256 `6d7afbcba2144f53faa119fd8f8f59d9ab016739f4fbddc7f632b579db32e357` (verified with `apksigner`) |
| Luna support | The app contains the Luna capture UI (`GimbalViewAngle*`, `VIDEO_GIMBAL`), and Insta360 requires 2.26.2 or later for Luna. |
| Local artifacts | `.local/insta360-app/` (gitignored): APK, `unpacked/dex01..18.dex`, `jadx/` and `jadx-consts/` sources, `insta360-2.34.5-messages.proto` (rebuilt schema), `messagecode-diff.txt`, `new-top-level-types.txt`, `tools/wire2proto.py` |

### Unpacking method (needed to reproduce)

The APK is packed by a commercial shell. `classes.dex` is a 6 KB stub (`com.ashield.Stub`, config `jiaguVersion 1.5.1.3`) followed by an encrypted 139 MB payload, so jadx on the APK recovers one class. To get real code, the APK was installed on a throwaway AOSP arm64 emulator (API 35, `adb root`) and launched to the splash screen. The unnamed anonymous mappings of the process were then read through `/proc/<pid>/mem`. A 177 MB rwx region held 16 concatenated plain dex files, and two smaller regions held one each: 18 files in total, with valid headers. The emulator AVD was deleted afterwards. The protobuf classes are Square Wire classes in `unpacked/dex18.dex`. `tools/wire2proto.py` rebuilds a `.proto` from their `@WireField(tag = …)` annotations and enum constructors. Decompile with `--no-replace-consts`, because otherwise jadx replaces enum numbers with unrelated constant names.

## 1. Absolute gimbal angle command (the recommended path)

### Schema: Proven (app)

From `jadx/sources/insta360/messages/GimbalControl.java`, `GimbalControlResp.java` and `GimbalAction.java`:

```proto
enum GimbalAction {
  GIMBAL_ACTION_UNKNOWN = 0;
  GIMBAL_ACTION_MOVE = 1;
  GIMBAL_ACTION_BACK_CENTER = 2;
  GIMBAL_ACTION_FLIP = 3;
  GIMBAL_ACTION_CALI = 4;
  GIMBAL_ACTION_SET_ANGLE = 5;   // new vs our schema
  GIMBAL_ACTION_GET_ANGLE = 6;   // new vs our schema
}
message GimbalControl {           // cmd 226
  GimbalAction gimbal_action = 1;
  VirtualRC virtual_rc = 2;       // sint32 up_down = 1; sint32 left_right = 2;
  GimbalCaliType gimbal_cali_type = 3;
  sint32 cali_id = 4;
  Angle angle = 5;                // new vs our schema
  message Angle { float roll = 1; float pitch = 2; float yaw = 3; }
}
message GimbalControlResp {       // new type
  int32 grf = 1;
  float roll = 2;
  float pitch = 3;
  float yaw = 4;
}
```

All fields are proto3 `OMIT_IDENTITY`, so zeros are not sent on the wire. Example body for SET_ANGLE with pitch 10.0 and yaw 30.0 (roll 0 omitted), checked by hand encoding:

```
08 05  2a 0a  15 00 00 20 41  1d 00 00 f0 41
```

GET_ANGLE body: `08 06`.

### What the app does with it: Proven (app)

- `com/arashivision/inskmp/device/plugin/camera/op/SetGimbalControlOpHandler.java` sends `GimbalControl.encode()` as cmd 226 (content type protobuf), and its `parseResponse` **ignores the payload**.
- A search of all 98k decompiled classes finds `GIMBAL_ACTION_SET_ANGLE`, `GIMBAL_ACTION_GET_ANGLE`, `GimbalControl.Angle` and `GimbalControlResp` **only** in the generated protobuf package. `BaseCameraController` uses only MOVE, BACK_CENTER, FLIP and CALI. The shipping app never positions the gimbal by angle.

### Open questions (all Unknown until a live test)

| Question | Best guess | Confidence |
| --- | --- | --- |
| Does Luna firmware 1.1.x act on SET_ANGLE? | The schema is shared across products and may have been added for another gimbal product (the same schema has flight-controller `FC_GIMBAL_CONTROL_INTENT` 20070 and `FC_SET_GIMBAL_PITCH_CONFIG` 20068 for a drone). It could also be a Luna feature that has not shipped yet. | Low |
| Units | Degrees, which is typical for Insta360 gimbal and `RENDER_VLP_EULER` floats. | Low |
| Frame | Probably handle or base relative, with 0/0/0 at BACK_CENTER. | Low |
| Does the cmd 226 response carry `GimbalControlResp` for GET_ANGLE? | Likely, given the name and field set. | Medium |
| `grf` meaning | Possibly a result or reference-frame flag. | Low |

### Suggested live test (for a later session, not run)

1. Send GET_ANGLE (`08 06`) while idle, and log the full response body for cmd 226. A decodable `GimbalControlResp` means the firmware knows the action.
2. Send SET_ANGLE with a small yaw only (for example `08 05 2a 05 1d 00 00 a0 40` for yaw 5.0), with the camera in a follow or lock gimbal mode. Watch the preview and the camera-head IMU loop we already have.
3. Try both degrees and radians only if 5.0 does nothing visible. Try sign and axis swaps next.
4. If the firmware rejects it (error status or no motion), keep the existing closed-loop MOVE stick controller. It already uses the camera-head IMU and is the proven fallback.

## 2. POV Head Tracker (CINSFAVL-01)

### Identity: Proven (app)

`com/arashivision/insta360akiko/setting/bleRemoteControl/RemoteType.java`:

```java
INSTA360_TM2("Insta360 POV Head Tracker", "insta360_mic_tm_firmware_tone"),
```

- The internal name is **TM2**. The API key names it a "mic TM" product with prompt tones. The protobuf calls it a "TM tracker ear hook" (`kTmTrackerEarHookWearUnknown / kTmTrackerEarHookNotWorn / kTmTrackerEarHookWorn`; the numeric values are presumably 0/1/2 but were not proven).
- The phone-side firmware updater is `TmPromptToneRemoteDelegate`. Its constants include OTA file `best1502p_ibrt_master.bin`, prompt tone files `prompt_tone_v*`, prompt tones supported from tracker firmware `1.1.2.5`, and up to 3 reconnects. **BES1502P** is a Bestechnic Bluetooth audio SoC ("ibrt" is BES's TWS earbud stack). **Inferred:** the tracker is built like an earbud with an IMU, speaking both Classic and LE.
- `v2/scan/scanResultFilter/TmBrDeviceScanFilter.java` drops **BR/EDR** scan results named "Insta360 POV Head Tracker", "Insta360 Flash" or "Insta360 Smart Remote". The tracker therefore appears over Classic too, and the app uses only its LE side.

### Phone-to-tracker GATT (for OTA and prompt tones only): Proven (app)

`bleRemoteControl/core/UUIDsKt.java`, used by `TmPromptToneRemoteDelegate` (and `TmBleRemoteDelegate` for Flash and Smart Remote):

| Role | UUID |
| --- | --- |
| Service | `0000ce80-0000-1000-8000-00805f9b34fb` |
| Write (phone to tracker) | `0000ce81-0000-1000-8000-00805f9b34fb`; write type toggles between no-response (1) and default (2) |
| Notify (tracker to phone) | `0000ce82-0000-1000-8000-00805f9b34fb` |

This follows the same CEx0/1/2 pattern as the camera's BE80/BE81/BE82. The app uses it only for `enterOta`, firmware and prompt-tone transfer. **No attitude, quaternion or head-angle parsing exists on the phone side.**

### Camera-side protocol and pairing

| Item | Status |
| --- | --- |
| Tracker-to-camera transport | **Unknown.** Candidates are BR/EDR (the tracker advertises Classic, and the camera lists BR/EDR in its specs), BLE, or the optional receiver module in the bottom port. Nothing in the app names the receiver module. |
| GATT/SDP profile the camera expects | **Unknown.** It is not in the app. |
| Attitude message format and rate | **Unknown.** It is not in the app. Clip metadata hints at the payload: `ExtraMetadata` has `mag_calib_tm = 167` (`MagCalib {repeated float bias, scale, cross}`), `q_i_mag_tm = 169`, `q_b_tm = 170` (`MagQI {repeated float q_i_mag}`), and the extra-data types `EXTRA_TYPE_TM_DATA = 36` and `EXTRA_TYPE_TM01_DATA = 58`. **Inferred:** the tracker supplies a magnetometer-corrected orientation quaternion with a mag calibration, which the camera records. |
| Calibration handshake | **Unknown**, apart from the mag-calibration metadata above. |
| Pairing | Done on the camera's Bluetooth accessories menu. The phone-side commands 26 to 29 (`SCAN_BT_PERIPHERAL`, `CONNECT_TO_BT_PERIPHERAL`, `DISCONNECT_BT_PERIPHERAL`, `GET_CONNECTED_BT_PERIPHERALS`) take `BTPeripheral {string name = 1; bytes mac_addr = 2}`, and `BTPeripheralType` has only `ALL = 0` and `REMOTE_CONTROLLER = 1`. **Proven (app)** schema. Whether they reach the tracker class is **Unknown.** |
| Tracker state visible to the phone | `OptionType TM_TRACKER_EAR_HOOK_WEAR_STATE = 196` (`Options.tm_tracker_ear_hook_wear_state = 196`), notification `CAMERA_NOTIFICATION_TM_TRACKER_EAR_HOOK_WEAR_STATE = 8321`, and robot key codes `ROBOT_KEY_CODE_TM_TRACKER_POWER/FUNCTION/TAP = 21/22/23` through `CAMERA_NOTIFICATION_ROBOT_CONTROL = 8340` (`RobotControlNotify {RobotKeyCode key_code = 1; RobotKeyValue key_value = 2}`). **Proven (app)** schema. Buttons and wear state reach the phone, but head angles do not. |

### Why iPhone emulation is not a good path (Inferred)

- CoreBluetooth peripheral mode can advertise only a local name and service UUIDs. It cannot set manufacturer data or a MAC address, and it cannot act as a Classic device. If the camera pairs over Classic, or checks a BES-style address or manufacturer ID, an iPhone cannot pass.
- Even over LE, the camera-side GATT layout, framing, authentication and attitude encoding would have to come from the tracker firmware (`best1502p_ibrt_master.bin`, fetched by the app from Insta360's accessory update service under API key `insta360_mic_tm_firmware_tone`) or from an air capture of a real tracker. The firmware was not downloaded or reversed here.

## 3. Other orientation-related fields (lower value)

| Field | Evidence | Relevance |
| --- | --- | --- |
| `PhotographyOptions.RENDER_VLP_EULER = 74` `{uint64 timestamp = 1; float yaw = 2; float pitch = 3; float roll = 4}` and `RENDER_VLP_QUAT = 84` `{float quat_x..quat_w = 1..4}` | `CaptureActivity.sendRenderVlpQuat()` sends the player's still quaternion with `funcMode = SubMode.VIDEO_GIMBAL`. **Proven (app).** | This is the view direction of the 360 cameras' virtual gimbal, not a motor command. It is unlikely to move Luna's physical gimbal. Low. |
| `PHONE_COMMAND_SET_ROBOT_MODE = 273` `{RobotModeAction action = 1; RobotId robot_id = 2}`, `RobotId ROBOT_ID_AGIBOT = 1` | Schema only. | A robot-mount integration that forwards buttons. It carries no angles. |
| `GimbalOptions.GimbalMode` `GIMBAL_MODE_LOCK = 5`, `GIMBAL_MODE_STAB_VERT = 6` (already in our schema) | Schema. | Useful for holding a pose after SET_ANGLE. |
| `CAMERA_NOTIFICATION_GYRO_CALIB_RESULT = 8336`, `CAMERA_NOTIFICATION_POSTURE_REBUILD_STATE = 8332` | Schema. | Calibration and state only. |

## 4. `MessageCode` diff: app 2.34.5 against `.local/insta360_messages.proto`

557 codes in the app, 447 in ours. No existing number changed meaning, except that 247 was renamed from `NOTIFY_BEAUTY_SETTING_PAGE` to `NOTIFY_PHOTO_SETTING_PAGE`. **Cmd 265, which the official app sends at connect, is `PHONE_COMMAND_GET_EXCEPTION_LOG_REPORT`** (request `GetExceptionLogReport`, response `GetExceptionLogReportResp`, ack via 266). The full list is in `.local/insta360-app/messagecode-diff.txt`.

New phone commands (248 to 275):

| # | Name | # | Name |
| --- | --- | --- | --- |
| 248 | REQUEST_WAKEUP | 262 | GET_TRANSLATE_CONFIG |
| 249 | RELEASE_WAKEUP | 263 | SET_USER_REGION |
| 250 | SWITCH_LIVE_STREAM | 264 | SET_ASSISTANT_LANGUAGE |
| 251 | SET_AUDIO_STREAM | 265 | GET_EXCEPTION_LOG_REPORT |
| 252 | REQUEST_DATA | 266 | EXCEPTION_LOG_PULL_ACK |
| 253 | DATA_TRANSPORT | 267 | NOTIFY_IDLE_ANALYSIS_BRIEF_PULL_STATE |
| 254 | SEND_STREAM_DATA | 268 | GET_BLUETOOTH_BIND_INFO (`GetBluetoothBindInfo {FeatureType feature_type = 1}` returns `CameraBluetoothBindInfo {feature_type = 1; PhoneInfo.PhoneType device_type = 2; string uuid = 3}`) |
| 255 | DATA_TRANSPORT_FEEDBACK | 269 | WT_KICK_WIFI |
| 256 | AIRETOUCH_RESPONSE_TEMPLATE_LIST | 270 | TRANSLATE_MODEL_SWITCH_RESULT |
| 257 | AIRETOUCH_RESPONSE_GENERATE_TASK | 271 | AI_ASSISTANT_APP_INFO |
| 258 | AIRETOUCH_RESPONSE_PERFORM_TASK | 272 | AI_VOICE_FEATURE_REPORT |
| 259 | AIRETOUCH_AI_TEMPLATE_THUMBNAIL_INFO_PUSH | 273 | SET_ROBOT_MODE |
| 260 | AIRETOUCH_PUSH_LOGIN_STATUS | 274 | GET_TRANSLATE_INTERACTION_MODE |
| 261 | AI_INTENT | 275 | AI_ASSISTANT_PERMISSION_REPORT |

All names carry the `PHONE_COMMAND_` prefix. Request and response message types were matched by name only where the table says so. The rest can be looked up in `insta360-2.34.5-messages.proto`.

New camera notifications: 8193 FIRMWARE_UPGRADE_COMPLETE, 8197 SHUTDOWN, 8200 KEY_PRESSED, 8300 CLOSE_WIFI, 8303 GIMBAL_CALIBRATION (`NotificationGimbalCalibration`), 8304 SINGLE_HOST_INFO, 8306 FOCUS_STATE, 8320 CAM_MODULE_READY, 8321 TM_TRACKER_EAR_HOOK_WEAR_STATE, 8322 DATA_INFO_READY, 8323 AUDIO_ACTIVITY_STATUS, 8324 DATA_TRANSPORT, 8325 DATA_TRANSPORT_FEEDBACK, 8326 to 8328 AIRETOUCH_*, 8329 LOGIN_REQUEST, 8330 AI_QUIT_ASSISTANT, 8331 TRANSLATE_CONFIG, 8332 POSTURE_REBUILD_STATE, 8333 LENS_ACCESSORIES_INFO_UPDATE, 8334 PHOTOGRAPHY_OPTIONS_CHANGE, 8335 AUTO_SWITCH_NIGHT_VIDEO, 8336 GYRO_CALIB_RESULT, 8337 FLASH_LIGHT_STATUS, 8338 AI_WAKEUP_ASSISTANT, 8339 TRANSLATE_MODE_CHANGE, 8340 ROBOT_CONTROL, 8341 LENS_ACCESSORY_CHANGED, 8342 TRANSLATE_MODE_SWITCH_TYPE. The remaining additions are factory (12290 to 12368) and drone flight-controller (20003 to 21328) codes.

The app defines 83 top-level types that our schema lacks. They are listed in `.local/insta360-app/new-top-level-types.txt`. `GimbalControl` gains field 5 as a nested change.

## Recommended path to exact gimbal positioning from the iPhone

1. Add `GIMBAL_ACTION_SET_ANGLE = 5`, `GIMBAL_ACTION_GET_ANGLE = 6`, the `Angle` sub-message (field 5) and `GimbalControlResp` to `LunaGimbalAction` and `LunaProtocol.gimbalControl(...)` (`Adapters/Insta360Protocol/Sources/Insta360Protocol/LunaProtocol.swift`) and to the Android `LunaControl.kt`.
2. Probe the firmware with GET_ANGLE, then with a small SET_ANGLE step, as described in section 1. Record the response status and body.
3. If SET_ANGLE works: drive head tracking (AirPods or phone attitude) as absolute yaw and pitch targets at a modest rate (10 to 20 Hz), and check the result against GET_ANGLE and the camera-head IMU.
4. If it does not work: keep the current closed-loop MOVE controller. Only then consider capturing a real POV Head Tracker session over the air, together with its firmware, to learn the tracker-to-camera protocol. Emulating it from iOS would still be blocked if that link is Classic Bluetooth.
