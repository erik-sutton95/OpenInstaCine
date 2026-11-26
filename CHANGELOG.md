# Changelog

## [Unreleased]

### Added

- Insta360 Luna Pro, untested: the apps connect to a Luna Pro like a Luna Ultra on iOS and
  Android, name it "Luna Pro" once connected, and show its own zoom: presets 1×, 2× and 4×, up to
  4×, with no 3× telephoto stop or TELE caption. Nobody has tried one yet; the Pro's model string
  is taken from Insta360's published specs. Another Insta360 camera is refused by name ("This
  camera is ... OpenInstaCine currently supports the Insta360 Luna Ultra and Luna Pro."), now on
  Android too. A nearby camera reads "Luna" plus its serial until it connects, since a Luna does not
  advertise its model.

### Fixed

- Recording in I-Log with Color Recovery no longer stops the take: when the record start pauses
  the camera's picture, the app keeps asking for a fresh picture instead of restarting live (which
  ended the recording and dropped back to monitoring). Live is restarted during a take only after
  30 s without video. Same on Android and in Multiview (OpenCine feed-stall ladder).

## [0.2.0] - 2026-11-22

Beta, cumulative since 0.1.3. The operator-facing iOS and Android lists are in the
[0.2.0 release notes](handbook/src/content/docs/releases/0-2-0.md).

### Added

- iOS: live streaming of the monitor's camera to Twitch, YouTube, Facebook, Instagram or a Custom
  server (plain `rtmp://` allowed there with a warning, for TikTok LIVE): Settings, Sharing, Live
  stream, then Go live. Camera Wi-Fi blocks it; a shared Wi-Fi network or the phone's hotspot
  allows it. While the monitor is closed, a Live pill at the top shows the stream with Stop.
  Streamed on an iPhone with a Luna Ultra on firmware 1.2.7 over a home router; the individual
  services are not each checked yet.
- Android: live streaming of the camera picture (with the monitor LUT, without assists) over
  RTMPS, or plain `rtmp://` to a Custom server with a warning, while the camera is on a Wi-Fi or
  hotspot setup. The Live stream card on Settings, Sharing holds the service and stream key; Go
  live sits on the monitor and a Live pill with Stop shows while the monitor is closed. The
  stream ends when the app leaves the screen. Untested on hardware.
- Live stream quality: when the camera picture is below 1080p, the Live stream card offers
  1080p upscaled (about 6 Mbps, with the LUT) beside Camera feed.
- Zoom panel: holding the zoom chip opens one panel on the trailing edge with the current zoom, a
  vertical ruler (smooth zoom, 0.1x ticks), three preset slots and a preset ramp (Off, or 0.5 s
  to 10 s) chosen in the camera value popup. Tap a preset to go there; with a ramp the zoom moves
  over that time. Go live now sits under the timecode and steps aside while the panel is open.
- Multiview on iOS and Android: up to four Luna cameras on one shared Wi-Fi network or this
  phone's hotspot, opened from the grid icon on Your cameras, on OpenCine's shared stage (see
  the handbook's Multiview guide). Untested with cameras.
- Camera presets: the Settings Controls tab saves the connected camera's exposure and white
  balance under a name, to recall or delete later, kept per camera model.
- GUIDES options add Action safe and Title safe lines, each with a size from 50% to 99%, drawn
  inside every selected frame line on live view and playback.
- The monitor's lock button also holds the screen rotation, upside-down landscape
  included, so a phone mounted inverted no longer flips when it is levelled.

### Changed

- Android: the zoom chip can now read the Luna Ultra's 15x instead of stopping at 12x, as on
  iPhone (the shared zoom readout's default ceiling rose to 18x for the Pocket 4 Pro).

### Fixed

- Luna Ultra firmware 1.2.7: a Wi-Fi or hotspot setup keeps the camera on the network. The
  firmware leaves it about 60 s after each join, so the picture dropped out every couple of
  minutes and Go live reached the platform at a low bitrate (OpenCine station keep-alive).
- Zoom preset ramps move smoothly: zoom steps go to the Luna about 28 times a second instead of
  6. A zoom step the camera leaves unanswered no longer freezes the ramp or says Zoom was not
  applied; the last step is sent once more first.
- Long programmed gimbal moves no longer stop partway with Programmed move was not applied when
  the camera leaves one target unanswered.
- Android: a Wi-Fi or hotspot setup checks the camera's serial number, so it connects to the
  requested Luna when other cameras share the network instead of the first one that answers.

## [0.1.3] - 2026-10-30

Public beta, cumulative since open beta build 26 (0.1.0). The operator-facing iOS and
Android lists are in the [0.1.3 release notes](handbook/src/content/docs/releases/0-1-3.md).

This beta is a parity and reliability update built on the shared OpenCine
foundation. Camera setup, the monitor, settings, View Assist, media and playback
follow the same shared components as the other OpenCapture apps, with Luna's
supported capabilities and single-camera iOS policy preserved.

### Added

- Shared monitoring, setup, settings, media and playback components across iOS
  and Android, with app differences supplied through camera capabilities.
- Feed incident diagnostics distinguish incoming video, decoding and display
  activity, carrying build/source identity for dropout investigation.

### Changed

- Landscape places the colour profile beside the codec; portrait card-space
  values remain readable near the cutout.
- Monitoring colour follows the selected camera profile. I-Log clipping guidance
  accounts for ISO; the ISO-dependent ceilings still need physical calibration.
- Recovery from a stalled live picture is bounded and ends in an honest retry
  state instead of staying on Reconnecting indefinitely.

### Fixed

- Shutter Angle follows angle picks, Auto-to-Manual transitions, AE lock and
  frame-rate changes. Android's EV meter follows the live picture again.
- Returning from Media refreshes the iOS live decoder. Playback keeps Pause
  through buffering, scrubbing, Share and app background/return.
- Android no longer freezes while the live picture rebuilds after rotating or
  returning to the app.
- Android zoom follows the zoom wheel and pinch while the finger moves instead
  of waiting for it to lift.
- iOS VoiceOver no longer reaches live controls under a covering screen.
- Sharing several cached clips stages them together with valid share names.
- A failed saved connection can retry on app return; scanning reflects Bluetooth
  availability and Android Wi-Fi failures open the relevant settings.
- Android restores the top-bar glow and keeps the space between crossing frame
  guides clear when Mask outside frame is enabled.
- Release shrinking preserves ML Kit's initialization so face detection can
  start in signed Android builds.

### Release qualification

Camera/device walkthroughs remain required before the next external beta. The
notes do not promise new camera support, iOS Multiview or live audio controls.
Better diagnostics are not a claim that every dropout has been eliminated.

### Public beta additions

- Media grid is staggered: portrait photos stand upright and every item fills the space above it.
- Caching and downloads show a live speed beside the percentage.
- Media selection leads with an Exit selection close; the bar keeps All, Share and Delete.
- Pinch-zoomed playback fills the screen past the clip's letterbox.
- Landscape Photo moves setup values to the status corner.
- iOS: connecting no longer freezes on Starting live view.
- Share finishes a clip whose cache the player left running or stopped.
- Cameras > Add setup connects a Luna over a Wi-Fi network or the phone's hotspot.
