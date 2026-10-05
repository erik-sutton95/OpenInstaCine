import Testing

@testable import OpenPocketViewCore

@Suite struct DumlFrameTests {
    // CRC-8 vectors from the Osmosis unit tests.
    @Test func crc8Vectors() {
        #expect(Duml.crc8([0x55, 0x11, 0x04]) == 0x92)
        #expect(Duml.crc8([0x55, 0x33, 0x04]) == 0xC2)
    }

    // Enter-playback (0x02/0x0C), App -> Camera, seq 0xA000 — a real Osmosis frame, byte for byte.
    @Test func encodeEnterPlayback() {
        let frame = Duml.encode(
            .init(
                sender: Duml.senderApp, receiver: Duml.rxCamera, seq: 0xA000,
                flags: Duml.flagRequest, cmdSet: 0x02, cmdId: 0x0C,
                payload: [0x01, 0x01, 0x00, 0x01]))
        #expect(
            frame == [
                0x55, 0x11, 0x04, 0x92, 0x02, 0x01, 0x00, 0xA0,
                0x40, 0x02, 0x0C, 0x01, 0x01, 0x00, 0x01, 0xB6, 0x3B,
            ])
    }

}
