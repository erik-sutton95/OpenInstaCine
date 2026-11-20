# Changelog

## [Unreleased]

### Added

- iOS: live streaming of the monitor's camera to Twitch, YouTube, Facebook, Instagram or a Custom
  server (plain `rtmp://` allowed there with a warning, for TikTok LIVE): Settings, Sharing, Live
  stream, then Go live over the picture. Camera Wi-Fi blocks it; a shared Wi-Fi network or the
  phone's hotspot allows it. Untested on hardware.
- The monitor's lock button also holds the screen rotation, upside-down landscape
  included, so a phone mounted inverted no longer flips when it is levelled.

### Changed

- Android: the zoom chip can now read the Luna Ultra's 15x instead of stopping at 12x, as on
  iPhone (the shared zoom readout's default ceiling rose to 18x for the Pocket 4 Pro).

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
