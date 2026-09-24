#!/usr/bin/env python3
"""Decode official-app UCD2 command numbers from a pcap or decoded JSON take."""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

import luna_wire  # noqa: E402
import ucd2  # noqa: E402

CODES_PATH = ROOT / "luna_message_codes.json"


def load_codes() -> dict[int, str]:
    raw = json.loads(CODES_PATH.read_text())
    return {int(k): v for k, v in raw.items()}


def packed_varints(data: bytes) -> list[int]:
    values, offset = [], 0
    while offset < len(data):
        value, offset = luna_wire.read_varint(data, offset)
        values.append(value)
    return values


def summarize_body(code: int, body: bytes) -> str:
    try:
        fields = luna_wire.fields(body)
    except ValueError as error:
        return f"unparsed: {error}"
    bits = []
    for field, wire, value in fields:
        if wire == 0:
            bits.append(f"{field}={value}")
        elif wire == 2 and isinstance(value, bytes):
            if field == 1 and code in (7, 8, 9, 10):
                try:
                    numbers = packed_varints(value) if value and value[0] < 0x80 else [
                        n for f, w, n in luna_wire.fields(value) if f == 1 and w == 0
                    ]
                    if not numbers:
                        numbers = packed_varints(value)
                    bits.append(f"{field}=types{numbers}")
                    continue
                except ValueError:
                    pass
            bits.append(f"{field}=[{len(value)}b]")
        else:
            bits.append(f"{field}/w{wire}")
    return " ".join(bits[:12])


def from_decoded_json(path: pathlib.Path, names: dict[int, str]) -> list[dict]:
    rows = []
    payload = json.loads(path.read_text())
    streams = payload if isinstance(payload, list) else [payload]
    for stream in streams:
        source = str(stream.get("source", ""))
        camera = source.endswith(".1") or source == "192.168.42.1"
        direction = "camera" if camera else "phone"
        for frame in stream.get("frames", []):
            if "code" not in frame:
                continue
            code = int(frame["code"])
            flags = int(frame.get("flags") or 0)
            body = bytes.fromhex(frame.get("body_hex") or "")
            if camera and code == 200:
                name = "RESPONSE_OK"
            elif camera and code == 500:
                name = "RESPONSE_ERROR"
            else:
                name = names.get(code, f"UNNAMED_{code}")
            rows.append({
                "source_frame": frame.get("source_frame"),
                "epoch": frame.get("epoch"),
                "direction": direction,
                "code": code,
                "name": name,
                "id": frame.get("id"),
                "type": frame.get("type"),
                "flags": flags,
                "request": not camera,
                "summary": summarize_body(code, body) if body else "",
            })
    return rows


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    names = load_codes()
    path = pathlib.Path(args.source)
    rows = from_decoded_json(path, names)
    if args.json:
        json.dump(rows, sys.stdout, indent=2)
        print()
        return 0
    counts: dict[tuple[int, str], int] = {}
    for row in rows:
        if row["type"] != 4:
            continue
        key = (row["code"], row["name"])
        counts[key] = counts.get(key, 0) + 1
        print(f"{row.get('source_frame')}\t{row['code']}\t{row['name']}\tid={row['id']}\t{row['summary']}")
    print("\n# counts")
    for (code, name), count in sorted(counts.items(), key=lambda item: (-item[1], item[0][0])):
        print(f"{count:4}  {code:5}  {name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
