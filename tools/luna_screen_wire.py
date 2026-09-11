"""Offline Luna screen framing, without sockets, radio control, or session policy.

Evidence: docs/research/luna-screen-udp-control.md. The CRCs detect corruption;
they are not authentication. This module does not implement a KCP endpoint or
claim that an arbitrary encoded message is a supported camera operation.
"""

from __future__ import annotations

from binascii import crc_hqx
from dataclasses import dataclass
import struct


CRC_INITIAL = 0xEF4A
KCP_PUSH, KCP_ACK, KCP_WINDOW_ASK, KCP_WINDOW_TELL = 81, 82, 83, 84
_KCP_HEADER = struct.Struct("<IBBHIIII")
_RPC_HEADER = struct.Struct("<BHHBI")
_MASK = 0xFFFFFFFF


def _unsigned(value: int, bits: int) -> int:
    if not isinstance(value, int) or not 0 <= value < 1 << bits:
        raise ValueError(f"Expected an unsigned {bits}-bit integer")
    return value


@dataclass(frozen=True)
class Envelope:
    kind: int
    source: int
    destination: int
    payload: bytes

    def encode(self) -> bytes:
        prefix = struct.pack("<BHH", _unsigned(self.kind, 8),
                             _unsigned(self.source, 16), _unsigned(self.destination, 16))
        prefix += _unsigned(len(self.payload), 24).to_bytes(3, "little")
        checksums = struct.pack("<HH", crc_hqx(prefix + bytes(4), CRC_INITIAL),
                                crc_hqx(self.payload, CRC_INITIAL))
        return prefix + checksums + self.payload


def decode_envelope(data: bytes) -> Envelope:
    """Decode exactly one envelope; reject trailing bytes and both CRC failures."""
    if len(data) < 12:
        raise ValueError("Truncated screen envelope")
    if int.from_bytes(data[5:8], "little") != len(data) - 12:
        raise ValueError("Screen envelope length mismatch")
    header_crc, payload_crc = struct.unpack_from("<HH", data, 8)
    if crc_hqx(data[:8] + bytes(4), CRC_INITIAL) != header_crc:
        raise ValueError("Screen envelope header CRC mismatch")
    if crc_hqx(data[12:], CRC_INITIAL) != payload_crc:
        raise ValueError("Screen envelope payload CRC mismatch")
    kind, source, destination = struct.unpack_from("<BHH", data)
    return Envelope(kind, source, destination, data[12:])


@dataclass(frozen=True)
class RPC:
    version: int
    service: int
    method: int
    category: int
    identifier: int
    body: bytes


def decode_rpc(envelope: Envelope) -> RPC:
    """Read the observed ordinary RPC header; preserve unknown service/flag values."""
    if envelope.kind != 0:
        raise ValueError("This envelope is not an ordinary RPC message")
    if len(envelope.payload) < _RPC_HEADER.size:
        raise ValueError("Truncated screen RPC header")
    fields = _RPC_HEADER.unpack_from(envelope.payload)
    return RPC(*fields, envelope.payload[_RPC_HEADER.size:])


@dataclass(frozen=True)
class KCPSegment:
    conversation: int
    command: int
    fragments_remaining: int
    window: int
    timestamp: int
    sequence: int
    next_unacknowledged: int
    payload: bytes


def decode_kcp_datagram(data: bytes) -> tuple[KCPSegment, ...]:
    """Split all KCP segments in one datagram; call separately for direct bootstrap."""
    segments = []
    position = 0
    while position < len(data):
        if len(data) - position < _KCP_HEADER.size:
            raise ValueError("Truncated KCP header")
        fields = _KCP_HEADER.unpack_from(data, position)
        size = fields[-1]
        position += _KCP_HEADER.size
        if fields[1] not in (KCP_PUSH, KCP_ACK, KCP_WINDOW_ASK, KCP_WINDOW_TELL):
            raise ValueError("Unknown KCP command")
        if size > len(data) - position:
            raise ValueError("Truncated KCP payload")
        segments.append(KCPSegment(*fields[:-1], data[position:position + size]))
        position += size
    return tuple(segments)


