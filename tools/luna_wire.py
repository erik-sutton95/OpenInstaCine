"""Luna lab protobuf and scheme-3 codec. No BLE, filesystem, or camera policy.

Protocol provenance and hardware evidence: docs/research/luna-ble-bootstrap-2026-09-11.md.
This deliberately implements only the bootstrap's protobuf subset.
"""

from __future__ import annotations

import os
import struct

from ucd2 import Frame, Message, checksum


def varint(value: int) -> bytes:
    if not 0 <= value < 1 << 64:
        raise ValueError("Expected unsigned 64-bit varint")
    result = bytearray()
    while value > 127:
        result.append((value & 127) | 128)
        value >>= 7
    result.append(value)
    return bytes(result)


def tag(field: int, wire: int) -> bytes:
    if not 0 < field < 1 << 29:
        raise ValueError("Invalid protobuf field number")
    return varint((field << 3) | wire)


def integer(field: int, value: int) -> bytes:
    return tag(field, 0) + varint(value)


def zigzag32(value: int) -> int:
    if not -0x80000000 <= value <= 0x7fffffff:
        raise ValueError("Expected signed 32-bit value")
    return ((value << 1) ^ (value >> 31)) & 0xffffffff


def signed32(field: int, value: int) -> bytes:
    return integer(field, zigzag32(value))


def photography_get(types: list[int], mode: int = 7) -> bytes:
    if not types or any(t <= 0 for t in types):
        raise ValueError("Photography GET requires option type numbers")
    return b"".join(integer(1, number) for number in types) + integer(2, mode)


def photography_set(types: list[int], nested: bytes, mode: int = 7) -> bytes:
    if not types or any(t <= 0 for t in types):
        raise ValueError("Photography SET requires option type numbers")
    packed = b"".join(varint(number) for number in types)
    return blob(1, packed) + blob(2, nested) + integer(3, mode)


def color_recovery_set(enabled: bool, mode: int = 7) -> bytes:
    return photography_set([73], integer(73, 1 if enabled else 0), mode)


def gimbal_control(action: int, up_down: int = 0, left_right: int = 0) -> bytes:
    if action not in (1, 2, 3) or not -99 <= up_down <= 99 or not -99 <= left_right <= 99:
        raise ValueError("Unsupported gimbal control")
    remote = b""
    if up_down:
        remote += signed32(1, up_down)
    if left_right:
        remote += signed32(2, left_right)
    return integer(1, action) + blob(2, remote)


def blob(field: int, value: bytes) -> bytes:
    return tag(field, 2) + varint(len(value)) + value


def options(numbers: list[int]) -> bytes:
    return b"".join(integer(1, number) for number in numbers)


def read_varint(data: bytes, offset: int) -> tuple[int, int]:
    value = 0
    for shift in range(0, 70, 7):
        if offset >= len(data):
            raise ValueError("Truncated varint")
        byte = data[offset]
        offset += 1
        if shift == 63 and byte > 1:
            raise ValueError("Varint overflow")
        value |= (byte & 127) << shift
        if not byte & 128:
            return value, offset
    raise ValueError("Varint overflow")


def fields(data: bytes) -> list[tuple[int, int, int | bytes]]:
    offset, result = 0, []
    while offset < len(data):
        tagged, offset = read_varint(data, offset)
        field, wire = tagged >> 3, tagged & 7
        if not 0 < field < 1 << 29:
            raise ValueError("Invalid protobuf field number")
        if wire == 0:
            value, offset = read_varint(data, offset)
        elif wire in (1, 2, 5):
            if wire == 2:
                size, offset = read_varint(data, offset)
            else:
                size = 8 if wire == 1 else 4
            if offset + size > len(data):
                raise ValueError("Truncated protobuf field")
            value = data[offset:offset + size]
            offset += size
        else:
            raise ValueError("Unsupported protobuf wire type")
        result.append((field, wire, value))
    return result


def one(data: bytes, number: int, default=None):
    # Singular protobuf fields use the last occurrence. Validate the entire body.
    return next((value for field, _, value in reversed(fields(data))
                 if field == number), default)


def encryption_schemes(data: bytes) -> list[int]:
    result = []
    for field, wire, value in fields(data):
        if field != 1:
            continue
        if wire == 0:
            result.append(value)
        elif wire == 2:
            offset = 0
            while offset < len(value):
                scheme, offset = read_varint(value, offset)
                result.append(scheme)
        else:
            raise ValueError("Invalid encryption-capability field")
    return result


def derive_key(shared_secret: bytes) -> bytes:
    from cryptography.hazmat.primitives import hashes
    from cryptography.hazmat.primitives.kdf.hkdf import HKDF

    return HKDF(algorithm=hashes.SHA256(), length=16, salt=b"UCD2-ENCRYPT",
                info=b"AES-SESSION-KEY").derive(shared_secret)


def complete_key_exchange(private_key, reply: bytes) -> bytes:
    from cryptography.hazmat.primitives.asymmetric import ec

    # EncryptErrorCode differs from authorization result: NONE is 1, not 0.
    if one(reply, 1, 0) != 1:
        raise ValueError("Camera key exchange did not report ENCRYPT_ERROR_NONE (1)")
    peer = one(reply, 2)
    if not isinstance(peer, bytes) or len(peer) != 65 or peer[0] != 4:
        raise ValueError("Invalid camera P-256 public key encoding")
    public_key = ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), peer)
    return derive_key(private_key.exchange(ec.ECDH(), public_key))


def encode_frame(sequence: int, payload: bytes, key: bytes | None = None) -> bytes:
    if key is not None and len(key) != 16:
        raise ValueError("Scheme 3 requires a 128-bit key")
    header = b"UCD2" + bytes([1, 43 if key is not None else 12, 4, sequence])
    header += struct.pack("<I", len(payload))
    if key is None:
        packet = header + payload
    else:
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM

        nonce = os.urandom(12)
        encrypted = AESGCM(key).encrypt(nonce, payload, header)
        packet = header + bytes.fromhex("401d03") + nonce + encrypted[-16:] + encrypted[:-16]
    return packet + checksum(packet).to_bytes(4, "little")


def decode_message(frame: Frame, key: bytes | None = None) -> Message | None:
    """Decode a checksum-validated Frame supplied by Reassembler."""
    if frame.frame_type != 4:
        return None
    if frame.header_length == 12:
        return frame.plain_message()
    if not frame.scheme3_encrypted:
        raise ValueError("Unknown UCD2 header extension")
    if key is None or len(key) != 16:
        raise ValueError("No negotiated scheme-3 key")
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM

    payload = AESGCM(key).decrypt(frame.raw[15:27], frame.payload + frame.raw[27:43],
                                  frame.raw[:12])
    if len(payload) < 9:
        raise ValueError("Short encrypted message")
    tagged_id = int.from_bytes(payload[3:7], "little")
    return Message(int.from_bytes(payload[:2], "little"), payload[2],
                   tagged_id & 0x3FFFFFFF, tagged_id & 0xC0000000,
                   payload[7:9], payload[9:])
