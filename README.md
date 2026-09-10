# OpenInstaCine

Native iOS and Android monitor for Insta360 cameras, starting with **Luna Ultra**.
The product target is OpenPocketCine's operator experience: the same monitor
tools, media, playback, LUTs, and delivery, supplied by one shared engine.
Insta360 discovery, pairing, transport, camera controls, and capabilities belong
in an Insta360 `CameraBackend` adapter.

**Current stage: working Mac live preview test.** Our client negotiates BLE
encryption, reuses camera authorization, joins Wi-Fi and displays the Luna's
1280×720 HEVC feed at 25 fps. The native apps and shared monitor integration remain
to be implemented.

Double-click **Open Luna Preview.command**, or run `just luna-view` with the
camera awake and the Insta360 app disconnected. Close the video window to stop.
[Mac viewer instructions and verification](docs/mac-preview.md).

- [Protocol sources and command research](docs/research/insta360-protocol-sources.md)
- [Verified BLE handshake and repeatable client](docs/research/luna-ble-bootstrap-2026-09-11.md)
- [Own Wi-Fi handoff and preview lab](docs/research/luna-own-network-2026-09-11.md)
- [First verified reconnect and decoded HEVC preview](docs/research/luna-reconnect-2026-09-11.md)
- [Hardware evidence and next milestones](docs/protocol-notes.md)
- [Capture workflow](docs/capture-guide.md)
- [Shared monitor architecture](docs/SHARED-MONITOR-ENGINE.md)
- [Extraction inventory and integration plan](docs/shared-engine-integration.md)

## BLE connection lab

```sh
just lab-setup
just luna-authorize 'EXACT_ADVERTISED_NAME'
just luna-connect 'EXACT_ADVERTISED_NAME'
just lab-check
```

Leave the camera awake and the official app disconnected. The first command
requests touchscreen approval for our own client identity; subsequent connections
reuse it. Credentials are saved privately in `.local/luna-wifi.json`, never
printed. This lab does not yet join the AP or start preview.

After joining the camera AP, `just luna-preview 20` runs the separate bounded TCP
capture tool using macOS system Python. The complete live sequence is now verified
on hardware and against a simulated camera. The `luna-view` launcher handles the
Wi-Fi association and display together.

## Passive capture tools

Requires Python 3.11+, `just`, Wireshark/tshark, and Nordic `nrfutil ble-sniffer`.
The connected nRF52840 is already flashed as a BLE sniffer. Commands use the
installed tools; these passive capture commands do not flash the dongle or write
camera commands. The separate connection lab above does send bootstrap commands.

```sh
just ble-scan advertisements 20
just ble-follow 'EXACT_ADVERTISED_NAME' connection-01 180
just ble-mark captures/SESSION 'Tapped Connect in official app'
just ble-report captures/SESSION/ble.pcap
just check
```

For an address target or explicit serial port, use
`python3 tools/ble_lab.py follow --help`. Scan first: a device may advertise an
identifier rather than the product name. Start following before connecting the
phone. An advertisement-only capture cannot establish the command set.

Raw captures, HCI logs, identifiers, camera credentials, and derived reports
remain in gitignored `captures/`. Publish reviewed protocol findings and
synthetic or explicitly sanitized test vectors, with provenance.
