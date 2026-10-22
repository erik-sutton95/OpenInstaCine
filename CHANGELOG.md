# Changelog

## [Unreleased]

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
  through buffering, scrubbing and app background/return.
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
