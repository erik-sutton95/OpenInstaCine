# OpenCine integration candidate

Branch `opencine/integration` combines every local OpenCine candidate for OpenInstaCine so it
can be reviewed and device-tested once. Local only: nothing is pushed, and it cannot build in
CI until the shared repositories are published (see the end of this page).

## What it combines

| Work package | Source branch | Head |
| --- | --- | --- |
| CORE-02 Luna: ISO, shutter, white balance and record through OpenCineCore `CameraSession` | `opencine/core-02-luna` | 04f6413 |
| STATE-01 Luna: per-session ownership, profile, zoom ceiling and EV calibration; CORE-01b adoption | `opencine/state-01-luna` (contains core-02-luna) | 7353aa7 |
| UI-03: design system from OpenCineUI (`MonitorUI`, `MonitorPresentation`, Android `monitor-ui`) | `opencine/ui-03-shared-ui` | ede16d7 |
| MEDIA-01: LUT, curve, scope, shutter angle and frame timing math from OpenCineMedia | `opencine/media-01` | f579e8f |

Base is `opencine/state-01-luna`; the other two are merged with `--no-ff`. Pinned siblings
(`opencine-pins.txt`): OpenCineUI 54bcbb3, OpenCineCore 28a0196 (contains the MEDIA-01
commit 4d001e4 the media branch pinned). `ios/project.yml` names both packages by path;
Android includes `../../../OpenCineUI/Android` (default name `Android`) and
`../../../OpenCineCore/Android` (named `opencinecore`). The root `Package.swift` takes
OpenCineMedia from `../OpenCineCore`, the same checkout the app project names, so Xcode sees
one package identity. `tools/build-identity.py` hashes both siblings on both platforms
(OpenCineCore `Package.swift` and `Sources`, plus `Android` for Android builds).

## What changes for users

Nothing is meant to look different. Underneath:

- Command path: ISO, shutter, white balance and record go through one OpenCineCore session per
  camera. A change shows as confirmed only after the camera reports it; a refused, unapplied or
  timed out write says so instead of reverting silently.
- Session isolation: each connection owns its backend, labels, media route, zoom ceiling (15x
  on Luna, previously clamped to 12x in readouts) and learned picture EV calibration. Old v1 EV
  offsets seed the new per-camera keys and are never rewritten.
- Shared UI and media: theme, Sora, icons and page layouts come from OpenCineUI; LUT, I-Log
  curve, scope and false-colour math come from OpenCineMedia. Screenshots matched before and
  after on the simulator.

## Physical device checklist (Luna Ultra, iOS and Android)

Nothing below has run on hardware.

1. Install over a build that learned an I-Log picture EV: the meter starts at the old value,
   then learns per camera; it keys separately for Matrix/Face metering and I-Log/Standard.
2. Look: yellow accent with dark text on yellow, Sora, Lucide icons on first launch, cameras,
   pair, settings, live and media screens. Mode, colour and gimbal names are Luna names
   (TimeShift, Standard, Roll Lock).
3. ISO Auto, 400, 800 confirms in under 4 s; shutter then ISO quickly (and the reverse) neither
   reverts; a manual ISO the camera drops shows "not applied".
4. WB Kelvin confirms within 6 s; WB Auto confirms; AE Lock and AWB Lock work.
5. Record start and stop: the lamp waits for capture status; stop with file save under 10 s;
   start on the camera button, then app Record sends Stop; a fresh connect before capture status
   refuses; timelapse record; watch and watcher-relay record.
6. Mode change, then ISO/WB lands in the new bank.
7. Wi-Fi drop mid-write shows "link dropped", recovers, and controls work; reconnect makes old
   controls stale; a stream restart (album return, stall repair) during an ISO write still
   confirms it.
8. Zoom chip and dial reach and show 15x.
9. Media album thumbnails, playback and download from 192.168.42.1; LUT preview, false colour,
   waveform/parade and I-Log display match the previous build.
10. Live View diagnostics copy works before and after connect.

Known limits: two Luna cameras at once cannot be tested (LunaWiFi joins one camera access point,
192.168.42.x); the two-session gate is simulated only. Android reports no serial on this path,
so EV keys use the connected camera id.

## Risks before merging

- Sync divergence: STATE-01 changed `Sources/OpenPocketViewCore` (`CameraProfile`,
  `MediaHTTP.Route`, `label(in:)`, the `CamFov` ceiling). `scripts/sync-openpocketcine.sh` copies
  that directory from OpenPocketCine and would overwrite these changes. Port them upstream or move
  them into OpenCineCore/OpenCineUI before the next sync.
- Kotlin `ScopeExposureCeiling` is still a process-wide object on Android (MEDIA-01 remaining).

## Publishing prerequisite

The OpenCineUI and OpenCineCore repositories must exist before CI, Xcode Cloud or another
machine can build this branch: `scripts/checkout-opencine.sh` fetches the pinned SHAs from them.
Follow `opencapture-atlas/docs/PUBLISH.md`, then replace the path packages and included builds
with url + version pins and Maven coordinates.
