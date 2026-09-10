# Mac live preview test

The Luna Ultra feed now works independently of the Insta360 app on this Mac.
The verified stream is **1280×720 HEVC Main, 25 fps, 8-bit BT.709 limited range**
on camera firmware **v1.0.288**.

## Open the feed

1. Keep the Luna awake and disconnect it in the Insta360 phone app.
2. Double-click **Open Luna Preview.command** in the project root, or run:

   ```sh
   just luna-view
   ```

The launcher negotiates BLE encryption, reuses our approved identity, retrieves
Wi-Fi credentials, joins the camera AP and opens the live window. This Mac's
camera advertisement name is already saved privately. On another setup, supply
the exact name once with `just luna-view 'EXACT_ADVERTISED_NAME'`.

Close the preview window or press **Q** to stop. The control session sends live
stop and disconnects. If the launcher changed Wi-Fi networks, it removes only
the camera profile it added and restores automatic Wi-Fi selection. This Mac
keeps internet access through its separate wired interface while previewing.

The viewer displays video only. Audio, record/exposure/gimbal controls, native
monitor tools and shared-engine integration are not part of this test launcher.
Viewing mode does not save the video stream; private control diagnostics and a
summary remain in `captures/`. The separate bounded capture tool saves video for
protocol analysis:

```sh
just luna-preview 20
```

## Verified behavior

- Own-client TCP greeting, model/firmware read, authorization status 0, capture
  status read, live-start response 200 and live-stop response 200.
- A 20-second requested take produced **467 decoded HEVC frames**, with about
  **18.53 seconds** between first and last received video packets. Startup time
  is included in the requested interval.
- A live window was visually inspected and ran for **271 seconds**, receiving
  **6,785 video packets** with **zero checksum failures** and no incomplete tail.
- Closing that window returned player exit 0 and an acknowledged stop command.
- The complete launcher subsequently repeated BLE → Wi-Fi → TCP → displayed
  video with the same client identity, without another camera approval.
- `just lab-check` passes 21 checks. The TCP integration tests also pass under
  macOS system Python 3.9.6.

The first viewer used FFplay's `nobuffer` option, which discarded initial decoder
reference frames during probing. Removing that option preserves the first
keyframe; the restarted viewer's log has no missing-reference/invalid-NAL errors.
Low-delay decoding and frame dropping remain enabled. End-to-end latency has not
yet been measured.

## Implementation and evidence

- `tools/luna_mac.py`: macOS launcher and temporary network setup/cleanup.
- `tools/luna_ble.py`: fresh P-256/AES-GCM session and authorized credentials.
- `tools/luna_tcp.py --view --seconds 0`: control session and FFplay video sink.
- `tools/luna_wire.py` / `tools/ucd2.py`: protobuf, framing and checksum.

TCP/protobuf parsing now runs without installing crypto or BLE dependencies into
system Python. BLE crypto imports remain available in the project venv. Using
`/usr/bin/python3` directly resolved this Mac's runtime-specific TCP failure;
launching netcat beneath the other interpreter had not resolved it. No macOS
privacy settings were changed.

| Evidence directory under `captures/` | Purpose |
| --- | --- |
| `20260910T231730790212Z-luna-tcp` | Bounded take, FFprobe decodes all 467 frames |
| `20260910T231839924146Z-luna-tcp` | First displayed feed and acknowledged close after 271 seconds |
| `20260910T232316263386Z-luna-ble` | Complete launcher's BLE reconnect |
| `20260910T232338140636Z-luna-tcp` | Complete launcher's live window |

The bounded take's `preview.hevc` SHA-256 is
`d4cde2bb593f9141673b22775fea601b8ea8f4e13b18dec8fabb1df382ab0bd9`.
Its camera wire SHA-256 is
`3c7a7c3518e6dde7d52dfbaea402e8ad979904f25ef4c6cd2262434374684de6`.
The live tests retain control diagnostics rather than video recordings. Raw
captures, camera images, credentials and identifiers stay gitignored.

The native OpenInstaCine product will consume the shared monitor engine. This
small Mac harness validates its future Insta360 backend's connection/feed path.
