# Luna Ultra: own-client Wi-Fi handoff and preview preparation

Date: 2026-09-11 Europe/Stockholm. Camera: Luna Ultra **v1.0.288**.
This follows the [successful saved-tool BLE run](luna-ble-bootstrap-2026-09-11.md).

**Later result, same session:** own TCP authorization, live preview, decoded
picture, acknowledged stop and repeated live connection now work through system
Python. A Mac live window ran for over four minutes. See the
[Mac preview report](../mac-preview.md) for final evidence and launcher usage.
The initial failures below remain as the diagnostic record.

## Verified on the Mac

After our saved BLE identity was recognized and fresh credentials were decrypted,
the Mac joined the camera AP using those credentials. No manually transcribed
password or official-app client identity was used.

| Check | Result |
| --- | --- |
| Wi-Fi association through `networksetup` | Successful, no reported error |
| Wi-Fi interface / assigned IPv4 | `en0` / **192.168.42.74** |
| Camera route | **192.168.42.1** through `en0` |
| Internet route | Remained on wired `en19`, gateway 192.168.1.1 |
| ICMP | Two replies from the camera, about 18 ms and 5 ms |
| HTTP port 80 | Root path returns **404**; listener is reachable, path is not a media endpoint |
| TCP port 6666 | System Python successfully opens and closes a socket |

Private association records are `.local/luna-wifi-join-result.json` and the
credential file. These checks establish association and listener reachability,
not an independently authenticated UCD2 session or a live picture.

After the AP became unreachable, the lab removed only the camera network profile
it had added (the before-state confirmed it was absent), and restored Wi-Fi.
The Mac returned to its earlier **192.168.1.87** address; wired internet stayed
available. `.local/network-restoration.json` records this cleanup. No existing
saved network profiles were removed.

## Failures preserved for diagnosis

The Python 3.13 lab interpreter returned immediate `EHOSTUNREACH` / errno **65**
for camera ports 80 and 6666, including explicit interface/address binding.
At the same time, curl reached HTTP and system Python opened port 6666.
The Python entry in macOS Local Network settings was already enabled; no privacy
switches were changed. The exact interpreter-specific cause remains unresolved.

`captures/20260910T225943637512Z-own-tcp-preview/` records the failed Python socket
attempt. `captures/20260910T230231949461Z-own-tcp-preview/` records the subsequent
system-netcat attempt: it received **zero camera bytes**. Later ICMP, HTTP, netcat
and system-Python checks all timed out, so the camera/AP had become unreachable.
This is distinct from the earlier interpreter-specific error. Sleep/power state
was not measured directly, and must not be asserted from a timeout alone.

No own-client UCD2 response or preview frame was captured in these attempts.
The only decoded camera picture remains the earlier
[official-app network capture](luna-reconnect-2026-09-11.md).

## Ready-to-run preview lab

`tools/luna_tcp.py` waits for the captured TCP greeting, reads model/firmware,
checks our saved authorization, reads capture status, sends the captured live
start body, saves video media, then sends stop. It uses two-second heartbeats
and bounds the requested capture to 1–60 seconds. Cleanup attempts stop when
start may have reached the camera, then closes the connection and helper process.

With the camera awake, official app disconnected and the Mac joined to its AP:

```sh
just luna-preview 20        # macOS system Python, verified on hardware
just luna-view              # BLE + Wi-Fi + live display launcher
```

The bounded capture tool does not associate Wi-Fi automatically; `luna-view`
does. The default destination is the
observed 192.168.42.1:6666. Raw directional bytes, message/media metadata, the
candidate HEVC elementary stream and checksummed artifact manifest remain under
private `captures/`. A `preview-captured` result means video-substream bytes were
received and stop acknowledged; it still needs FFprobe/FFmpeg decoding to prove
a valid picture. Exit 1 indicates failure; inspect the recorded failed stage.

Next hardware proof: our own greeting → authorization → live start → at least
20 seconds of valid decoded video → acknowledged stop → repeat connection.
Record first-frame delay, observed codec/color/dimensions, transport continuity
and restart behavior. Other media substreams are retained in the raw wire data
without assigning audio or metadata semantics prematurely.

## Offline verification

Two local simulated-camera tests cover the complete request sequence, fragmented
responses/coalesced live media, extraction, stop acknowledgment, and refusing to
start preview for an unauthorized identity. They do not establish hardware
support.

The checksum implementation now uses four table rounds per byte, preserving
the earlier 32-bit-round result. On a 64 KiB synthetic input it measured about
**0.483 → 2.885 MiB/s** in this session, with identical checksum `582A0F28`.
Existing real-packet fixtures still pass. This avoids the original decoder's
CPU bottleneck during larger network captures; it is not a native-app performance
measurement. `just lab-check` runs **21** offline checks in total.

These tools remain protocol research. The production Insta360 adapter must
provide timed native-decoder inputs to the shared monitor engine; it must not
make the shared UI depend on Python, netcat, or this Mac's network setup.
