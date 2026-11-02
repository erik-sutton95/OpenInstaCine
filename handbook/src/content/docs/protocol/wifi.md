---
title: Camera Wi-Fi
description: Read the camera network's credentials over BLE, join it, and keep it awake.
---

After [BLE pairing](../ble/), the phone joins the camera's own network. Control,
live view and media then use that LAN.

## Credentials over BLE

Ask the camera for its own network with an **encrypted** GetOptions (cmd 8) for
option types `[36, 37, 43]`. Authenticate and decrypt the reply, then read
Options field 36: field 1 is the SSID, field 2 the password. **Do not synthesize
the password**: read it.

:::caution[Never commit the password]
Pairing logs, Keychain exports and packet captures can contain the camera Wi-Fi
password. Keep them under gitignored `captures/` or `.local/`. Do not open issues
with Wi-Fi passwords.
:::

## Join the AP

The phone joins the camera network (WPA2).

| | |
| --- | --- |
| Camera | `192.168.42.1` |
| Phone | `192.168.42.x` |
| Control and live view | TCP `192.168.42.1:6666` ([UCD2 transport](../ucd2-transport/)) |
| Files | HTTP `192.168.42.1:80` ([Media](../media/)) |

On iOS the join is `NEHotspotConfiguration` (Hotspot Configuration
entitlement); see [iOS notes](../ios/). On Android it is `requestNetwork` with a
`WifiNetworkSpecifier`, and the backend binds the process to the camera network
so the shared HTTP client reaches the camera.

### When the join fails

A successful `NEHotspotConfiguration.apply` means the configuration was applied,
not that the phone associated. Both apps treat "the phone has a `192.168.42.x`
address" as the join, not the API result.

- **iOS** retries for up to two minutes, alternating a persistent and a
  join-once configuration and dropping the stale one between attempts. After the
  third attempt it tells the operator to join the camera network in Settings and
  continues on its own once the subnet appears. A tap on the system **Join Wi-Fi
  Network** alert after the 35 s timeout still counts.
- **Android** retries in 35-second attempts for up to two minutes after the
  Bluetooth handoff, alternating a plain and a hidden-SSID specifier, and adopts
  any Wi-Fi network already on the camera subnet.

## Wi-Fi lifetime

The camera turns its Wi-Fi off when the last app session ends: after the
official app was terminated, the network stayed gone for over two minutes. A
Bluetooth bootstrap wakes it (firmware 1.1.15 sends an empty BLE notification
8215 `CAM_WIFI_START`). So both apps connect over **Bluetooth first** whenever
the camera advertises, and use the saved Wi-Fi details only as the fallback
(Android tries them for 20 s before falling back to Bluetooth).

The Apple adapter compares the serial read over Bluetooth with the one read over
TCP, so a different Luna at the same `192.168.42.1` is not mistaken for the
paired camera.

Once associated, open the [UCD2 control session](../ucd2-transport/).

## Station mode (Wi-Fi and hotspot setups)

The camera can leave its own network and join a router or a phone hotspot. All
requests go over the encrypted Bluetooth session, after the credential read:

| Step | Message | Body |
| --- | --- | --- |
| 1 | `SET_WIFI_MODE` 147 | `place_holder = 1`, `wifi_mode = 1` (station), `country_code` from option 37 |
| 2 | `PHONE_INFO` 220 | phone type, maker, model, OS version |
| 3 | `SET_WIFI_CONNECTION_INFO` 112 | `WifiConnectionInfo { ssid = 1, password = 3 }`; a reply of 505 means the camera is still switching roles: wait for notification 8215, then send it again |
| 4 | notification 8232 | `CameraWifiConnectionResult`: result 0 is success, 1 timeout, 2 connect failed, 3 a wrong password, 4 no address, 6 not found; it echoes the network name and password it tried |
| 5 | `SET_AVAILABLE_WIFI` 215 | the same `WifiConnectionInfo` |

`SET_WIFI_MODE` with mode 0 (left out, proto3 default) returns the camera to its
own network. On firmware 1.1.15 the 8232 result names the network but no
address, so the phone searches its own subnet for TCP 6666 answering the UCD2
magic, then checks the serial. On that address control and HTTP media work as on
the camera network, but the live preview is **H.264**, not HEVC.

| Observation | Firmware | Evidence |
| --- | --- | --- |
| Router join in about 5 s; control, live preview and HTTP on the router address | 1.1.15 | Verified with the lab tools (2026-10-01) |
| Live preview on the router address is H.264 High 1280x720 with the camera-network start body | 1.1.15 | Verified (NAL types 7, 8, 5, 1, 9) |
| The camera network is gone while the camera is in station role | 1.1.15 | Observed |
| Phone hotspot as the network | | Untested |
| The camera can answer 112 with 505 (`WIFI_BUSY_SWITCHING`) right after a role switch; the official app waits for 8215 (`CAM_WIFI_START`, up to 38 s) and sends the join again | 1.1.15 app | Official app's provisioning flow; the app does the same |
| An earlier join's 8232 can arrive during a later one; the echoed name and password tell them apart | 1.1.15 | 8232 echoes field 2 (name and password lengths match the 112 request) |
