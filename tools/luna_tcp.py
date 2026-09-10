#!/usr/bin/env python3
"""Bounded Luna TCP preview lab. Requires an already joined camera Wi-Fi network.

Uses our saved BLE-authorized identity. Sends device/status reads, live start/stop
and heartbeats; never record/delete/format commands. Capture files remain private.
Network and media leads: docs/research/luna-reconnect-2026-09-11.md.
"""

import argparse
import asyncio
import contextlib
import hashlib
import json
import os
import struct
import time
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

from luna_wire import blob, encode_frame, integer, one, options
from ucd2 import Reassembler, checksum

ROOT = Path(__file__).resolve().parent.parent
PREFIX = bytes.fromhex("11000000060000affaaffaaffaaffaaffa")
LIVE_BODY = bytes.fromhex("10012080f702382b500e6001")


def utc():
    return datetime.now(timezone.utc).isoformat()


def heartbeat(sequence):
    packet = b"UCD2" + bytes([1, 12, 5, sequence]) + bytes(4)
    return packet + checksum(packet).to_bytes(4, "little")


class Session:
    def __init__(self, reader, writer, folder):
        self.reader, self.writer = reader, writer
        self.parser = Reassembler()
        self.pending = {}
        self.greeting = asyncio.Event()
        self.message_id = self.sequence = 0
        self.failure = None
        self.frames, self.media, self.tick_deltas = Counter(), Counter(), Counter()
        self.first_video = self.last_video = self.last_tick = None
        self.rx = (folder / "camera.bin").open("xb")
        self.tx = (folder / "client.bin").open("xb")
        self.video = (folder / "preview.hevc").open("xb")
        self.events = (folder / "events.jsonl").open("x")
        self.media_events = (folder / "media.jsonl").open("x")

    def event(self, direction, message):
        self.events.write(json.dumps({"utc": utc(), "direction": direction,
                          "code": message.code, "id": message.identifier,
                          "body_bytes": len(message.body)}) + "\n")

    async def receive(self):
        try:
            while data := await self.reader.read(65536):
                self.rx.write(data)
                for frame in self.parser.feed(data):
                    self.frames[frame.frame_type] += 1
                    if frame.frame_type == 5:
                        self.greeting.set()
                    elif frame.frame_type == 1:
                        payload = frame.payload
                        if len(payload) < 9:
                            raise ValueError("Short media payload")
                        subtype, tick = payload[0], int.from_bytes(payload[1:9], "little")
                        self.media[subtype] += 1
                        self.media_events.write(json.dumps({"utc": utc(), "subtype": subtype,
                                                "tick": tick, "bytes": len(payload) - 9}) + "\n")
                        if subtype == 0x20:
                            now = time.monotonic()
                            self.first_video = self.first_video or now
                            self.last_video = now
                            if self.last_tick is not None:
                                self.tick_deltas[tick - self.last_tick] += 1
                            self.last_tick = tick
                            self.video.write(payload[9:])
                    elif frame.frame_type == 4:
                        message = frame.plain_message()
                        if message is None:
                            raise ValueError("Unexpected encrypted TCP response")
                        self.event("RX", message)
                        future = self.pending.get(message.identifier)
                        if future is not None and message.code in (200, 500) and not future.done():
                            future.set_result(message)
            raise ConnectionError("Camera closed TCP")
        except Exception as error:
            self.failure = error
            self.greeting.set()  # Wake startup so EOF is not reported as a greeting timeout.
            for future in self.pending.values():
                if not future.done():
                    future.set_exception(error)

    async def send(self, packet):
        if self.failure is not None:
            raise self.failure
        self.tx.write(packet)
        self.tx.flush()
        self.writer.write(packet)
        await asyncio.wait_for(self.writer.drain(), 8)

    def next_sequence(self):
        self.sequence = (self.sequence + 1) & 255
        return self.sequence

    async def keepalive(self):
        try:
            while True:
                await self.send(heartbeat(self.next_sequence()))
                await asyncio.sleep(2)
        except Exception as error:
            self.failure = error

    async def request(self, code, body=b""):
        self.message_id += 1
        identifier = self.message_id
        packet = encode_frame(self.next_sequence(),
                              struct.pack("<HBIH", code, 2, identifier | 0x80000000, 0) + body)
        self.event("TX", Reassembler().feed(packet)[0].plain_message())
        future = asyncio.get_running_loop().create_future()
        self.pending[identifier] = future
        print(f"TX {code} id {identifier}", flush=True)
        try:
            await self.send(packet)
            reply = await asyncio.wait_for(future, 8)
            print(f"RX {reply.code} id {identifier} body_bytes {len(reply.body)}", flush=True)
            if reply.code != 200:
                raise RuntimeError(f"Camera rejected command {code}")
            return reply.body
        finally:
            self.pending.pop(identifier, None)
            if future.done() and not future.cancelled():
                future.exception()
            elif not future.done():
                future.cancel()

    def close_files(self):
        for output in (self.rx, self.tx, self.video, self.events, self.media_events):
            output.close()


