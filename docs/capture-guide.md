# Luna Ultra capture workflow

Capture the official app's connection first, then reproduce the exchange with
our client. Keep BLE, phone HCI, and IP traffic as separate evidence sources.

## Equipment and capture layers

| Capture | What it gives us | What it cannot establish alone |
| --- | --- | --- |
| nRF52840 over-the-air BLE | Advertising, connection establishment, timing, GATT if visible, link security | Wi-Fi/IP; plaintext from encrypted application messages |
| iPhone Bluetooth HCI log | Phone-side connection, ATT writes/replies/notifications when logger records them | Camera Wi-Fi packets; decryption of UCD2 application encryption |
| iPhone RVI packet capture | Control sockets, preview and file-transfer network flows | BLE handshake; necessarily plaintext inside encrypted network sessions |
| Own-client instrumentation | Request IDs, parsed response status, our negotiated crypto session | Proof that untested commands work or that other camera models match |

An iPhone BLE scanner's own operation log is not the same as an HCI trace of the
official app. Confirm the logger before relying on it. Apple supplies
[Bluetooth developer tools](https://developer.apple.com/bluetooth/) and a
[Bluetooth logging profile](https://developer.apple.com/feedback-assistant/profiles-and-logs/).
Wireshark can read supported [PacketLogger/HCI formats](https://wiki.wireshark.org/Bluetooth).

Nordic requires appropriate keys or pairing capture conditions to decode an
encrypted BLE link; LE Secure Connections is not automatically decrypted just
because its pairing was captured. See [Nordic's pairing guidance](https://docs.nordicsemi.com/r/bundle/nrfutil/page/nrfutil-ble-sniffer/guides/common_sniffing_actions.html/sniffing-the-pairing-procedure-of-a-connection).
The separate UCD2 encryption layer is described in the
[Luna source research](research/insta360-protocol-sources.md).

## Prepare and identify the body

1. Put the powered camera and phone close to the dongle. Leave the official app
   disconnected while identifying the advertiser. Avoid a second BLE client
   connecting during the official-app take.
2. Record model, firmware, official-app version, iOS version, attached/detached
   touchscreen configuration, and whether camera authorization already exists.
   Preserve the initial state; an ordinary reconnect is useful if first pairing
   already happened. Factory reset is not part of this workflow.
3. Run `just ble-scan advertisements 20`. The tool prints a session directory.
4. Run `just ble-report captures/SESSION/ble.pcap`. Inspect `advertisements.tsv`
   locally. Look for service BE80 and stable CRC-valid advertisements, not only
   names containing Luna. Match the candidate to this camera through its state
   or displayed identity. A BE80 advertisement alone is not model identification.
5. Use the observed address or exact name for following. Addresses can change.

## Take 1: connection and authorization

Start the iPhone HCI logger, then arm the sniffer **before** tapping Connect:

```sh
just ble-follow 'EXACT_ADVERTISED_NAME' connection-01 180
# Alternative, using the address observed in this session:
python3 tools/ble_lab.py follow connection-01 --address AA:BB:CC:DD:EE:FF --seconds 180
```

The script prints a new directory. In another terminal, mark actions:

```sh
just ble-mark captures/SESSION 'Before opening official app'
just ble-mark captures/SESSION 'Tapped Connect'
just ble-mark captures/SESSION 'Camera authorization prompt appeared'
just ble-mark captures/SESSION 'Approved on camera'
just ble-mark captures/SESSION 'Phone accepted Wi-Fi join'
just ble-mark captures/SESSION 'First live picture'
just ble-mark captures/SESSION 'Disconnected in app'
```

Write only markers that happened. Keep these as close to each action as possible;
note if a timestamp was retrospective. Leave about ten seconds idle around each
transition. Export the phone's HCI log into the same session directory and record
its clock offset or correlate it to the connection event. Fill metadata fields.

Do a second and third reconnect with the same configuration. Record whether the
camera prompts again and whether the phone was already on the camera AP. Later,
capture cancellation at authorization, rejected authorization, camera restart,
app reconnect, and AP loss as separate labelled takes.

Nordic's installed CLI supports address/name following, scan responses and
auxiliary advertisements; see its [capture documentation](https://docs.nordicsemi.com/r/bundle/nrfutil/page/nrfutil-ble-sniffer/guides/sniff.html).
`--coded` is available for a separate LE Coded PHY scan when needed; do not assume
an empty default scan means the camera has no BLE. The nRF sniffer does not
capture Bluetooth Classic or Wi-Fi traffic.

## Extract and assess the capture

```sh
just ble-report captures/SESSION/ble.pcap
just ble-report captures/SESSION/phone.pklg
```

Each invocation creates a new local report with source SHA-256, tool version,
advertisements, ATT TSV, link metadata, and structured Bluetooth JSON. Nothing
is automatically interpreted as a Luna command. No raw payloads print to stdout.

Check these before interpreting the payload:

- Is the intended connection present from establishment, with valid packets?
- Do we have GATT discovery, write mode, CCCD enable and negotiated MTU?
- Can ATT be decoded? Zero ATT in an advertising-only take is expected; zero ATT
  after connection requires checking following, capture start and encryption.
- Use the JSON for multi-attribute discovery: flat TSV lists cannot pair every
  handle with its corresponding UUID. Keep transport direction and connection
  handle/access address; request IDs can repeat across reconnects.
- ATT value boundaries are not necessarily UCD2 message boundaries. Reassemble
  by connection and direction, retaining fragments and the source frame numbers.
- A notification or ATT write response alone does not prove command success.
  Correlate the UCD2 response status and camera/app state.

If Wi-Fi credential requests have encrypted UCD2 payloads, stop treating their
ciphertext as protobuf or a static password. Implement the source-backed crypto
negotiation for our own session, then validate an authenticated response.

## Take 2: network handoff and preview

Once BLE is understood, capture the phone's network path alongside its BLE log.
OpenZCine's existing helper demonstrates Apple's `rvictl` plus `tcpdump` workflow;
reuse that approach after identifying the connected phone's actual USB UDID and
RVI interface. `devicectl`'s CoreDevice identifier is not automatically the USB UDID.
Do not silently assume `rvi0` belongs to the desired device.

Record the camera's real AP/interface addresses first; use public-source IP/port
values only as candidates. Capture connect → idle 10 s → live 10 s → exit 5 s,
then repeat. If live starts automatically, mark that and compare with another
non-live state. Capture full packet lengths and retain control plus media flows.

After first picture, isolate record start/stop, one exposure value, white balance,
format changes, zoom, gimbal actions, and media browse/download into separate
takes. An operation absent from the BLE trace may be on the network transport.
Do not test delete/format as discovery probes.

## Publishable result

For each verified operation, document model/firmware, source capture hash and
frame range, direction, complete reassembled frame, request/response correlation,
semantic fields, preconditions, timeout behavior, and independent repeat result.
Replace identifiers/credentials in any published fixture and make its synthetic
or sanitized provenance explicit. Raw captures and all reports stay local.
