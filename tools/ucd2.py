"""Read-only UCD2 framing helpers for local capture analysis.

Wire layout and checksum provenance: docs/research/insta360-protocol-sources.md.
This module does not transmit commands, decrypt sessions, or infer camera support.
"""

from dataclasses import dataclass
import struct


def _checksum_table() -> tuple[int, ...]:
    result = []
    for byte in range(256):
        value = byte << 24
        for _ in range(8):
            value = ((value << 1) ^ (0x04C11DB7 if value & 0x80000000 else 0)) & 0xFFFFFFFF
        result.append(value)
    return tuple(result)


_CHECKSUM_TABLE = _checksum_table()


def checksum(data: bytes) -> int:
    """UCD2 word-fed checksum: four byte-table rounds per input byte, not CRC-32."""
    value = 0xFFFFFFFF
    table = _CHECKSUM_TABLE
    for byte in data:
        value ^= byte
        for _ in range(4):
            value = ((value << 8) & 0xFFFFFFFF) ^ table[value >> 24]
    return value


@dataclass(frozen=True)
class Message:
    """Plain MESSAGE header; raw flags remain available without guessing semantics."""

    code: int
    content_type: int
    identifier: int
    identifier_flags: int
    reserved: bytes
    body: bytes


@dataclass(frozen=True)
class Frame:
    """One checksum-valid frame; payload may be ciphertext or media."""

    raw: bytes

    @property
    def frame_type(self) -> int:
        return self.raw[6]

    @property
    def sequence(self) -> int:
        return self.raw[7]

    @property
    def header_length(self) -> int:
        return self.raw[5]

    @property
    def payload(self) -> bytes:
        return self.raw[self.header_length:-4]

    @property
    def scheme3_encrypted(self) -> bool:
        return self.header_length == 43 and self.raw[12:15] == bytes.fromhex("40 1d 03")

    def plain_message(self) -> Message | None:
        """Return only a known plain message; never interpret ciphertext as a command."""
        if self.frame_type != 4 or self.header_length != 12:
            return None
        data = self.payload
        if len(data) < 9:
            raise ValueError("Plain MESSAGE is shorter than its nine-byte inner header.")
        tagged_id = int.from_bytes(data[3:7], "little")
        return Message(int.from_bytes(data[:2], "little"), data[2],
                       tagged_id & 0x3FFFFFFF, tagged_id & 0xC0000000,
                       data[7:9], data[9:])


class Reassembler:
    """Reassemble a single ordered, directional stream, retaining incomplete tails.

    Allocate separately for each connection and direction; reset at disconnect.
    Feed only transport payloads after retransmission handling. Frame count alone
    is not command success. The size limit is an analysis safeguard, not a camera
    limit; increase explicitly when inspecting larger media frames.
    """

    def __init__(self, max_frame_size: int = 4 * 1024 * 1024):
        if max_frame_size < 16:
            raise ValueError("Frame size limit must allow the minimum UCD2 frame.")
        self.max_frame_size = max_frame_size
        self.pending = bytearray()
        self.rejected_headers = 0
        self.bad_checksums = 0
        self.discarded_bytes = 0

    def _discard(self, count: int):
        del self.pending[:count]
        self.discarded_bytes += count

    def feed(self, chunk: bytes) -> list[Frame]:
        self.pending.extend(chunk)
        frames = []
        while len(self.pending) >= 4:
            start = self.pending.find(b"UCD2")
            if start < 0:
                self._discard(len(self.pending) - 3)
                break
            if start:
                self._discard(start)
            if len(self.pending) < 12:
                break
            header_length = self.pending[5]
            payload_length = struct.unpack_from("<I", self.pending, 8)[0]
            total = header_length + payload_length + 4
            if self.pending[4] != 1 or header_length < 12 or total > self.max_frame_size:
                self.rejected_headers += 1
                self._discard(1)
                continue
            if len(self.pending) < total:
                break
            raw = bytes(self.pending[:total])
            if checksum(raw[:-4]) != int.from_bytes(raw[-4:], "little"):
                self.bad_checksums += 1
                self._discard(1)
                continue
            frames.append(Frame(raw))
            del self.pending[:total]
        return frames
