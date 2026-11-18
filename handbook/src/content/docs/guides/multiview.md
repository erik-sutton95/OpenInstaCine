---
title: Multiview
description: Monitor up to four Luna cameras on one shared network, on iPhone and Android. Hardware-untested.
---

**Development build. No part of Luna Multiview has been checked with cameras yet.**
Every behavior below follows OpenCine's shared Multiview stage, the same one
OpenPocketCine uses, with Luna's own steps where the camera differs. Until the
hardware pass is done, read each sentence as what the app is built to do, not as
something that has been observed on a Luna.

Multiview shows up to four Luna cameras on one screen. The cameras and this phone
join one shared network (a Wi-Fi network or this phone's hotspot); each camera
keeps its own connection, picture and recording state. iPhone and Android offer
the same stage; see [Android differences](#android-differences) for the few
platform words that differ.

## Open Multiview

From **Your cameras**, tap the grid icon at the top-right of the camera list. Any
single camera connection closes first: Multiview owns the cameras until you close
it.

1. Each time you open Multiview, choose **Wi-Fi** (**Local Wi-Fi** on Android)
   for a router or another device's hotspot, or choose this phone's **Hotspot**.
   Select or enter the network name, then its password. A password saved by a
   Luna's Wi-Fi or hotspot setup fills in. A Luna cannot list nearby networks,
   so the wizard offers the current network, the saved ones and **Other
   network…**.
2. Tap **Connect over Wi-Fi** for a local network and approve the phone's join
   prompt if shown. Center stage opens with space for four cameras.
3. Stop recording on each camera and close the Insta360 app on other phones so
   the camera is free.
4. Tap **Add camera** and choose a nearby Luna. If the camera asks to allow this
   phone, tap **Allow** on its screen.
5. Repeat for the other cameras. The network is chosen once per session.

Use WPA2 and, for a hotspot, the 2.4 GHz compatibility setting. On iPhone, enable
**Allow Others to Join** and **Maximize Compatibility** under Personal Hotspot
first. iOS and Android do not give apps the hotspot password: enter it once.

## How a Luna joins the stage

Adding a Luna works like a Luna Wi-Fi or hotspot setup:

- Over Bluetooth the app asks the camera to allow this phone, reads its serial
  number and its own Wi-Fi details, then asks it to join the shared network.
  Bluetooth closes as soon as the camera has the network.
- The app then searches the phone's subnet for the camera's control port. A
  search opens no session with any camera: it only checks that a Luna answers.
  A camera that is still taking its address is asked for again for up to a
  minute.
- A camera is opened only after its serial matches the one read over Bluetooth.
  Cameras on other tiles are never searched or opened by another tile.

Luna has no experimental join path: a camera that cannot join shows why in its
tile. A Luna that another phone holds is not offered in the picker.

## Pictures, recording and Auto LUT

Each tile has its own Luna connection, decoder and status. Camera names, battery,
storage, reported timecode and recording state appear inside each feed, with ISO,
shutter, white balance and focus readouts for the selected camera, as in Live
View.

The shared record lamp starts all assigned cameras; if any camera is recording,
it stops them. Each camera must confirm its own result, and the lamp follows
each camera's own record reports, including recordings started on the camera.
Both the lamp and a tile's recording action follow the **Record confirmation**
preference in Settings. This is a shared command, not frame-accurate
synchronized recording.

**Auto LUT** starts on for each newly added camera. It follows what the picture
carries, with the same rule as Live View, not the recording profile alone. A
Luna's Color Recovery can bake Rec.709 into an I-Log recording's phone picture;
such a picture is never graded a second time. Only an I-Log picture that arrives
flat gets the bundled I-Log to Rec.709 look. On iPhone the **flat I-Log preview**
setting says which one you have (on by default, because firmware 1.1.15 sends a
flat I-Log preview); with it off, an I-Log tile reads **Auto · no conversion
needed**. Android has no such setting: like Android Live View, it treats the
I-Log picture as flat. Standard, Vivid, HDR and Dolby Vision get no automatic
conversion. The LUT affects monitoring only.

**Camera settings** in the toolbar opens the floating settings popup with the
same Luna controls as Live View. Its preview is the tile's own picture, and the
tile behind the popup keeps showing it. A change reaches a camera only while the
stage allows it: a group record, a reconnect, the app in the background or a
newer popup stops changes that have not been sent yet.

Double-tap a connected tile to open its Live View; the lock control becomes a
Multiview grid icon that returns to the stage. The borrowed Live View is the
monitor's own (the volume-key shutter and Settings' shutter angle work as in a
single-camera session), and Multiview stays the camera's repair owner while Live
View borrows it. Tiles use the same shutter angle or speed setting as Live View.

Layout (Grid or Center stage), the selected main camera and Fit/Fill are
remembered on this device.

## Recovery

A stalled picture is repaired in place first: a keyframe request after two
seconds without video, then up to two live restarts after six. If that does not
bring the picture back, or the control link is lost, the app looks for the camera
at its address on the shared network and reopens it there. A camera that no
longer answers is moved onto the network again over Bluetooth; only one camera
uses Bluetooth at a time. If the camera refuses this phone, the tile waits until
you allow it on the camera and tap **Reconnect**. Repair never stops a recording.

If this phone leaves the shared network, the stage waits for it to return before
repairing cameras. Keep Multiview in the foreground for continuous monitoring;
brief app switches keep the camera assignments.

## Closing Multiview

Closing Multiview closes every camera connection, then asks each camera over
Bluetooth to return to its own Wi-Fi (up to three tries a few seconds apart).
Approve the camera if it asks. A camera that cannot be reached, or that asks
for approval again, stays in this device's cleanup record and a later close tries again.
No stop-recording command is sent. Removing a tile closes monitoring only: the
camera stays on the shared network and any recording continues.

Network passwords stay in this device's Keychain on iPhone and are sealed with
an Android Keystore key on Android.

## Android differences

Android offers the same stage, network wizard, camera picker, tile pictures with
Auto LUT, Live View from a tile, the **Camera settings** popup, recording,
recovery and cleanup.

While the stage is open the single-camera monitor connects nothing on its own,
also when Android's Wi-Fi join prompt sends the app to the background and back.
Multiview does not open while a camera is connecting. Closing Multiview lets go
of the shared Wi-Fi the app asked Android for.

As in Pocket: Android uses **Phone hotspot** instead of Personal Hotspot,
**Local Wi-Fi** uses the current Wi-Fi when its name matches and otherwise shows
Android's own join prompt, and sockets are bound to that network so camera
traffic does not leave over mobile data.

## Not yet checked

Nothing on this page has been checked with Luna cameras on either platform:
joining and verification, the search, pictures, recording, recovery, the return
to the camera's own Wi-Fi, hotspot use, four-camera performance, battery and
heat. This page is updated after the hardware pass.
