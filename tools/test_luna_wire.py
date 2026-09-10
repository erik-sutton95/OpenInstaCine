"""Offline bootstrap regressions; all keys and payloads here are synthetic/public."""

import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

from luna_ble import Session, client_identity, private_json
from luna_wire import (blob, complete_key_exchange, decode_message, derive_key,
                       encode_frame, encryption_schemes, fields, integer, one, options, varint)
from ucd2 import Reassembler, checksum


# P-256 scalar 1 exchanged with the standard generator gives the generator's X.
# HMAC extract/expand and AES-GCM fixture independently generated with Node crypto /
# WebCrypto, not the Python codec. Nonce is fixed ONLY in this synthetic fixture.
SHARED = bytes.fromhex("6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296")
KEY = bytes.fromhex("25531003115702b3eb9e5327a35a97dd")
HEADER = bytes.fromhex("55434432012b04010d000000")
NONCE = bytes.fromhex("000102030405060708090a0b")
TAG = bytes.fromhex("7173624439c47060d937e9e93c8385a0")
CIPHERTEXT = bytes.fromhex("dd28d4cce260a45d70b8a9e399")
PAYLOAD = bytes.fromhex("c8000201000000000012020801")
PACKET = HEADER + bytes.fromhex("401d03") + NONCE + TAG + CIPHERTEXT


def validated(packet):
    return Reassembler().feed(packet + checksum(packet).to_bytes(4, "little"))[0]


class WireTests(unittest.TestCase):
    def test_independent_key_derivation_and_p256_vector(self):
        self.assertEqual(derive_key(SHARED), KEY)
        private = ec.derive_private_key(1, ec.SECP256R1())
        public = private.public_key().public_bytes(Encoding.X962, PublicFormat.UncompressedPoint)
        self.assertEqual(complete_key_exchange(private, integer(1, 1) + blob(2, public)), KEY)

    def test_key_exchange_rejects_unknown_failure_and_invalid_curve_point(self):
        private = ec.derive_private_key(1, ec.SECP256R1())
        public = private.public_key().public_bytes(Encoding.X962, PublicFormat.UncompressedPoint)
        for status in (0, 2, 3, 4, 5, 100):
            with self.subTest(status=status), self.assertRaises(ValueError):
                complete_key_exchange(private, integer(1, status) + blob(2, public))
        for public in (b"", b"\x04" + bytes(64), b"\x02" + bytes(32)):
            with self.subTest(public_length=len(public)), self.assertRaises(ValueError):
                complete_key_exchange(private, integer(1, 1) + blob(2, public))

    def test_independent_aes_gcm_fixture_in_both_directions(self):
        frame = validated(PACKET)
        message = decode_message(frame, KEY)
        self.assertEqual((message.code, message.identifier, message.body), (200, 1, bytes.fromhex("12020801")))
        with patch("luna_wire.os.urandom", return_value=NONCE):
            self.assertEqual(encode_frame(1, PAYLOAD, KEY), frame.raw)

    def test_gcm_rejects_tampering_even_with_valid_checksum(self):
        for offset in (7, 15, 27, 43):
            tampered = bytearray(PACKET)
            tampered[offset] ^= 1
            with self.subTest(offset=offset), self.assertRaises(InvalidTag):
                decode_message(validated(bytes(tampered)), KEY)
        with self.assertRaises(InvalidTag):
            decode_message(validated(PACKET), bytes(16))

    def test_bootstrap_protobuf_shapes_and_packed_capabilities(self):
        self.assertEqual(options([36, 37, 43]), bytes.fromhex("08240825082b"))
        self.assertEqual(encryption_schemes(bytes.fromhex("0a03030201")), [3, 2, 1])
        self.assertEqual(encryption_schemes(bytes.fromhex("080308020801")), [3, 2, 1])
        self.assertEqual(one(b"", 1, 0), 0)  # proto3 authorized default
        self.assertEqual(one(bytes.fromhex("08010800"), 1), 0)

    def test_malformed_protobuf_and_integer_bounds(self):
        for data in (b"\x08\x80", b"\x12\x05a", b"\x00", b"\x0b", b"\x09abc",
                     b"\x08" + b"\xff" * 9 + b"\x02"):
            with self.subTest(data=data), self.assertRaises(ValueError):
                fields(data)
        for value in (-1, 1 << 64):
            with self.assertRaises(ValueError):
                varint(value)
        self.assertEqual(one(integer(1, (1 << 64) - 1), 1), (1 << 64) - 1)


class SessionTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)

    def make_session(self, response):
        class Client:
            async def write_gatt_char(client, characteristic, chunk, response=True):
                # Simulated camera delivers response in transport fragments.
                session.receive(None, reply[:8])
                session.receive(None, reply[8:])
        reply = response
        session = Session(Client(), Path(self.directory.name))
        self.addCleanup(session.log.close)
        return session

    async def test_encrypted_request_requires_authenticated_response(self):
        session = self.make_session(validated(PACKET).raw)
        session.key = KEY
        self.assertEqual(await session.request(8, options([48]), encrypted=True), PAYLOAD[9:])
        self.assertFalse(session.pending)

    async def test_plaintext_cannot_satisfy_encrypted_request(self):
        session = self.make_session(encode_frame(1, PAYLOAD))
        session.key = KEY
        with self.assertRaisesRegex(ValueError, "encryption does not match"):
            await session.request(8, encrypted=True)

    async def test_camera_error_is_not_command_success(self):
        payload = (500).to_bytes(2, "little") + PAYLOAD[2:]
        session = self.make_session(encode_frame(1, payload))
        with self.assertRaisesRegex(RuntimeError, "500 to command 8"):
            await session.request(8)

    async def test_private_identity_persists_and_credentials_replace_restrictively(self):
        folder = Path(self.directory.name)
        identity = folder / "identity.json"
        original = client_identity(identity)
        self.assertEqual(client_identity(identity), original)
        self.assertEqual(identity.stat().st_mode & 0o777, 0o600)
        credential = folder / "wifi.json"
        credential.write_text("old")
        credential.chmod(0o644)
        private_json(credential, {"password": "synthetic-test-only"})
        self.assertEqual(credential.stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
