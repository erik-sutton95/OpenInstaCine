# OpenPocketCine foundation in OpenInstaCine

Date: 2026-09-17. This replaces the 2026-09-11 extraction from OpenPocketCine
`9c4e733`. The previous `Shared/Apple/MonitorUI` + `MonitorCore` snapshot had
already drifted from current OpenPocketCine.

## Parity contract

Until the two products share a monorepo, OpenInstaCine **vendors** the current
OpenPocketCine shared engine and native shells, then overlays brand identity and
the Luna adapter.

```sh
just sync-openpocketcine
# or: OPENPOCKETCINE_PATH=/path/to/OpenPocketCine bash scripts/sync-openpocketcine.sh
```

That command:

1. Copies `Sources/MonitorPresentation`, `Sources/MonitorUI`,
   `Sources/OpenPocketViewCore`, JNI facade, and their tests from the sibling
   OpenPocketCine checkout.
2. Copies `ios/OpenPocketCine` into `Shared/Apple/MonitorShell` (minus the
   PocketCine app entry, Sentry reliability pipeline, and assets).
3. Copies Android `monitor-ui` and the PocketCine app sources into
   `Apps/Android/monitor`.
4. Applies the tiny overlays in `scripts/apply-openpocketcine-overlays.py`
   (injectable accent, I-Log / Dolby Vision color cases, Luna pairing copy).
5. Writes `docs/implementation/openpocketcine-provenance.json` with the source
   commit.

Do **not** edit vendored trees for product features. Change OpenPocketCine, then
re-sync. OpenInstaCine-owned code is:

| Owner | Path |
| --- | --- |
| Brand storefront | `Apps/Apple/OpenInstaCine`, `Apps/Android/app` |
| Luna protocol | `Adapters/Insta360Protocol` |
| Luna Apple I/O | `Adapters/Insta360Apple` |
| Luna Android I/O | `Apps/Android/luna-adapter` |
| CameraBackend contract | `Sources/MonitorContracts` |
| Overlays / sync | `scripts/sync-openpocketcine.sh`, `scripts/apply-openpocketcine-overlays.py` |
| Protocol research | `docs/research`, `tools/luna_*` |

Accent is `MonitorTheme.accentRGB = 0xFFCF00`, set once in
`OpenInstaCineBrand.apply()` before any view is built. Record red, false color,
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
- `swift test --filter MonitorPresentationTests`
- `just apple-generate && just apple-build`

Physical Luna connect, first picture, and control readback still require a
phone on the camera AP.
