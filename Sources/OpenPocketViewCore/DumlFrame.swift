import Foundation

/// DUML wire framing for DJI Osmo cameras, ported from the Osmosis
/// reverse-engineering (see docs/protocol-notes.md). Plaintext, no crypto.
///
/// Frame layout (total = 13 + payload.count):
///   55 | len_lo | (ver<<2)|len_hi | crc8(bytes[0..2]) |
///   sender | receiver | seq:u16le | flags | cmdSet | cmdId | payload | crc16:u16le
public enum Duml {
    /// The app is always the sender: id 0, type 2 -> (0<<5)|2.
    public static let senderApp: UInt8 = 0x02

    /// Receivers, packed as (id<<5)|type. See Osmosis OsmoCommands / DumlTransport.
    public static let rxCamera: UInt8 = 0x01  // id 0, type 1

    /// Command flags (byte 8): request / response / unsolicited notify.
    public static let flagRequest: UInt8 = 0x40
    public static let flagNotify: UInt8 = 0x00

    public static func hex(_ bytes: [UInt8], limit: Int = 24) -> String {
        if bytes.isEmpty { return "-" }
        let head = bytes.prefix(limit).map { String(format: "%02X", $0) }.joined(separator: " ")
        return bytes.count > limit ? head + "…" : head
    }

    public struct Frame: Equatable, Sendable {
        public var sender: UInt8
        public var receiver: UInt8
        public var seq: UInt16
        public var flags: UInt8
        public var cmdSet: UInt8
        public var cmdId: UInt8
        public var payload: [UInt8]

        public init(
            sender: UInt8, receiver: UInt8, seq: UInt16, flags: UInt8,
            cmdSet: UInt8, cmdId: UInt8, payload: [UInt8]
        ) {
            self.sender = sender
            self.receiver = receiver
            self.seq = seq
            self.flags = flags
            self.cmdSet = cmdSet
            self.cmdId = cmdId
            self.payload = payload
        }
    }

    public static func encode(_ f: Frame) -> [UInt8] {
        let total = 13 + f.payload.count
        var b: [UInt8] = []
        b.reserveCapacity(total)
        b.append(0x55)
        b.append(UInt8(total & 0xFF))
        b.append(UInt8((1 << 2) | ((total >> 8) & 0x03)))  // ver 1 + high length bits
        b.append(crc8(Array(b[0..<3])))
        b.append(f.sender)
        b.append(f.receiver)
        b.append(UInt8(f.seq & 0xFF))
        b.append(UInt8((f.seq >> 8) & 0xFF))
        b.append(f.flags)
        b.append(f.cmdSet)
        b.append(f.cmdId)
        b.append(contentsOf: f.payload)
        let c = crc16(b)
        b.append(UInt8(c & 0xFF))
        b.append(UInt8((c >> 8) & 0xFF))
        return b
    }

    // Reflected CRC-8, init 0x77, poly 0x8C, over the 3 header bytes -> byte 3.
    public static func crc8(_ data: [UInt8]) -> UInt8 { crc8(data[...]) }

    /// Slice form so frame scanning checks CRCs without copying the frame.
    public static func crc8(_ data: ArraySlice<UInt8>) -> UInt8 {
        var c: UInt8 = 0x77
        for byte in data {
            c ^= byte
            for _ in 0..<8 { c = (c & 1) != 0 ? (c >> 1) ^ 0x8C : c >> 1 }
        }
        return c
    }

    // Reflected CRC-16, init 0x3692, poly 0x8408, over the whole frame minus the trailing CRC.
    public static func crc16(_ data: [UInt8]) -> UInt16 { crc16(data[...]) }

    public static func crc16(_ data: ArraySlice<UInt8>) -> UInt16 {
        var c: UInt16 = 0x3692
        for byte in data {
            c ^= UInt16(byte)
            for _ in 0..<8 { c = (c & 1) != 0 ? (c >> 1) ^ 0x8408 : c >> 1 }
        }
        return c
    }
}
