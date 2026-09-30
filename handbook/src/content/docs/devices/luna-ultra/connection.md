---
title: Luna Ultra connection and reconnect
description: Bluetooth wake, camera Wi-Fi lifetime, keep-alive and poll cadence, and OpenInstaCine reconnect evidence.
---

Part of the [Luna Ultra reference](../).
Read the overview for firmware, survey scope and evidence levels.

## Bluetooth and camera Wi-Fi

The camera advertises service **BE80** with a short name ending in its serial
suffix. OpenInstaCine names it **Luna Ultra** plus that suffix. Pairing,
approval and the encrypted Wi-Fi credential read are in
[BLE pairing](../../../protocol/ble/); they work unchanged on firmware 1.1.15.

| Observation | Firmware | Evidence |
| --- | --- | --- |
| The camera Wi-Fi turns off when an app session ends. After the official app was terminated the network was gone for over two minutes | 1.1.15 | Observed |
| A Bluetooth bootstrap (connect, key exchange, authorization check, credential read) wakes the Wi-Fi again | 1.1.15 | Verified; new empty BLE notification 8215 `CAM_WIFI_START` |
| First approval, then a saved-identity reconnect without a new prompt | 1.0.288 and 1.1.15 | Verified with our own client identity |
| The camera Wi-Fi is WPA2 with the camera at `192.168.42.1`; the phone gets a `192.168.42.x` address | both | Verified |

Because the Wi-Fi sleeps, OpenInstaCine connects over Bluetooth first whenever
the camera is advertising. The saved Wi-Fi details are the fallback.

## Session keep-alive and polls

| | Official app on 1.1.15 | OpenInstaCine |
| --- | --- | --- |
| Phone heartbeat (UCD2 type 5) | One after the preface, then none | Every 2 s |
| Camera heartbeat | Type 5 at 1 Hz | |
| Status polls | Every 10 s | Device status every 5 s |
| Capture status (cmd 15) | Only around capture | Every 1 s (drives the REC timer) |

The higher request rate has not shown a cost; it is kept because the record
timer needs it. The camera also sends notifications for capture (8208), settings
(8293, 8334), mode (8275) and storage (8198); the app re-reads status on those.

## OpenInstaCine connect and reconnect

| Check | Result |
| --- | --- |
| iPhone 16 Pro Max, iOS 27, firmware 1.1.15 | Bluetooth (already approved), camera Wi-Fi, TCP 6666, live at 25 fps. ISO, zoom, gimbal, color, record and delete all read back from the camera |
| iOS Simulator over the Mac's Wi-Fi | Connect to live; disconnect and reconnect to live in about 15 s |
| Link loss (Mac Wi-Fi off) | **Reconnecting**, then the **Connection keeps dropping** card at about 45 s; **Retry connection** restores live |
| Android, Bluetooth off | Live over the saved Wi-Fi in about 8 s |
| Android, phone Wi-Fi off and on | Back to live in about 30 s without a tap |
| First connect after an iOS reinstall | The system **Join Wi-Fi Network** alert appears and the join waits for the tap; a tap after the 35 s timeout still counts |

The iPhone hotspot join once returned an internal error on every attempt while
the camera network was up, then joined on the first attempt the next morning with
the same build. It was treated as environmental. The app now retries for up to
two minutes, drops the stale configuration between attempts, and after the third
attempt asks the operator to join in Settings, continuing on its own once the
camera subnet appears.

The Apple adapter compares the serial read over Bluetooth with the one read over
TCP, so a different camera at the same private address is not mistaken for the
paired one.
