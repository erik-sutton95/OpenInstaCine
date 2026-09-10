"""Offline framing tests; none establish support on local Luna hardware."""

import struct
import unittest

from ucd2 import Reassembler, checksum

# External captured fixture cited in docs/research/insta360-protocol-sources.md.
# It has no identifier unique to the owner and contains no camera credentials.
GET_OPTIONS = bytes.fromhex(
    "55 43 44 32 01 0c 04 10 0f 00 00 00 "
    "08 00 02 01 00 00 80 00 00 08 30 08 0f 08 0b 7c 00 8e 7c"
)

# Local Luna v1.0.288 capture, IP frames 144156 and 144402. Reviewed fixtures:
# only protocol headers, generic live settings and checksums; no device/client IDs.
LUNA_GREETING = bytes.fromhex("55434432010c050100000000112834b2")
LUNA_LIVE_START = bytes.fromhex(
    "55434432010c0452150000000100024d000080000010012080f702382b500e6001e497c1ce"
)


def synthetic_frame(kind=4, payload=b"", extension=b""):
    """Test-only builder; synthetic fixtures are not hardware observations."""
    packet = b"UCD2" + bytes([1, 12 + len(extension), kind, 0])
    packet += struct.pack("<I", len(payload)) + extension + payload
    return packet + checksum(packet).to_bytes(4, "little")


class FramingTests(unittest.TestCase):
    def test_stream_sized_checksum_regression(self):
        # Independently computed by the prior 32-bit-round implementation.
        self.assertEqual(checksum(bytes(range(256)) * 256), 0x582A0F28)

    def test_local_luna_greeting_and_live_start(self):
        frames = Reassembler().feed(LUNA_GREETING + LUNA_LIVE_START)
        self.assertEqual([f.frame_type for f in frames], [5, 4])
        message = frames[1].plain_message()
        self.assertEqual((message.code, message.identifier), (1, 77))
        self.assertEqual(message.body, bytes.fromhex("10012080f702382b500e6001"))

    def test_external_checksum_and_message(self):
        self.assertEqual(checksum(GET_OPTIONS[:-4]), 0x7C8E007C)
        frame = Reassembler().feed(GET_OPTIONS)[0]
        message = frame.plain_message()
        self.assertEqual((message.code, message.identifier, message.identifier_flags),
                         (8, 1, 0x80000000))
        self.assertEqual(message.body, bytes.fromhex("08 30 08 0f 08 0b"))

    def test_every_split_and_concatenation(self):
        for split in range(1, len(GET_OPTIONS)):
            parser = Reassembler()
            self.assertEqual(parser.feed(GET_OPTIONS[:split]), [])
            frames = parser.feed(GET_OPTIONS[split:] + GET_OPTIONS)
            self.assertEqual([x.raw for x in frames], [GET_OPTIONS, GET_OPTIONS])
            self.assertFalse(parser.pending)

    def test_stream_greeting_does_not_discard_following_message(self):
        frames = Reassembler().feed(synthetic_frame(kind=5) + GET_OPTIONS)
        self.assertEqual([f.frame_type for f in frames], [5, 4])
        self.assertEqual(frames[1].plain_message().code, 8)

    def test_corruption_and_noise_recover(self):
        bad = bytearray(GET_OPTIONS)
        bad[21] ^= 1
        parser = Reassembler()
        frames = parser.feed(b"noise" + bad + GET_OPTIONS)
        self.assertEqual([f.raw for f in frames], [GET_OPTIONS])
        self.assertEqual(parser.bad_checksums, 1)
        self.assertGreater(parser.discarded_bytes, 5)

    def test_oversized_header_does_not_hold_following_frame(self):
        parser = Reassembler(max_frame_size=1024)
        header = b"UCD2" + bytes([1, 12, 4, 0]) + struct.pack("<I", 0xFFFFFFFF)
        self.assertEqual(parser.feed(header + GET_OPTIONS)[0].raw, GET_OPTIONS)
        self.assertEqual(parser.rejected_headers, 1)

    def test_encrypted_envelope_is_not_plaintext(self):
        extension = bytes.fromhex("40 1d 03") + bytes(12 + 16)
        frame = Reassembler().feed(synthetic_frame(payload=bytes(20), extension=extension))[0]
        self.assertTrue(frame.scheme3_encrypted)
        self.assertIsNone(frame.plain_message())

    def test_short_inner_message_is_rejected(self):
        frame = Reassembler().feed(synthetic_frame(payload=bytes(8)))[0]
        with self.assertRaises(ValueError):
            frame.plain_message()


if __name__ == "__main__":
    unittest.main()
