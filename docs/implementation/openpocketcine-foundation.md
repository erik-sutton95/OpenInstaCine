# OpenPocketCine foundation in OpenInstaCine

Date: 2026-09-17. This replaces the 2026-09-11 extraction from OpenPocketCine
`9c4e733`. The previous `Shared/Apple/MonitorUI` + `MonitorCore` snapshot had
already drifted from current OpenPocketCine.

## Parity contract

Until the two products share a monorepo, OpenInstaCine **vendors** the OpenPocketCine iOS
presentation shell, then overlays brand identity and the Luna adapter. Everything that has a
shared OpenCine package comes from the OpenCine platform repository (`../OpenCine`) at the SHA
pinned in `opencine-pins.txt`, never from a copy:

| Shared system | Owner | How OpenInstaCine gets it |
| --- | --- | --- |
| Design system (`MonitorUI`, `MonitorPresentation`, Android `monitor-ui`) | OpenCine | `ios/project.yml` path package `OpenCine`; Android `monitor-ui` from the included build `../../../OpenCine/Android` (named `opencine`) |
| Camera contracts, media math, motion, relay, Apple decode runtime | OpenCine (`OpenCineCore`, `OpenCineMedia`, `OpenCineMotion`, `OpenCineRelay`, `OpenCineApple`) | root `Package.swift` and `ios/project.yml` path package |
| Android core, media, the live-view MediaCodec decoder (`HevcDecoder`) and the native Vulkan renderer (`libopc_vulkan.so`, `feed.OpcVulkan`) | OpenCine `Android/` (`:core`, `:media`, `:decoder`, `:vulkan`) | the same `opencine` included build |
| Luna protocol, Apple I/O, Kotlin shell contract and Luna adapter | OpenCine (Swift products, `Android/` `insta360-shell`, `insta360-luna`) | path package; the same `opencine` included build |
| DJI protocol and session | OpenCine (`OpenCineDJI`) | not linked: the Luna build never needs it |

Change shared code in OpenCine, then move the pin.

```sh
just sync-openpocketcine
# or: OPENPOCKETCINE_PATH=/path/to/OpenPocketCine bash scripts/sync-openpocketcine.sh [--dry-run]
```

## Sync scope (RELEASE-01, 2026-10-02)

What `scripts/sync-openpocketcine.sh` still copies, and only this:

- `ios/` renamed to OpenInstaCine: the iOS presentation shell (live view, assists and scopes,
  capture sheets, media library and delivery, settings, the watch app, app and UI tests) and
  `HevcDecoder`'s presentation side. Reason: this code is still per app in OpenPocketCine and has
  no shared package yet (MEDIA-02 left presentation orchestration in the apps). It stays synced
  until it moves into OpenCineUI or an OpenCineCore runtime product.
- Three neutral tools: `stamp-source-revision.sh`, `pull-control-log.sh`, `analyze-live-log.py`.

What it never copies, and why:

