import Testing

@testable import OpenPocketViewCore

@Suite struct DeclaredVideoFrameTests {
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
