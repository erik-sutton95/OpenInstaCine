"""Inspect one directional Luna screen session from an already decrypted TSV.

No sockets, radio changes, credentials, or device control. See the screen control
research note for the exact tshark export fields and capture limitations.
"""

from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path
import re
from typing import Iterable

from luna_screen_wire import (CaptureAssembler, decode_envelope,
                              decode_kcp_datagram, observed_h264_access_unit)


def inspect_capture(lines: Iterable[str], source_ip: str, source_port: int,
                    destination_port: int, conversation: int) -> tuple[dict, tuple[bytes, ...]]:
    """The input must cover one logical session; split captures at session resets."""
    collector = CaptureAssembler(conversation)
    commands: Counter[int] = Counter()
    selected = bootstrap = invalid = other_conversations = 0
    for number, line in enumerate(lines, 1):
        columns = line.rstrip("\r\n").split("\t")
        if len(columns) != 8:
            raise ValueError(f"Line {number}: expected eight TSV fields without a header")
        if columns[2:5] != [source_ip, str(source_port), str(destination_port)]:
            continue
        selected += 1
        try:
            data = bytes.fromhex(columns[5].replace(":", ""))
        except ValueError as error:
            raise ValueError(f"Line {number}: invalid UDP payload hex") from error
        if not data:
            invalid += 1
            continue
        try:
            segments = decode_kcp_datagram(data)
        except ValueError:
            try:
                envelope = decode_envelope(data)
            except ValueError:
                invalid += 1
                continue
            if envelope.kind == 2:
                bootstrap += 1
            else:
                invalid += 1
            continue
        for segment in segments:
            if segment.conversation != conversation:
                other_conversations += 1
                continue
            commands[segment.command] += 1
            collector.add(segment)

    result = collector.assemble()
    video = []
    nal_types: Counter[int] = Counter()
    for message in result.messages:
        try:
            unit = observed_h264_access_unit(message)
        except ValueError:
            continue
        video.append(unit)
        for marker in re.finditer(b"\x00\x00(?:\x00)?\x01", unit):
            if marker.end() < len(unit):
                nal_types[unit[marker.end()] & 31] += 1
    return {
        "selected_datagrams": selected,
        "valid_direct_kind_2_envelopes": bootstrap,
        "invalid_or_unrecognized_datagrams": invalid,
        "segments_from_other_conversations": other_conversations,
        "kcp_commands": dict(sorted(commands.items())),
        "duplicate_pushes": result.duplicate_pushes,
        "complete_crc_valid_messages": len(result.messages),
        "incomplete_groups": result.incomplete_groups,
        "invalid_envelope_groups": result.invalid_envelopes,
        "conflicting_groups": result.conflicting_groups,
        "observed_h264_access_units": len(video),
        "h264_bytes": sum(map(len, video)),
        "h264_nal_types": dict(sorted(nal_types.items())),
        "has_sps_pps_and_idr": all(nal_types[kind] for kind in (7, 8, 5)),
        "warning": "Capture gaps remain gaps. NAL presence alone does not establish decodability or I-Log encoding.",
    }, tuple(video)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tsv", type=Path)
    parser.add_argument("--source-ip", required=True)
    parser.add_argument("--source-port", type=int, required=True)
    parser.add_argument("--destination-port", type=int, required=True)
    parser.add_argument("--conversation", type=lambda value: int(value, 0), required=True)
    parser.add_argument("--h264-output", type=Path,
                        help="Create an incomplete elementary stream for offline analysis; refuses overwrite")
    args = parser.parse_args()
    try:
        with args.tsv.open() as source:
            summary, video = inspect_capture(source, args.source_ip, args.source_port,
                                             args.destination_port, args.conversation)
        if args.h264_output:
            with args.h264_output.open("xb") as destination:
                for unit in video:
                    destination.write(unit)
        print(json.dumps(summary, indent=2))
    except (OSError, ValueError) as error:
        parser.exit(2, f"{error}\n")


if __name__ == "__main__":
    main()
