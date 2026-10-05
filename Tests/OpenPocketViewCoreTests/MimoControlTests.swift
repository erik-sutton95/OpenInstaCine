import Testing

@testable import OpenPocketViewCore

@Suite struct MimoControlTests {

    @Test func isoLimitGetOnlyWhenAutoIsOffered() {
        #expect(IsoLimit.shouldGet(colorMode: .normal))
        #expect(IsoLimit.shouldGet(colorMode: .hdr))
        #expect(IsoLimit.shouldGet(colorMode: .dLog))
        #expect(IsoLimit.shouldGet(colorMode: nil), "color unknown — treat as Normal")
        #expect(!IsoLimit.shouldGet(colorMode: .dLog2), "D-Log2 has no Auto ceiling")
        #expect(ColorMode.dLog2.isoAutoLimits.isEmpty)
        #expect(!ColorMode.dLog2.isoIndices.contains(.auto))
    }

    @Test func controlNoteToastSitsTopCenterAndFades() {
        #expect(ControlHud.toastCenterY(feedMinY: 200) == 222)
        #expect(
            ControlHud.toastCenterY(feedMinY: 0, chromeBottomY: 60) == 82,
            "DISP 1: park under the mounted top bar")
        #expect(
            ControlHud.toastCenterY(feedMinY: 200, chromeBottomY: Double?.none) == 222,
            "DISP 2: feed edge when the bar is off")
        #expect(
            ControlHud.toastCenterY(feedMinY: 50, chromeBottomY: 50) == 72,
            "portrait bar already sits above the feed")
        #expect(
            ControlHud.toastCenterY(feedMinY: 50, chromeBottomY: 40) == 72,
            "chrome above the feed does not pull the toast up")
    }

    @Test func recAndColorDrumLabelsMatchCapture() {
        #expect(VideoResolution.labeledVideo.map(\.label) == ["1080p", "4K"])
        #expect(VideoResolution.labeledVideo.map(\.tabTitle) == ["1080", "4K"])
        #expect(VideoFrameRate.labeledVideo.map(\.fps) == [24, 25, 30, 48, 50, 60])
        #expect(
            VideoFrameRate.labeledVideo.map(\.drumLabel) == [
                "24p", "25p", "30p", "48p", "50p", "60p",
            ])
        #expect(VideoFrameRate(drumLabel: "48p") == .fps48)
        #expect(VideoFrameRate(drumLabel: "120p") == .fps120)
        #expect(
            ColorMode.available(for: .pocket).map(\.label)
                == ["Normal", "HDR", "D-Log"])
        #expect(
            ColorMode.available(for: CameraModel.resolve(modelId: 0x0022, name: nil)).map(\.label)
                == ["Normal", "HDR", "D-Log", "D-Log2"])
        #expect(
            ColorMode.available(for: CameraModel.resolve(modelId: 0x0021, name: nil)).map(\.label)
                == ["Normal", "HDR", "D-Log"])
        #expect(
            ColorMode.available(for: CameraModel.resolve(modelId: 0x0020, name: nil)).map {
                $0.label(for: .pocket)
            } == ["Normal", "HDR", "D-Log M"])
        #expect(
            CamCapColorMode.wheel(
                available: [.dLog2, .dLog, .hdr, .normal],
                model: CameraModel.resolve(modelId: 0x0022, name: nil)
            ).map(\.label) == ["Normal", "HDR", "D-Log", "D-Log2"])
        #expect(
            CamCapColorMode.wheel(
                available: [], model: CameraModel.resolve(modelId: 0x0020, name: nil)
            ).map { $0.label(for: .pocket) } == ["Normal", "HDR", "D-Log M"])
        #expect(
            !CamCapColorMode.wheel(
                available: [], model: CameraModel.resolve(modelId: 0x0021, name: nil)
            ).contains(.dLog2))
        #expect(
            ColorMode.available(for: .nano).map { $0.label(for: .nano) }
                == ["Normal 8-bit", "Normal 10-bit", "D-Log M 10-bit"])
        #expect(ColorMode(label: "D-Log2") == .dLog2)
        #expect(ColorMode(label: "Normal 8-bit") == .normal)
        #expect(ColorMode(label: "D-Log M 10-bit") == .dLogM)
        #expect(ColorMode(label: "N-Log") == nil)
        #expect(VideoFormat(resolution: .p4K, frameRate: .fps25).chipLabel == "4K · 25p")
        #expect(VideoFormat(resolution: .p1080, frameRate: .fps24).chipLabel == "1080p · 24p")
    }

    /// Mimo pinch streams `0A 4E` at 20 Hz. Waiting for ACK made the lens
    /// jump only when the fingers paused (or after the 2 s SET timeout).
    /// Rapid shutter wheel: 1/160 is superseded by 1/8. That timeout is not
    /// half-dead uplink and must not stack with a UDP tear-down.
}
