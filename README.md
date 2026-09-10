# OpenInstaCine

Native iOS and Android monitor for Insta360 cameras, starting with **Luna Ultra**.
The product target is OpenPocketCine's operator experience: the same monitor
tools, media, playback, LUTs, and delivery, supplied by one shared engine.
Insta360 discovery, pairing, transport, camera controls, and capabilities belong
in an Insta360 `CameraBackend` adapter.

**Current stage: protocol discovery and capture tooling.** The official app's
TCP startup and ten HEVC preview frames are captured and decoded. Public
Luna-specific source provides the BLE bootstrap leads. BLE authorization and
an independent OpenInstaCine connection are next; app implementation is pending.

- [Protocol sources and command research](docs/research/insta360-protocol-sources.md)
- [First verified reconnect and decoded HEVC preview](docs/research/luna-reconnect-2026-09-11.md)
- [Hardware evidence and next milestones](docs/protocol-notes.md)
- [Capture workflow](docs/capture-guide.md)
- [Shared monitor architecture](docs/SHARED-MONITOR-ENGINE.md)
- [Extraction inventory and integration plan](docs/shared-engine-integration.md)

## Capture tools

Requires Python 3.11+, `just`, Wireshark/tshark, and Nordic `nrfutil ble-sniffer`.
The connected nRF52840 is already flashed as a BLE sniffer. Commands use the
installed tools; they do not flash the dongle or write camera commands.

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