@dataclass(frozen=True)
class CapturedMessage:
    first_sequence: int
    last_sequence: int
    envelope: Envelope
    raw: bytes


@dataclass(frozen=True)
class Assembly:
    messages: tuple[CapturedMessage, ...]
    incomplete_groups: int
    invalid_envelopes: int
    conflicting_groups: int
    duplicate_pushes: int


class CaptureAssembler:
    """Collect ONE conversation, direction, and logical session from an offline take.

    Handles reordering, retries, fragmentation and sequence wrap in a capture
    spanning less than half the 32-bit sequence space. A radio reconnect does not
    necessarily start a new KCP session. Reset explicitly at a logical restart.
    Missing prefixes are rejected by exact envelope length and both CRCs, even
    when a contiguous suffix reaches fragment zero. No missing data is invented.
    """

    def __init__(self, conversation: int):
        self.conversation = _unsigned(conversation, 32)
        self._pushes: dict[int, KCPSegment] = {}
        self._conflicts: set[int] = set()
        self._anchor: int | None = None
        self.duplicate_pushes = 0

    def add(self, segment: KCPSegment) -> None:
        if segment.conversation != self.conversation:
            raise ValueError("Do not combine different KCP conversations")
        if segment.command != KCP_PUSH:
            return
        _unsigned(segment.sequence, 32)
        _unsigned(segment.fragments_remaining, 8)
        if self._anchor is None:
            self._anchor = segment.sequence
        previous = self._pushes.get(segment.sequence)
        if previous is not None:
            if (previous.fragments_remaining, previous.payload) == (
                    segment.fragments_remaining, segment.payload):
                self.duplicate_pushes += 1
            else:
                self._conflicts.add(segment.sequence)
            return
        self._pushes[segment.sequence] = segment

    def assemble(self) -> Assembly:
        groups: dict[int, dict[int, KCPSegment]] = {}
        for segment in self._pushes.values():
            end = (segment.sequence + segment.fragments_remaining) & _MASK
            groups.setdefault(end, {})[segment.fragments_remaining] = segment
        anchor = self._anchor or 0
        ordered = sorted(groups, key=lambda end: ((end - anchor + (1 << 31)) & _MASK) - (1 << 31))
        messages = []
        incomplete = invalid = conflicts = 0
        for end in ordered:
            group = groups[end]
            if any(segment.sequence in self._conflicts for segment in group.values()):
                conflicts += 1
                continue
            fragments = max(group) + 1
            if len(group) != fragments or 0 not in group:
                incomplete += 1
                continue
            raw = b"".join(group[index].payload for index in range(fragments - 1, -1, -1))
            try:
                envelope = decode_envelope(raw)
            except ValueError:
                invalid += 1
                continue
            messages.append(CapturedMessage(group[fragments - 1].sequence, end, envelope, raw))
        return Assembly(tuple(messages), incomplete, invalid, conflicts, self.duplicate_pushes)


def observed_h264_access_unit(message: CapturedMessage) -> bytes:
    """Extract only the measured media layout, not arbitrary H.264 in other RPCs.

    An access unit is not necessarily independently decodable: the captured
    stream may lack SPS/PPS, references, or frames lost elsewhere in the take.
    """
    rpc = decode_rpc(message.envelope)
    if (rpc.version, rpc.service, rpc.method, rpc.category) != (1, 2, 3, 1):
        raise ValueError("Unrecognized screen video RPC layout")
    if len(message.raw) < 108:
        raise ValueError("Truncated screen video message")
    payload = message.raw[102:]
    if int.from_bytes(message.raw[98:102], "little") != len(payload):
        raise ValueError("Screen video length mismatch")
    if not payload.startswith(b"\x00\x00\x00\x01\x09"):
        raise ValueError("Expected the observed H.264 access-unit delimiter")
    return payload
