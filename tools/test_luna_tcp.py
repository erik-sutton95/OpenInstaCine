"""Local simulated-camera integration; no hardware or camera secrets used."""

import asyncio
import json
import struct
import tempfile
import unittest
from pathlib import Path

from luna_tcp import LIVE_BODY, PREFIX, capture, heartbeat
from luna_wire import blob, encode_frame, integer
from ucd2 import Reassembler, checksum


class TCPTests(unittest.IsolatedAsyncioTestCase):
    async def simulate(self, authorized):
        requests = []
        video = bytes.fromhex("00000001260100010203")  # Synthetic NAL, not a decodable picture.

        async def camera(reader, writer):
            try:
                self.assertEqual(await reader.readexactly(len(PREFIX)), PREFIX)
                writer.write(heartbeat(1))
                await writer.drain()
                parser = Reassembler()
                while data := await reader.read(65536):
                    for frame in parser.feed(data):
                        message = frame.plain_message()
                        if message is None:
                            continue
                        requests.append(message)
                        body = b""
                        if message.code == 8:
                            body = blob(2, blob(48, b"Insta360 Luna Ultra") + blob(30, b"test-only"))
                        elif message.code == 39:
                            body = integer(1, 0 if authorized else 1)
                        packet = encode_frame(1, struct.pack("<HBIH", 200, 2, message.identifier, 0) + body)
                        if message.code == 1:
                            payload = b"\x20" + (1000).to_bytes(8, "little") + video
                            media = b"UCD2" + bytes([1, 12, 1, 2]) + struct.pack("<I", len(payload)) + payload
                            packet += media + checksum(media).to_bytes(4, "little")
                        # Fragment the greeting-adjacent responses and coalesce live ack/media.
                        writer.write(packet[:7])
                        await writer.drain()
                        writer.write(packet[7:])
                        await writer.drain()
            finally:
                writer.close()
                await writer.wait_closed()

        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            server = await asyncio.start_server(camera, "127.0.0.1", 0)
            async with server:
                result = await capture(folder, "00000000-0000-4000-8000-000000000001",
                                       host="127.0.0.1", port=server.sockets[0].getsockname()[1], seconds=1)
            saved_video = (folder / "preview.hevc").read_bytes()
            self.assertEqual(json.loads((folder / "summary.json").read_text())["state"], result["state"])
        return result, requests, saved_video, video

    async def test_authorized_capture_extracts_video_and_stops(self):
        result, requests, saved, video = await self.simulate(True)
        self.assertEqual(result["state"], "preview-captured")
        self.assertEqual([m.code for m in requests], [8, 39, 15, 1, 2])
        self.assertEqual(requests[3].body, LIVE_BODY)
        self.assertEqual(saved, video)
        self.assertTrue(result["stop_acknowledged"])
        self.assertEqual(result["bad_checksums"], 0)

    async def test_unauthorized_camera_never_receives_live_start(self):
        result, requests, saved, _ = await self.simulate(False)
        self.assertEqual((result["state"], result["failed_stage"]), ("error", "authorization"))
        self.assertEqual([m.code for m in requests], [8, 39])
        self.assertFalse(saved)


if __name__ == "__main__":
    unittest.main()