| Path | Reason |
| --- | --- |
| `Package.swift`, `Sources/`, `Tests/` (the Swift core, JNI facade and their tests) | OpenInstaCine-owned since RELEASE-01. SHELL-04 deleted the DJI transport files nothing here uses (DUML transport and notification assembly, HEVC depacketizer, set mailbox, handshake admission, BLE adverts, link diagnosis, multicam, station join, native gimbal stream and program zoom, stick luma) with their tests, and trimmed the JNI facade to the 8 natives the Android app calls. Upstream's `OpenPocketViewCore` now depends on OpenCineDJI (36 DJI files moved out), and this copy carries the STATE-01 Luna edits (`CameraProfile`, `MediaHTTP.Route`, `label(in:)`, the `CamFov` ceiling) plus the I-Log hooks below. A sync used to rsync or three-way these and would have overwritten them. |
| `Apps/Android` | Never synced (Android resyncs were always by hand). SHELL-04 deleted the DJI transport, Multiview and setup code the Luna build never ran. |
| `LUNA_OWNED` (Luna seams, brand assets, `project.yml`, `Package.resolved`, `ci_scripts`, `Frameio/`) | App-owned. `project.yml` names this app's package graph (OpenCineInsta360; upstream has OpenCineDJI, OpenCineMulticam). `Frameio/` stays until OpenInstaCine adopts OpenCineFrameIO. Upstream edits are reported, never applied. |
| `DJI_ONLY` (`BleLink`, `DatalinkDriver`, `Multiview*`, `StationNetworkSetupView`, `AddSetupView`, `WiFiNameAccess`, `CameraSession+DJI*`, their tests) | DJI transport, Multi View and the Wi-Fi and Hotspot setup sheets, built on OpenCineDJI/OpenCineMulticam APIs this app does not link. Deleted here in SHELL-04 (they were unreachable for a Luna); `FoundCamera` moved to its own app file. |
| Files deleted here that the last synced upstream had | Moved to a shared package, Osmo-only or DJI-only. Never patched or brought back; the script prints a note when upstream changed one. SHELL-04 also removed the DJI hooks from the synced `AppRoot`, `SavedCamerasView`, `OpenInstaCineApp`, `VideoDisplayOwnershipTests` and `CameraPagePresentationTests`, so an upstream edit next to those hooks can come out as a conflict: keep the hook deleted. |
| `RELEASE_OWNED` tooling, incl. `tools/build-identity.py` | Retargeted copies (Sentry projects, `:monitor` paths, this app's sibling packages). Port by hand. |

First sync after the OpenCine integration branches land: set
`docs/implementation/openpocketcine-sync-commit.txt` to the OpenPocketCine `main` commit that
contains its OpenCine integration. This branch already carries the same MEDIA-01/02, UI, motion,
relay and Apple-runtime refactors, so replaying them from 9e306c91 only produces conflicts (a dry
run against OpenPocketCine `opencine/integration` a76488ad: 43 shell files, 7 with conflicts, no
core, DJI, project or Android paths). Pocket's Frame.io move to OpenCineFrameIO (6183d949) is the
one shell change that needs a decision first: adopt the product here (link it in `project.yml`,
delete `Frameio/FrameioClient`, `FrameioModels`, `FrameioOAuth`) or keep excluding it.

Atlas: the remaining source-copy edge is OpenPocketCine `ios/OpenPocketCine` -> OpenInstaCine
`ios/OpenInstaCine` (iOS presentation shell, three-way sync, tools above). The former
OpenPocketCine `Sources/`/`Tests/` -> OpenInstaCine edge is retired: OpenInstaCine owns its core
copy, and shared systems are package dependency edges.

## How the sync works

`scripts/sync-openpocketcine.sh` is a three-way update, not a copy:

1. Builds the "renamed upstream" tree twice, in temp dirs: at the last synced
   commit (`docs/implementation/openpocketcine-sync-commit.txt`, override with
   `OLD_COMMIT=`) and at OpenPocketCine `HEAD` (override with `NEW_COMMIT=`).
   Each tree is `ios/` renamed to OpenInstaCine minus `LUNA_OWNED` and `DJI_ONLY`, plus the
   three tools, with `scripts/apply-openpocketcine-overlays.py` applied. Files deleted here are
   then dropped from both trees.
2. Diffs old to new (`git diff --no-index --binary`) and applies it with
   `git apply --3way`. Our edits to upstream-derived files survive; overlaps
   come out as conflicts and the script exits non-zero without recording the
   new commit. Commit or stash the synced paths first (`--3way` uses the index).
3. Warns when upstream changed a Luna-owned or release-owned file (never applied; port by hand).
4. Writes the new commit to `openpocketcine-sync-commit.txt`.

`--dry-run` prints the diff stat, saves the full patch to `$TMPDIR`, and runs
`git apply --3way --check`. It writes nothing to the repo.

### Core hooks (OpenInstaCine-owned core)

`Sources/OpenPocketViewCore` started as a copy of OpenPocketCine's and is no longer synced.
These are the Luna differences from upstream's last shared version:

| File | Hook |
| --- | --- |
| `OpenPocketViewCore/CameraControl.swift` | `ColorMode.iLog` / `.dolbyVision`, `IsoIndex.iso160`, `VideoResolution.luna8K/6K/4K_9x16/3K/8K_235/4K_235`, `label(in:)` with a per-session `CameraProfile`, constant `CamFov.maxFactor` with a `ceiling:` argument |
| `OpenPocketViewCore/CameraProfile.swift` | per-session mode, colour, gimbal and focus labels and the media route (STATE-01) |
| `OpenPocketViewCore/CameraStatus.swift` | `zoomFactorOverride` |
| `OpenPocketViewCore/LiveColorScience.swift` | `MonitorTransfer.ilog` and the I-Log curve |
| `OpenPocketViewCore/LogColorTransform.swift`, `CamCap.swift`, `OpenPocketCineAndroidFacade/FeedEffectsWire.swift` | exhaustive `switch` cases for `.ilog` |
| `OpenPocketViewCore/MonitorLUT.swift` | `lunaILog` LUT source and auto-pick |
| `OpenPocketViewCore/MediaManifest.swift` | `MediaHTTP.Route` (host + addressing), Insta360 filename dates, `.lrv` proxy |
| `OpenPocketViewCore/ExposureMeterReading.swift` | `imageEstimated` provenance |
| `OpenPocketViewCore/Diagnostics.swift`, `FeedIncidentStore.swift`, `WatchRelayProtocol.swift`, `WatcherRelayMessages.swift` | brand-neutral user copy (no "OpenPocketCine") |

Do **not** edit the vendored shell for product features. Change OpenPocketCine (or the shared
package), then re-sync. OpenInstaCine-owned code is:

| Owner | Path |
| --- | --- |
| Brand storefront | `LUNA_OWNED` files in `ios/OpenInstaCine`, `Apps/Android/app` |
| Swift core and JNI facade | `Package.swift`, `Sources/`, `Tests/` |
| Android shell | `Apps/Android` (`:monitor` is the inherited presentation, `:app` the brand) |
| Luna protocol, Apple I/O, Kotlin shell contract and adapter | sibling OpenCine (Insta360 products) |
| Overlays / sync | `scripts/sync-openpocketcine.sh`, `scripts/apply-openpocketcine-overlays.py` |
| Protocol research | `docs/research`, `tools/luna_*` |

Accent is `MonitorTheme.accentRGB = 0xFFCF00` (OpenCineUI theme, default
OpenPocketCine blue), set once in `OpenInstaCineBrand.apply()` before any view is
built. Android sets `MonitorPalette.accent` from `BrandIdentity` in
`MonitorConfiguration.install` before the first screen. Record red, false color,
and zebra keep their semantic colors.

## Camera seam

`CameraSession` in the vendored shell still knows Osmo types for HUD values.
Its scan / connect / disconnect / captured controls now dispatch through
`CameraBackend`. `LunaCameraBackend` is the only live adapter.

Captured Luna Ultra v1.0.288 operations that the adapter will send:

- Live start/stop
- Record start/stop, stills
- ISO, shutter, EV, Standard / I-Log / Dolby Vision, WB kelvin, zoom 1–6
- Gimbal stick / recenter / flip
- Tap focus, Deep Track
- Clip list / HTTP download / delete

Not wired (uncaptured or proven no-op):

- Color Recovery as phone photography option 73 (use the detached-screen RPC)
- Filter `gamma_mode` 18 SET
- Camera-side favorite / star
- UCD2 playback transport 89–99 (official iOS player uses HTTP)
- Watcher relay / Osmo station multiview
- Sentry reliability uploads

## Verification

- `swift test --package-path Adapters/Insta360Protocol`
- `swift test` in OpenCineUI (`MonitorPresentationTests`; its CI also runs the Android `monitor-ui` tests and lint)
- `just ios-generate && just ios-build`

Physical Luna connect, first picture, and control readback still require a
phone on the camera AP.
