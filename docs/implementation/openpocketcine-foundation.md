# OpenPocketCine foundation in OpenInstaCine

Date: 2026-09-17. This replaces the 2026-09-11 extraction from OpenPocketCine
`9c4e733`. The previous `Shared/Apple/MonitorUI` + `MonitorCore` snapshot had
already drifted from current OpenPocketCine.

## Parity contract

Until the two products share a monorepo, OpenInstaCine **vendors** the current
OpenPocketCine shared engine and native shells, then overlays brand identity and
the Luna adapter.

The design system is not vendored. Since 2026-10-01 (UI-03) `MonitorUI`,
`MonitorPresentation` (and `MonitorPresentationTests`) and the Android `monitor-ui`
module come from the OpenCineUI repository, a sibling checkout at `../OpenCineUI`:
`ios/project.yml` names it as a path package, and `Apps/Android/settings.gradle.kts`
includes `../../../OpenCineUI/Android` and substitutes
`com.opencapture.opencine:monitor-ui`. The sync never copies those paths, even
from an upstream commit that still has them. Change shared UI in OpenCineUI.

```sh
just sync-openpocketcine
# or: OPENPOCKETCINE_PATH=/path/to/OpenPocketCine bash scripts/sync-openpocketcine.sh [--dry-run]
```

`scripts/sync-openpocketcine.sh` is a three-way update, not a copy:

1. Builds the "renamed upstream" tree twice, in temp dirs: at the last synced
   commit (`docs/implementation/openpocketcine-sync-commit.txt`, override with
   `OLD_COMMIT=`) and at OpenPocketCine `HEAD` (override with `NEW_COMMIT=`).
   Each tree is `Sources/{OpenPocketViewCore,CJNI,OpenPocketCineAndroidFacade}`,
   `Tests/*` except `Tests/MonitorPresentationTests`, four build-phase `tools/`, and `ios/` renamed to OpenInstaCine,
   minus the `LUNA_OWNED` and `OSMO_ONLY` lists in the script, with
   `scripts/apply-openpocketcine-overlays.py` applied.
2. Diffs old to new (`git diff --no-index --binary`) and applies it with
   `git apply --3way`. Our edits to upstream-derived files survive; overlaps
   come out as conflicts and the script exits non-zero without recording the
   new commit. Commit or stash the synced paths first (`--3way` uses the index).
3. Engine and test dirs identical to the old upstream tree are rsynced from the
   new one instead. Dirs with local changes print a warning and go through the
   three-way diff.
4. Warns when upstream changed a Luna-owned file (never applied; port by hand).
5. Writes the new commit to `openpocketcine-sync-commit.txt`.

`--dry-run` prints the diff stat, saves the full patch to `$TMPDIR`, and runs
`git apply --3way --check`. It writes nothing to the repo.

### Core hooks (local changes to the engine)

These make `Sources/OpenPocketViewCore` (and one facade file) differ from
upstream, so the sync takes the three-way path for them. Upstream them when
possible. The brand accent is not an engine hook: OpenCineUI's `MonitorTheme`
already has a settable `accentRGB` and `onAccent`.

| File | Hook |
| --- | --- |
| `OpenPocketViewCore/CameraControl.swift` | `ColorMode.iLog` / `.dolbyVision`, `IsoIndex.iso160`, `VideoResolution.luna8K/6K/4K_9x16/3K/8K_235/4K_235`, `ShootingMode.labelOverrides`, settable `CamFov.maxFactor` |
| `OpenPocketViewCore/CameraStatus.swift` | `zoomFactorOverride` |
| `OpenPocketViewCore/LiveColorScience.swift` | `MonitorTransfer.ilog` and the I-Log curve |
| `OpenPocketViewCore/LogColorTransform.swift`, `CamCap.swift`, `OpenPocketCineAndroidFacade/FeedEffectsWire.swift` | exhaustive `switch` cases for `.ilog` |
| `OpenPocketViewCore/MonitorLUT.swift` | `lunaILog` LUT source and auto-pick |
| `OpenPocketViewCore/MediaManifest.swift` | `MediaHTTP.addressing` / settable `.host`, Insta360 filename dates, `.lrv` proxy |
| `OpenPocketViewCore/Diagnostics.swift`, `FeedIncidentStore.swift`, `WatchRelayProtocol.swift`, `WatcherRelayMessages.swift` | brand-neutral user copy (no "OpenPocketCine") |
| `Tests/OpenPocketViewCoreTests/MonitorLUTTests.swift`, `DiagnosticsTests.swift` | tests for the above |

Do **not** edit vendored trees for product features. Change OpenPocketCine, then
re-sync. OpenInstaCine-owned code is:

| Owner | Path |
| --- | --- |
| Brand storefront | `LUNA_OWNED` files in `ios/OpenInstaCine`, `Apps/Android/app` |
| Luna protocol | `Adapters/Insta360Protocol` |
| Luna Apple I/O | `Adapters/Insta360Apple` |
| Luna Android I/O | `Apps/Android/luna-adapter` |
| CameraBackend contract | `Sources/MonitorContracts` |
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
