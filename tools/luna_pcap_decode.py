#!/usr/bin/env python3
"""Decode UCD2 control messages (TCP 6666) from an rvi0 pcap into a readable log.

Usage: luna_pcap_decode.py take.pcap [--events events.log] [--all] [--json]

macOS tcpdump on rvi0 (PKTAP) sometimes writes a 24-byte classic pcap header in
front of a pcapng section; that header is stripped automatically. Needs tshark.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import struct
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))

import luna_wire  # noqa: E402
import ucd2  # noqa: E402

TSHARK = "/Applications/Wireshark.app/Contents/MacOS/tshark"
CAMERA = "192.168.42.1"


def table(name: str) -> dict[int, str]:
    return {int(k): v for k, v in json.loads((ROOT / f"{name}.json").read_text()).items()}


CODES = table("luna_message_codes")
PHOTO = table("luna_photography_options")
DEVICE = table("luna_device_options")
MODES = table("luna_function_modes")


def readable_pcap(path: pathlib.Path) -> pathlib.Path:
    head = path.read_bytes()[:32]
    if head[:4] == b"\xd4\xc3\xb2\xa1" and head[24:28] == b"\x0a\x0d\x0d\x0a":
        fixed = pathlib.Path(tempfile.mkstemp(suffix=".pcapng")[1])
        fixed.write_bytes(path.read_bytes()[24:])
        return fixed
    return path


def tcp_segments(path: pathlib.Path):
    out = subprocess.run([TSHARK, "-r", str(path), "-Y", "tcp.port==6666 && tcp.len>0",
                          "-T", "fields", "-e", "frame.time_epoch", "-e", "ip.src",
                          "-e", "tcp.stream", "-e", "tcp.seq_raw", "-e", "tcp.payload"],
                         capture_output=True, text=True).stdout
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) == 5 and parts[4]:
            yield float(parts[0]), parts[1], int(parts[2]), int(parts[3]), bytes.fromhex(parts[4])


def render(data: bytes, depth: int = 0) -> str:
    """Generic protobuf rendering; nested blobs recurse when they parse cleanly."""
    try:
        items = luna_wire.fields(data)
    except ValueError:
        return data.hex() if len(data) <= 24 else f"<{len(data)}b {data[:16].hex()}..>"
    if not items:
        return "{}"
    bits = []
    for field, wire, value in items:
        if wire == 0:
            bits.append(f"{field}:{value}")
        elif wire == 1:
            bits.append(f"{field}:d{struct.unpack('<d', value)[0]:g}")
        elif wire == 5:
            bits.append(f"{field}:f{struct.unpack('<f', value)[0]:g}")
        else:
            text = None
            if value and all(32 <= b < 127 for b in value) and len(value) > 2:
                text = value.decode()
            if text is not None:
                bits.append(f"{field}:'{text[:80]}'")
            elif depth < 4 and value:
                bits.append(f"{field}:{render(value, depth + 1)}")
            else:
                bits.append(f"{field}:<{len(value)}b>")
    return "{" + " ".join(bits) + "}"


def packed(value) -> list[int]:
    if isinstance(value, int):
        return [value]
    numbers, offset = [], 0
    while offset < len(value):
        n, offset = luna_wire.read_varint(value, offset)
        numbers.append(n)
    return numbers


def annotate(code: int, body: bytes, request: bool) -> str:
    """Name option types for the option GET/SET commands."""
    try:
        items = luna_wire.fields(body)
    except ValueError:
        return ""
    names = PHOTO if code in (9, 10) else DEVICE if code in (7, 8) else None
    if names is None or not request:
        return ""
    types = [n for f, _, v in items if f == 1 for n in packed(v)]
    mode = [v for f, _, v in items if f in (2, 3) and isinstance(v, int)]
    label = ",".join(f"{t}:{names.get(t, '?')}" for t in types)
    if mode and code in (9, 10):
        label += f" mode={mode[-1]}:{MODES.get(mode[-1], '?')}"
    return label


def decode(path: pathlib.Path):
    streams: dict[tuple[int, str], dict] = {}
    rows = []
    readable = readable_pcap(path)
    segments = list(tcp_segments(readable))
    if readable != path:
        readable.unlink()  # the stripped copy can be gigabytes
    for epoch, src, stream, seq, payload in segments:
        key = (stream, src)
        state = streams.setdefault(key, {"next": None, "r": ucd2.Reassembler(64 << 20)})
        if state["next"] is not None and seq < state["next"]:
            overlap = state["next"] - seq
            if overlap >= len(payload):
                continue  # retransmission
            payload = payload[overlap:]
        state["next"] = seq + len(payload) if state["next"] is None else max(state["next"], seq) + len(payload)
        for frame in state["r"].feed(payload):
            if frame.frame_type != 4:
                continue
            try:
                message = luna_wire.decode_message(frame)
            except ValueError:
                continue
            if message is None:
                continue
            camera = src == CAMERA
            code = message.code
            if camera and code == 200:
                name = "OK"
            elif camera and code == 500:
                name = "ERROR"
            else:
                name = CODES.get(code, f"UNNAMED_{code}")
            rows.append({"t": epoch, "stream": stream, "dir": "cam" if camera else "phone",
                         "code": code, "name": name, "id": message.identifier,
                         "flags": message.identifier_flags >> 30, "ctype": message.content_type,
                         "body": message.body.hex(),
                         "types": annotate(code, message.body, not camera),
                         "fields": render(message.body)})
    return rows


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pcap")
    parser.add_argument("--events", help="events.log (epoch<TAB>take<TAB>action<TAB>note)")
    parser.add_argument("--all", action="store_true", help="include replies and notifies")
    parser.add_argument("--quiet-poll", action="store_true",
                        help="hide cmd 15/8 poll traffic and their replies")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    rows = decode(pathlib.Path(args.pcap))
    if args.json:
        json.dump(rows, sys.stdout, indent=1)
        return 0
    events = []
    if args.events:
        for line in pathlib.Path(args.events).read_text().splitlines():
            parts = line.split("\t")
            if len(parts) >= 3:
                events.append((float(parts[0]), " ".join(parts[2:])))
    requests = {}
    for row in rows:
        if row["dir"] == "phone":
            requests[row["id"]] = row["name"]
    for row in rows:
        while events and events[0][0] <= row["t"]:
            print(f"\n=== {events[0][0]:.3f} EVENT {events[0][1]}")
            events.pop(0)
        if not args.all and row["dir"] == "cam" and row["code"] < 8192 and row["code"] != 500:
            continue
        reply_to = f" re:{requests.get(row['id'], '?')}" if row["dir"] == "cam" and row["code"] < 8192 else ""
        print(f"{row['t']:.3f} {row['dir']:5} {row['code']:5} {row['name']}{reply_to} id={row['id']} "
              f"{row['types']} {row['fields'][:600]}")
    for epoch, text in events:
        print(f"\n=== {epoch:.3f} EVENT {text}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
