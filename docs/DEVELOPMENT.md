# Developing OpenInstaCine

Lab and build notes that used to live in the README. The shared monitor engine
contract is [SHARED-MONITOR-ENGINE.md](SHARED-MONITOR-ENGINE.md).

## Layout

| Path | What |
| --- | --- |
| `ios/` | XcodeGen project (`ios/project.yml`), app `ios/OpenInstaCine`, tests, watch app |
| `Sources/` | Shared OpenPocketCine core (`OpenPocketViewCore`, `MonitorContracts`, `MonitorUI`, ...) with small Luna hooks (I-Log color mode, Luna resolutions, `.lrv` proxy) |
| `Adapters/Insta360Protocol` | Portable Luna codec: UCD2 framing, protobuf, status, settings, media and control messages |
| `Adapters/Insta360Apple` | CoreBluetooth pairing, CryptoKit handshake, Keychain, camera Wi-Fi join, TCP transport |
| `tools/LunaProbe` | Swift CLI that drives the camera from a Mac on its Wi-Fi (used for the fw 1.1.15 verification) |
| `tools/` | Python lab tools: BLE capture, Mac preview, DEBUG remote client |
| `Apps/Android` | Android app on the OpenPocketCine Android shell (synced to upstream `9e306c91`); builds, not yet verified on a physical Luna |

Luna-specific app code lives in `ios/OpenInstaCine/CameraSession.swift`,
`CameraSessionControls.swift`, `CameraMedia.swift` (Luna extension),
`LunaShellMapping.swift`, `LunaThumbnailImage.swift`, `DebugRemote.swift`,
`OpenInstaCineBrand.swift`, `OsmoCameraPageAdapter.swift` and
`OsmoMonitorPresentation.swift` (the `Osmo*` names are kept so shared call sites
bind unchanged). Everything else in `ios/OpenInstaCine` is the shared shell.
`just sync-openpocketcine` re-copies the shell from the sibling checkout and
leaves the Luna files alone.

## Build and run

Needs Xcode 26, XcodeGen and `just`. Run from the repository root.

| Recipe | What it does |
| --- | --- |
| `just ios-generate` | `xcodegen generate` in `ios/` |
| `just ios-build` | Simulator build, no signing, derived data in `.local/DD` |
| `just ios-run [device]` | Development-signed build, install and launch on a USB iPhone (devicectl id) |
| `just ios-test` | App unit tests on the first available iPhone simulator |
| `just core-test` | `swift test` for the shared core and `Adapters/Insta360Protocol` |
| `just oic-remote ...` | DEBUG remote client (see below) |
| `just sync-openpocketcine` | Re-sync the shell from `../OpenPocketCine` |
| `just luna-official-xc device` | XCUITest driver for the official Insta360 app (lab captures) |
| `just lab-setup`, `just luna-view` | Python venv and the Mac live-view lab |
| `just android-build`, `just android-check` | Android debug APK, unit tests and lint |
| `just sentry-test`, `just testflight-notes`, `just android-play-notes` | Release tooling checks ([`RELEASE.md`](RELEASE.md)) |

## Simulator live testing rig

The Simulator has no Bluetooth or hotspot API but shares the Mac's network. In
the Simulator build the backend skips BLE and talks straight to a camera on the
current network (`LunaSessionHub` in `CameraSession.swift`,
`LunaCameraBackend(useExistingNetwork: true)`).

1. Join the Mac's `en0` to the camera AP (camera `192.168.42.1`, Mac gets a
   `192.168.42.x` address). `.local/wake-and-join.sh` wakes the camera Wi-Fi
   over BLE with the lab identity and joins `en0` using the password in
   `.local/luna-wifi.json`. Keep internet on another interface.
2. `just ios-build`, then install the DEBUG app in a booted simulator:
   `xcrun simctl install booted .local/DD/Build/Products/Debug-iphonesimulator/OpenInstaCine.app`
3. Launch with the already approved client identity (Simulator builds only read
   `LUNA_IDENTITY`, see `LunaSecureStore.swift`):

   ```sh
   SIMCTL_CHILD_LUNA_IDENTITY="$(python3 -c "import json;print(json.load(open('.local/luna-client-identity.json'))['authorization_id'])")" \
     xcrun simctl launch --terminate-running-process booted com.opencapture.openinstacine
   ```

   The identity value is private: it lives only in `.local/` (gitignored).
   Never paste it into commits, docs or logs.
