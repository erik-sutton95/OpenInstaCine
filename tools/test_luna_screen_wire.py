"""Synthetic offline corruption, capture-gap and sequence-wrap regressions."""

from dataclasses import replace
import struct
import unittest

from luna_screen_wire import (CaptureAssembler, Envelope, KCPSegment,
                              decode_envelope, decode_kcp_datagram, decode_rpc,
                              observed_h264_access_unit)
from luna_screen_capture import inspect_capture


def push(sequence, remaining, payload, conversation=0x001E0008):
    return KCPSegment(conversation, 81, remaining, 128, 123, sequence, 0, payload)


def datagram(segment):
    return struct.pack("<IBBHIIII", segment.conversation, segment.command,
                       segment.fragments_remaining, segment.window, segment.timestamp,
                       segment.sequence, segment.next_unacknowledged, len(segment.payload)) + segment.payload


class ScreenWireTests(unittest.TestCase):
    # Independently generated with a bit-at-a-time polynomial implementation,
    # not binascii or the codec. Routing/identifier values are synthetic.
    FIXTURE = bytes.fromhex("003412cdab11000052c963b1010b000100004030201003000000677569")

    def test_independent_fixture_and_rpc(self):
        envelope = decode_envelope(self.FIXTURE)
        self.assertEqual((envelope.kind, envelope.source, envelope.destination), (0, 0x1234, 0xABCD))
        self.assertEqual(envelope.encode(), self.FIXTURE)
        rpc = decode_rpc(envelope)
        self.assertEqual((rpc.version, rpc.service, rpc.method, rpc.category, rpc.identifier),
                         (1, 11, 1, 0, 0x10203040))
        self.assertEqual(rpc.body, b"\x03\x00\x00\x00gui")

    def test_every_single_byte_mutation_and_boundary_is_rejected(self):
        for offset in range(len(self.FIXTURE)):
            damaged = bytearray(self.FIXTURE)
            damaged[offset] ^= 1
            with self.subTest(offset=offset), self.assertRaises(ValueError):
                decode_envelope(bytes(damaged))
        for data in (b"", self.FIXTURE[:11], self.FIXTURE[:-1], self.FIXTURE + b"\x00"):
            with self.subTest(size=len(data)), self.assertRaises(ValueError):
                decode_envelope(data)

    def test_routing_and_payload_have_separate_integrity_checks(self):
        envelope = decode_envelope(self.FIXTURE)
        rerouted = replace(envelope, destination=3).encode()
        self.assertNotEqual(rerouted[8:10], self.FIXTURE[8:10])
        self.assertEqual(rerouted[10:12], self.FIXTURE[10:12])
        changed = replace(envelope, payload=envelope.payload[:-1] + b"x").encode()
        self.assertEqual(changed[8:10], self.FIXTURE[8:10])
        self.assertNotEqual(changed[10:12], self.FIXTURE[10:12])
        for envelope in (Envelope(256, 0, 0, b""), Envelope(0, -1, 0, b""),
                         Envelope(0, 0, 65536, b"")):
            with self.assertRaises(ValueError):
                envelope.encode()
        self.assertEqual(decode_envelope(Envelope(2, 1, 2, b"").encode()).payload, b"")
        with self.assertRaises(ValueError):
            decode_rpc(Envelope(2, 1, 2, bytes(13)))
        with self.assertRaises(ValueError):
            decode_rpc(Envelope(0, 1, 2, bytes(9)))

    def test_coalesced_kcp_segments_and_malformed_lengths(self):
        first = push(10, 0, self.FIXTURE)
        ack = replace(first, command=82, payload=b"")
        self.assertEqual(decode_kcp_datagram(datagram(first) + datagram(ack)), (first, ack))
        for data in (datagram(first)[:23], datagram(first)[:-1],
                     datagram(first) + b"x", datagram(replace(first, command=99))):
            with self.assertRaises(ValueError):
                decode_kcp_datagram(data)

    def test_out_of_order_retries_and_sequence_wrap(self):
        collector = CaptureAssembler(0x001E0008)
        chunks = [self.FIXTURE[:10], self.FIXTURE[10:20], self.FIXTURE[20:]]
        segments = [push(0xFFFFFFFE, 2, chunks[0]), push(0xFFFFFFFF, 1, chunks[1]),
                    push(0, 0, chunks[2])]
        for segment in (segments[1], segments[2], segments[0], replace(segments[0], timestamp=999)):
            collector.add(segment)
        collector.add(replace(segments[0], command=82, payload=b""))
        result = collector.assemble()
        self.assertEqual(result.duplicate_pushes, 1)
        self.assertEqual(len(result.messages), 1)
        self.assertEqual((result.messages[0].first_sequence, result.messages[0].last_sequence),
                         (0xFFFFFFFE, 0))
        self.assertEqual(result.messages[0].raw, self.FIXTURE)
        self.assertEqual(collector.assemble(), result)  # Reading a report does not accumulate counts.

    def test_missing_middle_missing_prefix_and_conflicts_never_emit_video(self):
        parts = [push(100, 2, self.FIXTURE[:10]), push(101, 1, self.FIXTURE[10:20]),
                 push(102, 0, self.FIXTURE[20:])]
        for selected, field in (([parts[0], parts[2]], "incomplete_groups"),
                                (parts[1:], "invalid_envelopes"),
                                (parts + [replace(parts[1], payload=b"corrupt")], "conflicting_groups")):
            collector = CaptureAssembler(0x001E0008)
            for segment in selected:
                collector.add(segment)
            result = collector.assemble()
            self.assertFalse(result.messages)
            self.assertEqual(getattr(result, field), 1)
        with self.assertRaises(ValueError):
            CaptureAssembler(7).add(parts[0])

    def test_video_layout_requires_valid_rpc_length_and_aud(self):
        unit = b"\x00\x00\x00\x01\x09\xf0\x00\x00\x00\x01\x41synthetic"
        rpc = struct.pack("<BHHBI", 1, 2, 3, 1, 7) + bytes(76) + struct.pack("<I", len(unit)) + unit
        envelope = Envelope(0, 0x07FC, 0x0BFB, rpc)
        collector = CaptureAssembler(8)
        collector.add(push(0, 0, envelope.encode(), conversation=8))
        message = collector.assemble().messages[0]
        self.assertEqual(observed_h264_access_unit(message), unit)
        with self.assertRaises(ValueError):
            observed_h264_access_unit(replace(message, raw=message.raw + b"x"))
        with self.assertRaises(ValueError):
            observed_h264_access_unit(replace(message, envelope=replace(envelope, kind=2)))

    def test_tsv_inspection_separates_flows_and_accounts_for_bad_packets(self):
        def row(data, source="192.0.2.1"):
            return f"1\t0\t{source}\t6002\t6023\t{data.hex()}\t1\t0\n"

        segment = push(10, 0, self.FIXTURE)
        # The other sender must never contaminate this direction's sequence space.
        rows = [row(datagram(segment)), row(datagram(segment)),
                row(datagram(replace(segment, payload=b"unrelated")), "192.0.2.2"),
                row(b"truncated"), row(Envelope(2, 1, 0, bytes(13)).encode()),
                row(datagram(replace(segment, conversation=99)))]
        report, video = inspect_capture(rows, "192.0.2.1", 6002, 6023, 0x001E0008)
        self.assertEqual(report["selected_datagrams"], 5)
        self.assertEqual(report["complete_crc_valid_messages"], 1)
        self.assertEqual(report["duplicate_pushes"], 1)
        self.assertEqual(report["invalid_or_unrecognized_datagrams"], 1)
        self.assertEqual(report["valid_direct_kind_2_envelopes"], 1)
        self.assertEqual(report["segments_from_other_conversations"], 1)
        self.assertFalse(video)
        with self.assertRaisesRegex(ValueError, "eight TSV fields"):
            inspect_capture(["wrong export\n"], "192.0.2.1", 6002, 6023, 8)


if __name__ == "__main__":
    unittest.main()