async def capture(folder, identity, host="192.168.42.1", port=6666, seconds=20, transport="socket"):
    summary = {"started_utc": utc(), "state": "tcp-connect", "transport": transport,
               "requested_seconds": seconds}
    session = process = None
    tasks = []
    start_attempted = False
    try:
        if transport == "netcat":
            process = await asyncio.create_subprocess_exec(
                "/usr/bin/nc", "-G", "6", host, str(port), stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
            reader, writer = process.stdout, process.stdin
        else:
            reader, writer = await asyncio.wait_for(asyncio.open_connection(host, port), 6)
            summary["local_address"] = writer.get_extra_info("sockname")[0]
        session = Session(reader, writer, folder)
        tasks.append(asyncio.create_task(session.receive()))
        summary["state"] = "greeting"
        await session.send(PREFIX)
        await asyncio.wait_for(session.greeting.wait(), 8)
        if session.failure:
            raise session.failure
        tasks.append(asyncio.create_task(session.keepalive()))
        summary["state"] = "device-info"
        info = one(await session.request(8, options([48, 30])), 2)
        model, firmware = one(info, 48, b"").decode(), one(info, 30, b"").decode()
        if model != "Insta360 Luna Ultra":
            raise RuntimeError("Unexpected camera model")
        summary.update(model=model, firmware=firmware)
        summary["state"] = "authorization"
        encoded_identity = identity.encode()
        auth = await session.request(39, blob(1, encoded_identity) + integer(2, 1)
                                     + blob(3, encoded_identity))
        summary["authorization_status"] = one(auth, 1, 0)
        if summary["authorization_status"] != 0:
            raise RuntimeError("Saved identity is not authorized over TCP")
        summary["state"] = "capture-status"
        (folder / "capture-status.pb").write_bytes(await session.request(15))
        summary["state"] = "live-start"
        start_attempted = True
        await session.request(1, LIVE_BODY)
        summary["state"] = "receiving-preview"
        for elapsed in range(seconds):
            await asyncio.sleep(1)
            if session.failure:
                raise session.failure
            if (elapsed + 1) % 5 == 0:
                print(f"Preview {elapsed + 1}s; video packets {session.media[0x20]}", flush=True)
        summary["state"] = "live-stop"
        await session.request(2)
        start_attempted = False
        summary["stop_acknowledged"] = True
        if not session.media[0x20]:
            raise RuntimeError("No video media received")
        summary["state"] = "preview-captured"
    except Exception as error:
        summary.update(failed_stage=summary["state"], state="error", error_type=type(error).__name__)
        if isinstance(error, OSError):
            summary["errno"] = error.errno
        print("FAILED:", summary["error_type"], "during", summary["failed_stage"], flush=True)
    finally:
        if session:
            if start_attempted:
                try:
                    await session.request(2)
                    summary["cleanup_stop_acknowledged"] = True
                except Exception:
                    summary["cleanup_stop_acknowledged"] = False
            for task in tasks:
                task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)
            session.writer.close()
            with contextlib.suppress(Exception):
                await asyncio.wait_for(session.writer.wait_closed(), 3)
            summary.update(frame_types=dict(session.frames), media_subtypes=dict(session.media),
                           bad_checksums=session.parser.bad_checksums,
                           rejected_headers=session.parser.rejected_headers,
                           pending_receive_bytes=len(session.parser.pending),
                           receive_error=type(session.failure).__name__ if session.failure else None,
                           video_interval_seconds=(session.last_video - session.first_video
                                                   if session.first_video else None),
                           video_tick_deltas=dict(session.tick_deltas))
            session.close_files()
        if process:
            if process.returncode is None:
                with contextlib.suppress(ProcessLookupError):
                    process.terminate()
            with contextlib.suppress(asyncio.TimeoutError):
                await asyncio.wait_for(process.wait(), 3)
            if process.returncode is None:
                process.kill()
                await process.wait()
            summary["transport_exit"] = process.returncode
            (folder / "transport-stderr.txt").write_bytes(await process.stderr.read())
        summary["finished_utc"] = utc()
        summary["sha256"] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                             for p in folder.iterdir() if p.is_file()}
        (folder / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="192.168.42.1")
    parser.add_argument("--seconds", type=int, default=20)
    parser.add_argument("--transport", choices=("socket", "netcat"), default="socket",
                        help="netcat uses macOS /usr/bin/nc for TCP I/O")
    args = parser.parse_args()
    if not 1 <= args.seconds <= 60:
        parser.error("--seconds must be between 1 and 60")
    identity_file = ROOT / ".local/luna-client-identity.json"
    if not identity_file.exists():
        parser.error("Run the BLE authorization lab first")
    identity = json.loads(identity_file.read_text())["authorization_id"]
    os.umask(0o077)
    folder = ROOT / "captures" / (datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ") + "-luna-tcp")
    folder.mkdir(parents=True, mode=0o700)
    print("Session:", folder.relative_to(ROOT), flush=True)
    try:
        summary = asyncio.run(capture(folder, identity, host=args.host,
                                      seconds=args.seconds, transport=args.transport))
    except KeyboardInterrupt:
        return 130
    print("Result:", summary["state"], flush=True)
    return 0 if summary["state"] == "preview-captured" else 1


if __name__ == "__main__":
    raise SystemExit(main())
