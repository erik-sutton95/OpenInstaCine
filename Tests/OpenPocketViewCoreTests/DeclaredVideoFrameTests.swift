import Testing

@testable import OpenPocketViewCore

@Suite struct DeclaredVideoFrameTests {
    private func packets(_ slice: [UInt8], group: UInt8 = 255, firstSeq: UInt16 = 65520)
        -> [[UInt8]]
    {
        let n = UInt32(slice.count)
        let header: [UInt8] = [
            0, 0, 1, 255, UInt8(n & 255), UInt8((n >> 8) & 255), UInt8((n >> 16) & 255),
            UInt8(n >> 24), 0x90, 0x11, 0, 0, 0, 0, 0, 0,
        ]
        let bytes = header + slice
        let count = (bytes.count + 63) / 64
        return (0..<count).map { i in
            var p = [UInt8](repeating: 0, count: 20)
            let seq = firstSeq &+ UInt16(i * 8)
            p[4] = UInt8(seq & 255)
            p[5] = UInt8(seq >> 8)
            p[6] = 2
            p[16] = group &+ UInt8(i / 63)
            p[17] = UInt8(min(63, count - (i / 63) * 63)) | UInt8(((i % 63) % 2) << 7)
            p[18] = UInt8((i % 63) / 2)
            return p + Array(bytes[(i * 64)..<min(bytes.count, (i + 1) * 64)])
        }
    }
    private let slice = [UInt8]([0, 0, 1, 0x65]) + [UInt8](repeating: 0xAA, count: 9000)

    @Test func privateNanoMetadataCannotCreateFalseSliceNALs() {
        let sps: [UInt8] = [0x67, 0x42, 0xAA]
        let picture: [UInt8] = [0x65, 0xBB]
        var metadata = [UInt8](repeating: 0x22, count: 25)
        metadata.replaceSubrange(4..<9, with: [0, 0, 1, 0x41, 0xFF])
        let privateSEI: [UInt8] = [0, 0, 1, 6, 0xF0, 25] + metadata + [0x80]
        let au = [0, 0, 0, 1] + sps + privateSEI + [0, 0, 0, 1] + picture
        #expect(Hevc.nalUnits(au) == [sps, picture])
        #expect(Hevc.nalUnits(privateSEI).isEmpty)
        let ordinarySEI: [UInt8] = [6, 5, 1, 0x22, 0x80]
        #expect(Hevc.nalUnits([0, 0, 1] + ordinarySEI) == [ordinarySEI])
    }

}
