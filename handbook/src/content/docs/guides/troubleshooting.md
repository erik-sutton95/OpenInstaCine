---
title: Troubleshooting
description: Pairing, camera Wi-Fi, live view, a sleeping gimbal, and settings that take a few seconds to apply.
---

Pairing and live view need a **physical** phone and the camera. The Simulator has no Bluetooth or camera Wi-Fi.

If a step fails, tap **Report a problem** on the pairing screen or in Operator
Setup → System. Describe what happened and choose whether to include technical
details. You can also ask for help at
[opencapture.org/openinstacine/support](https://opencapture.org/openinstacine/support/).
Never put camera Wi-Fi passwords, approval identities or captures in a report or
an issue.

## Before pairing

Force quit the Insta360 app. It can hold the camera, and then pairing or the
video link never completes. Do this on every phone near the camera, not only the
one you are pairing.

Update the camera to **firmware 1.1.15** in the Insta360 app first. That is the
firmware OpenInstaCine is verified on.

## Camera does not appear

Wake the Luna, stay close, and allow Bluetooth. The camera appears as
**Luna Ultra** followed by a short code.

After about 20 seconds with no camera, the pairing screen shows **Still
looking**: "Force quit the Insta360 app on every phone near the camera. Make
sure the camera is on and activated, then move closer." A new camera must be
activated in the Insta360 app once before any other app can pair with it.

If Bluetooth access is off for OpenInstaCine, the pairing screen says so and
offers **Open Settings**. On Android, finding the camera needs **Nearby
devices** on Android 12 and newer, or **Location** with Location turned on on
Android 10 and 11.

## Camera asks for approval

The first time a phone pairs, the Luna shows a prompt on its touchscreen.
Accept it there. The app waits for the camera's answer and then reads the
camera's Wi-Fi details over Bluetooth. Later connections reuse the approval and
skip the prompt. If you reinstall the app, it has a new identity and the camera
asks again.

## Wi-Fi join never finishes

After Bluetooth, the phone joins the camera's own network. On iPhone the first
connect after an install shows the system **Join Wi-Fi Network** alert; tap
**Join**. The app keeps retrying for up to two minutes and continues as soon as
the phone has a `192.168.42.x` address. After the third failed attempt it asks
you to join the camera network in Settings yourself; it then continues on its
own.

On Android the join is a system network request. The app retries for up to two
minutes after the Bluetooth handoff and adopts any Wi-Fi network that is already
on the camera subnet.

The camera turns its Wi-Fi off a while after the last app session ends. A
reconnect wakes it over Bluetooth first whenever the camera is advertising; the
saved Wi-Fi details are the fallback.

## Stuck on Open video link (iPhone Local Network)

iOS needs **Local Network** access to reach the camera at `192.168.42.1`. If it
is off, the failure offers **Open Settings** (Settings, OpenInstaCine, Local
Network). If the camera never answers over Wi-Fi, pause any VPN or ad blocker
and try again.

## Picture is grey or black, or the gimbal does nothing

The Luna's gimbal sleeps pointing down until an app enters the shooting view.
OpenInstaCine sends the wake before every live start. If you opened the camera's
own playback, or the Insta360 app was connected, leave Media and return to live
view, or reconnect.

## Picture looks flat or washed out

The camera is probably in **I-Log**. The live picture carries the log curve.
Turn on **LUT → Auto** to apply the official Insta360 I-Log to Rec.709 look, or
switch color to Standard. Scopes and false color can read either the log signal
or the Rec.709 look.

## A setting jumps back or takes a few seconds

White balance kelvin and metering (Matrix or Face Priority) apply on the camera
3.5 to 5 seconds after the change. The app holds your selection on screen while
the camera catches up. Vivid and HDR color are refused by the camera on firmware
1.1.15, so the app does not offer them.

## Audio controls are missing

Firmware 1.1.15 exposes no audio mode or level on the phone protocol. Set
Original Audio, Wind Reduction or Voice Enhancement on the camera's screen. The
live AUDIO tool is hidden; playback of a downloaded clip keeps its meters.

## Clip does not play from the camera

Playback downloads the clip's `.lrv` proxy over the camera's Wi-Fi, which needs
an open connection to the camera. Reconnect, then open the clip again. Cached
clips play offline.

## Connection keeps dropping

After a drop the app shows **Reconnecting**, then a recovery card if the link
keeps failing. **Retry connection** runs the same Bluetooth-first path as a new
connect. Move closer, and check that no other phone has the Insta360 app open.
