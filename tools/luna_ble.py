#!/usr/bin/env python3
"""Authorized Luna BLE bootstrap lab; writes credentials only to private local files.

Run from any directory; paths are anchored to this repository. Requires the lab
venv. Only --authorize requests on-camera approval; normal runs reuse our identity.
Raw wire logs contain private identifiers. ECDH private/session keys are not saved.
"""

import argparse
import asyncio
import hashlib
import json
import os
import struct
import tempfile
import uuid
from datetime import datetime, timezone
from pathlib import Path

from bleak import BleakClient, BleakScanner
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

from luna_wire import (blob, complete_key_exchange, decode_message, encode_frame,
                       encryption_schemes, integer, one, options)
from ucd2 import Reassembler

ROOT = Path(__file__).resolve().parent.parent
SERVICE = "0000be80-0000-1000-8000-00805f9b34fb"
WRITE = "0000be81-0000-1000-8000-00805f9b34fb"
NOTIFY = "0000be82-0000-1000-8000-00805f9b34fb"


def utc() -> str:
    return datetime.now(timezone.utc).isoformat()


def private_json(path: Path, value):
    """Atomic replacement also repairs permissions on an existing destination."""
    fd, temporary = tempfile.mkstemp(prefix=".luna-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as output:
            json.dump(value, output, indent=2)
            output.write("\n")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def client_identity(path: Path) -> str:
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        os.chmod(path, 0o600)
        identity = json.loads(path.read_text())["authorization_id"]
        if not isinstance(identity, str) or str(uuid.UUID(identity)).upper() != identity:
            raise ValueError("Invalid saved client identity; inspect the local identity file")
        return identity
    identity = str(uuid.uuid4()).upper()
    with os.fdopen(fd, "w") as output:
        json.dump({"authorization_id": identity}, output)
    return identity


class Session:
    def __init__(self, client, folder: Path):
        self.client = client
        self.parser = Reassembler()
        self.pending = {}
        self.approvals = asyncio.Queue(maxsize=16)
        self.first = asyncio.Event()
        self.key = None
        self.failure = None
        self.message_id = self.sequence = self.received = 0
        self.transcript = []
        self.log = (folder / "wire.jsonl").open("x")
        os.fchmod(self.log.fileno(), 0o600)

    def record(self, direction: str, data: bytes):
        self.log.write(json.dumps({"utc": utc(), "direction": direction,
                                   "hex": bytes(data).hex()}) + "\n")
        self.log.flush()

    def event(self, direction: str, code: int, identifier: int, body: bytes, encrypted: bool):
        self.transcript.append({"utc": utc(), "direction": direction, "code": code,
                                "id": identifier, "body_bytes": len(body), "encrypted": encrypted})
        print(f"{direction} code {code} id {identifier} body_bytes {len(body)} encrypted {encrypted}",
              flush=True)

    def receive(self, characteristic, data):
        self.received += 1
        self.record("camera-to-client", data)
        self.first.set()
        try:
            for frame in self.parser.feed(bytes(data)):
                message = decode_message(frame, self.key)
                if message is None:
                    continue
                if message.content_type != 2:
                    raise ValueError("Unexpected response content type")
                self.event("RX", message.code, message.identifier, message.body, frame.scheme3_encrypted)
                pending = self.pending.get(message.identifier)
                if pending is not None and message.code in (200, 500):
                    future, encrypted = pending
                    if frame.scheme3_encrypted != encrypted:
                        raise ValueError("Response encryption does not match request")
                    if not future.done():
                        future.set_result(message)
                elif message.code in (8209, 8228):
                    self.approvals.put_nowait(message)
        except Exception as error:
            self.failure = error
            for future, _ in self.pending.values():
                if not future.done():
                    future.set_exception(error)

    async def request(self, code: int, body: bytes = b"", encrypted: bool = False) -> bytes:
        if self.failure is not None:
            raise self.failure
        if encrypted and self.key is None:
            raise ValueError("No negotiated key")
        self.message_id = self.message_id % 0x3FFFFFFE + 1
        self.sequence = (self.sequence + 1) & 255
        identifier = self.message_id
        payload = struct.pack("<HBIH", code, 2, identifier | 0x80000000, 0) + body
        packet = encode_frame(self.sequence, payload, self.key if encrypted else None)
        future = asyncio.get_running_loop().create_future()
        self.pending[identifier] = (future, encrypted)
        self.event("TX", code, identifier, body, encrypted)
        try:
            # Conservative source-backed chunk size; not a measured Luna MTU limit.
            for offset in range(0, len(packet), 206):
                chunk = packet[offset:offset + 206]
                self.record("client-to-camera", chunk)
                await asyncio.wait_for(self.client.write_gatt_char(WRITE, chunk, response=True), 10)
            response = await asyncio.wait_for(future, 10)
            if response.code != 200:
                raise RuntimeError(f"Camera response {response.code} to command {code}")
            return response.body
        finally:
            self.pending.pop(identifier, None)
            # Consume an exception if the ATT write failed before awaiting its reply.
            if future.done() and not future.cancelled():
                future.exception()
            elif not future.done():
                future.cancel()


async def bootstrap(name: str, authorize: bool) -> int:
    local = ROOT / ".local"
    local.mkdir(mode=0o700, exist_ok=True)
    captures = ROOT / "captures"
    captures.mkdir(mode=0o700, exist_ok=True)
    folder = captures / (datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ") + "-luna-ble")
    folder.mkdir(mode=0o700)
    print("Session:", folder.relative_to(ROOT), flush=True)
    summary = {"started_utc": utc(), "state": "scanning", "initiator": 1,
               "tool_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
               "codec_sha256": hashlib.sha256((ROOT / "tools/luna_wire.py").read_bytes()).hexdigest()}
    session = None
    try:
        identity = client_identity(local / "luna-client-identity.json")
        device = await BleakScanner.find_device_by_filter(
            lambda device, advert: advert.local_name == name and SERVICE in advert.service_uuids,
            timeout=20)
        if device is None:
            raise RuntimeError("Camera not found by exact advertised name and BE80 service")
        async with BleakClient(device, timeout=20) as client:
            gatt = [{"uuid": service.uuid, "handle": service.handle, "characteristics": [
                {"uuid": item.uuid, "handle": item.handle, "properties": item.properties,
                 "descriptors": [{"uuid": descriptor.uuid, "handle": descriptor.handle}
                                 for descriptor in item.descriptors]}
                for item in service.characteristics]} for service in client.services]
            private_json(folder / "gatt.json", gatt)
            for characteristic, required in ((WRITE, "write"), (NOTIFY, "notify")):
                item = client.services.get_characteristic(characteristic)
                if item is None or required not in item.properties:
                    raise RuntimeError("GATT fingerprint mismatch")
            summary.update(state="connected", mtu=client.mtu_size)
            session = Session(client, folder)
            await client.start_notify(NOTIFY, session.receive)
            try:
                await asyncio.wait_for(session.first.wait(), 5)
            except asyncio.TimeoutError:
                print("No initial notification; trying device-info request", flush=True)

            info = one(await session.request(8, options([48, 15, 30])), 2)
            model = one(info, 48, b"").decode()
            firmware = one(info, 30, b"").decode()
            if model != "Insta360 Luna Ultra":
                raise RuntimeError("Unexpected camera model; stopping bootstrap")
            summary.update(state="identity-read", model=model, firmware=firmware)
            print("Camera:", model, firmware, flush=True)
            schemes = encryption_schemes(await session.request(240))
            summary["schemes"] = schemes
            if 3 not in schemes:
                raise RuntimeError("Camera does not offer encryption scheme 3")

            private = ec.generate_private_key(ec.SECP256R1())
            public = private.public_key().public_bytes(Encoding.X962, PublicFormat.UncompressedPoint)
            reply = await session.request(241, integer(1, 3) + blob(2, public))
            summary["key_exchange_field1"] = one(reply, 1, 0)
            session.key = complete_key_exchange(private, reply)
            summary["state"] = "key-negotiated"
            encrypted_info = one(await session.request(8, options([48, 30]), encrypted=True), 2)
            if one(encrypted_info, 48, b"").decode() != model:
                raise RuntimeError("Encrypted identity response mismatch")
            summary["encrypted_identity_read"] = True
            print("Fresh encryption session verified with device-info read", flush=True)

            # Mirrors observed iPhone initiator (1), with our own UUID in both ID fields.
            summary["state"] = "checking-authorization"
            auth = await session.request(39, blob(1, identity.encode()) + integer(2, 1)
                                         + blob(3, identity.encode()))
            status = one(auth, 1, 0)
            summary["authorization_status"] = status
            print("Own identity authorization status:", status, flush=True)
            if status == 1:
                if not authorize:
                    summary["state"] = "needs-camera-approval"
                    print("New client: rerun with --authorize and accept on the camera", flush=True)
                    return 2
                await session.request(86, integer(1, 1))
                summary["state"] = "awaiting-camera-approval"
                print("WAITING: accept this client's connection on the Luna touchscreen", flush=True)
                async with asyncio.timeout(120):
                    while True:
                        message = await session.approvals.get()
                        result, operation = one(message.body, 1, 0), one(message.body, 2, 0)
                        if operation not in (0, 1):
                            continue
                        summary.update(approval_code=message.code, approval_result=result,
                                       approval_operation=operation)
                        if result != 0:
                            raise RuntimeError(f"Camera authorization failed with result {result}")
                        break
            elif status != 0:
                raise RuntimeError("Unexpected authorization status")

            summary["state"] = "reading-wifi-credentials"
            wifi = one(await session.request(8, options([36, 37, 43]), encrypted=True), 2)
            information = one(wifi, 36)
            ssid, password = one(information, 1), one(information, 2)
            if not isinstance(ssid, bytes) or not ssid or not isinstance(password, bytes) or not password:
                raise RuntimeError("No Wi-Fi credentials in reply")
            private_json(local / "luna-wifi.json", {"ssid": ssid.decode(), "password": password.decode(),
                         "camera_model": model, "firmware": firmware, "retrieved_utc": utc()})
            summary.update(state="wifi-credentials-read", ssid_bytes=len(ssid), password_bytes=len(password))
            print("SUCCESS: encrypted Wi-Fi credentials saved privately; BLE session closing", flush=True)
            return 0
    except Exception as error:
        # Avoid exception strings that could embed private device responses.
        summary.update(failed_stage=summary["state"], state="error", error_type=type(error).__name__)
        print("FAILED:", type(error).__name__, "during", summary["failed_stage"], flush=True)
        return 1
    finally:
        if session is not None:
            summary.update(notifications=session.received, bad_checksums=session.parser.bad_checksums,
                           rejected_headers=session.parser.rejected_headers,
                           pending_receive_bytes=len(session.parser.pending),
                           receive_error=type(session.failure).__name__ if session.failure else None)
            session.key = None
            session.log.close()
            private_json(folder / "transcript.json", session.transcript)
            summary["wire_sha256"] = hashlib.sha256((folder / "wire.jsonl").read_bytes()).hexdigest()
        summary["finished_utc"] = utc()
        private_json(folder / "summary.json", summary)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True, help="Exact observed BE80 advertisement name")
    parser.add_argument("--authorize", action="store_true", help="Request approval for our saved client ID")
    args = parser.parse_args()
    try:
        return asyncio.run(bootstrap(args.name, args.authorize))
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