4. Drive the app with the DEBUG remote: `scan`, then `connectFirst`.
5. Optional scripted walkthrough with real taps (XCUITest, same Simulator):

   ```sh
   TEST_RUNNER_OIC_WALKTHROUGH_DIR=$PWD/.local/live-walkthrough/ui \
   TEST_RUNNER_LUNA_IDENTITY=<identity> \
   xcodebuild -project ios/OpenInstaCine.xcodeproj -scheme OpenInstaCineUIReview \
     -destination "platform=iOS Simulator,id=<sim>" \
     -only-testing:OpenInstaCineUITests/LunaLiveWalkthroughTests test
   ```

   Screenshots land in the given folder. `testF_DeleteOwnClip` also needs
   `TEST_RUNNER_OIC_DELETE_CLIP=<a clip you recorded>`.

## DEBUG remote

DEBUG builds (never Release) run an HTTP listener on TCP 18780
(`ios/OpenInstaCine/DebugRemote.swift`). In the Simulator it is on localhost;
on a USB iPhone `tools/oic_remote.py` finds the CoreDevice tunnel itself when
`OIC_URL` is unset.

```sh
export OIC_URL=http://127.0.0.1:18780
python3 tools/oic_remote.py state          # JSON: phase, live stats, camera settings, panels, assists
python3 tools/oic_remote.py log            # recent control log
python3 tools/oic_remote.py do '{"action":"iso","value":400}'
python3 tools/oic_remote.py shot out.png   # key window snapshot
python3 tools/oic_remote.py frame out.jpg  # last decoded live frame
```

Actions (`"action"` plus the keys shown; every action takes an optional
`"pause"` in seconds):

| Group | Actions |
| --- | --- |
| Connection | `scan`, `connectFirst`, `reconnect` (`id` optional), `disconnect`, `pairNew` (`value` bool) |
| Capture | `record`, `mode` (`value` label, e.g. `"Timelapse"`), `format` (`value` chip label) |
| Exposure | `iso` (`value` number or `"auto"`), `shutter` (`value` denominator), `expo` (`"auto"`/`"manual"`), `ev` (`value` stops), `wb` (`value` kelvin or `"auto"`), `color` (`value` label) |
| Zoom | `zoom` (`value`), `pinch` (`value`, `steps`) |
| Gimbal | `stick` (`x`, `y`, `seconds`), `rc` (raw VirtualRC `steps` `[[pan, tilt, seconds]]`, `hz`), `recenter`, `flip`, `gimbalMode` (`value`), `gimbalSpeed` (`value`), `aim` (`yaw`, `pitch`), `level`, `sweep` (`mode` `raw`/`track`, `axis`, `amp`, `period`, `rate`, `hz`, `seconds`, `getHz`), `program` (`op`) |
| Head tracking | `headLogStart`, `headLog` (`anchor` `"imu"` optional; last 12 s of track, raw AirPods samples and IMU rate), `headTune` (`gain`, `lead`, `accel`, `window`, `tick`, `panScale`, `tiltScale`), `replay` (`rows` `[[t, yaw, pitch]]`, at most ~160 per request, `latency`) |
| Focus | `tap` (`x`, `y`), `track` (`x`, `y`, `w`, `h`), `cancelTrack` |
| UI | `lock` (`value` bool), `clean` (`value` bool), `panel` (`settings`, `media`, `homeSettings`, `homeMedia`), `settingsTab` (`value`), `sheet` (`value`), `assist` (`value` tool, e.g. `"WAVE"`) |
| Media | `mediaBrowse`, `mediaEnd`, `files`, `thumb`, `download`, `delete` (`value` filename) |
| Lab | `refreshStatus`, `raw` (`code`, `hex` body), `wait` (`seconds`) |

## Mac live-view lab

The Python viewer works independently of the app: `just lab-setup`, then
`just luna-authorize 'EXACT_ADVERTISED_NAME'` once and `just luna-view`.
It connects to the real camera and may change the Mac's Wi-Fi. Details:
[mac-preview.md](mac-preview.md).

## Protocol and research

- [fw 1.1.15 hardware verification](research/luna-fw-1.1.15-verification.md)
- [Command catalog](research/luna-command-catalog.md)
- [Public sources and command research](research/insta360-protocol-sources.md)
- [Verified BLE bootstrap](research/luna-ble-bootstrap-2026-09-11.md)
- [Own Wi-Fi handoff](research/luna-own-network-2026-09-11.md)
- [TCP reconnect and decoded HEVC](research/luna-reconnect-2026-09-11.md)
- [Portable Swift protocol](implementation/luna-swift-protocol.md)
- [I-Log color](implementation/i-log.md) and [white paper notes](research/luna-i-log-white-paper.md)
- [Color Recovery (detachable screen link)](implementation/luna-color-recovery.md)
- [Passive BLE capture workflow](capture-guide.md)

Raw captures, HCI logs, camera footage, identities and Wi-Fi credentials stay
in gitignored `captures/` and `.local/`. The app keeps its approval identity and
camera Wi-Fi password in the Keychain.
