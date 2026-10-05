import Testing

@testable import OpenPocketViewCore

@Suite struct ShootingModeTests {

    @Test func photoExcludesSuperNightLowLightVideo() {
        #expect(ShootingMode.photo.isPhoto)
        #expect(!ShootingMode.video.isPhoto)
        #expect(!ShootingMode.slowMo.isPhoto)
        #expect(!ShootingMode.timeLapse.isPhoto)
        #expect(!ShootingMode.hyperLapse.isPhoto)
        #expect(!ShootingMode.superNight.isPhoto)
        #expect(ShootingMode.superNight.offersVideoFormat)
        #expect(!ShootingMode.photo.offersVideoFormat)
    }

    @Test func photoSetByteIsBodySpecificAndDefaultStaysPocket4() {
        let pocket3 = CameraModel.resolve(modelId: 0x0020, name: "Osmo Pocket 3")
        let nano = CameraModel.resolve(modelId: 0x0019, name: "Osmo Nano")
        let pocket4 = CameraModel.resolve(modelId: 0x0021, name: "Osmo Pocket 4")
        let pro = CameraModel.resolve(modelId: 0x0022, name: "Osmo Pocket 4 Pro")
        #expect(ShootingMode.photo.wireByte(for: pocket3) == 0x05)
        #expect(ShootingMode.photo.wireByte(for: nano) == 0x05)
        #expect(ShootingMode.photo.wireByte(for: pocket4) == 0x17)
        #expect(ShootingMode.photo.wireByte(for: pro) == 0x17)
        #expect(ShootingMode.video.wireByte(for: pocket3) == 0x01)
        #expect(ShootingMode.photo.wireByte(for: nil) == 0x17)
        // The enum rawValue only carries Pocket 4; fromWire maps both photo bytes to `.photo`.
        #expect(ShootingMode(rawValue: 0x05) == nil)
        #expect(ShootingMode.fromWire(0x05) == .photo)
        #expect(ShootingMode(rawValue: 0x17) == .photo)
    }

    @Test func slowMoTrailerIsModeAndRateSpecificAndDefaultApiUnchanged() {
        let fourK120 = VideoFormat(resolution: .p4K, frameRate: .fps120)
        let fourK100 = VideoFormat(resolution: .p4K, frameRate: .fps100)
        let hd240 = VideoFormat(resolution: .p1080, frameRate: .fps240)
        let fourK30 = VideoFormat(resolution: .p4K, frameRate: .fps30)
        #expect(fourK120.setPayload == [0x10, 0x07, 0x00, 0x00, 0x00])
        #expect(fourK120.setPayload(shootingMode: nil) == [0x10, 0x07, 0x00, 0x00, 0x00])
        #expect(fourK120.setPayload(shootingMode: .slowMo) == [0x10, 0x07, 0x00, 0x04, 0x00])
        #expect(fourK100.setPayload(shootingMode: .slowMo) == [0x10, 0x0A, 0x00, 0x04, 0x00])
        #expect(hd240.setPayload(shootingMode: .slowMo) == [0x0A, 0x08, 0x00, 0x08, 0x00])
        #expect(fourK30.setPayload(shootingMode: .slowMo) == [0x10, 0x03, 0x00, 0x00, 0x00])
        #expect(fourK120.setPayload(shootingMode: .video) == [0x10, 0x07, 0x00, 0x00, 0x00])
        #expect(fourK120.setPayload(shootingMode: .superNight) == [0x10, 0x07, 0x00, 0x00, 0x00])
    }
}
