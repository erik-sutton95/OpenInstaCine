import Testing

@testable import OpenPocketViewCore

@Suite struct CamCapTests {
    @Test func emptyCapabilityPortraitKeepsReportedResolution() {
        let statusFormat = VideoFormat(resolution: .p3K_9x16, frameRate: .fps25)
        let formats = CamCapVideoFormat.pickerFormats(
            available: [], model: CameraModel.resolve(modelId: 0x20, name: nil),
            shootingMode: -1)
        let aspects = CamCapVideoFormat.aspects(
            available: formats, current: statusFormat.resolution.aspect)
        let resolutions = CamCapVideoFormat.resolutions(
            available: formats, aspect: aspects.count > 1 ? .nineSixteen : nil,
            current: statusFormat.resolution)
        #expect(resolutions == [.p3K_9x16])
        #expect(resolutions.map(\.tabTitle) == ["3K"])
    }

    @Test func pocket3PickerNeverOverridesReportedFormatsOrOtherModes() {
        let pocket3 = CameraModel.resolve(modelId: 0x20, name: "OsmoPocket3-Test")
        let reported = [VideoFormat(resolution: .p4K, frameRate: .fps25)]
        #expect(CamCapVideoFormat.pickerFormats(available: reported, model: pocket3, shootingMode: 1) == reported)
        for mode in [-1, 2, 0x05, 0x0A, 0x17, 26] {
            #expect(CamCapVideoFormat.pickerFormats(available: [], model: pocket3, shootingMode: mode).isEmpty)
        }
        for name in ["OsmoPocket4P-Test", "OsmoNano-Test", "Unknown"] {
            #expect(CamCapVideoFormat.pickerFormats(available: [], model: .resolve(modelId: nil, name: name), shootingMode: 1).isEmpty)
        }
        #expect(
            CamCapVideoFormat.pickerFormats(available: [], model: pocket3, shootingMode: 0)
                .isEmpty == false)
        #expect(
            CamCapVideoFormat.pickerFormats(
                available: [], model: .resolve(modelId: 0x22, name: "Osmo Pocket 4 Pro"),
                shootingMode: 0
            ).isEmpty)
    }

    @Test func pocket3SlowMoAndLowLightFallbacksMatchAcceptedPairsOnly() {
        let pocket3 = CameraModel.resolve(modelId: 0x20, name: "OsmoPocket3-Test")
        let slow = CamCapVideoFormat.pickerFormats(available: [], model: pocket3, shootingMode: 0)
        #expect(
            slow == [
                VideoFormat(resolution: .p4K, frameRate: .fps100),
                VideoFormat(resolution: .p4K, frameRate: .fps120),
                VideoFormat(resolution: .p2_7K, frameRate: .fps120),
                VideoFormat(resolution: .p1080, frameRate: .fps120),
                VideoFormat(resolution: .p1080, frameRate: .fps240),
            ])
        let lowLight = CamCapVideoFormat.pickerFormats(
            available: [], model: pocket3, shootingMode: 0x28)
        #expect(lowLight.count == 6)
        #expect(Set(lowLight.map(\.resolution)) == [.p1080, .p4K])
        #expect(Set(lowLight.map(\.frameRate)) == [.fps24, .fps25, .fps30])
        #expect(
            !lowLight.contains { $0.resolution == .p2_7K },
            "Low-Light survey had no 2.7K")
    }

    @Test func isoStepsSkipAutoAndStopAtEnds() {
        #expect(IsoIndex.stepped(from: .iso100, stops: 1, available: IsoIndex.allCases) == .iso200)
        #expect(IsoIndex.stepped(from: .iso25600, stops: 1, available: IsoIndex.allCases) == nil)
        #expect(IsoIndex.stepped(from: .auto, stops: 1, available: IsoIndex.allCases) == nil)
        #expect(
            IsoIndex.stepped(from: .iso400, stops: -1, available: [.iso200, .iso400, .iso800])
                == .iso200)
    }

    @Test func shutterStepsOpenTowardSlower() {
        let denoms = [16_000, 8_000, 100, 50, 25, 4]
        #expect(CamCapShutter.steppedDenom(from: 50, steps: 1, available: denoms) == 25)
        #expect(CamCapShutter.steppedDenom(from: 50, steps: -1, available: denoms) == 100)
        #expect(CamCapShutter.steppedDenom(from: 16_000, steps: -1, available: denoms) == nil)
        #expect(CamCapShutter.steppedDenom(from: 4, steps: 1, available: denoms) == nil)
        #expect(CamCapShutter.steppedDenom(from: 48, steps: 1, available: denoms) == 25)
    }

    /// D-Log stars 400, D-Log2 stars 1600; Rec.709, HLG and unknown star nothing.
    @Test(
        arguments: [
            (.dlog, .dLog, ["400"], 400),
            (.dlog2, .dLog2, ["1600"], 1600),
            (.rec709, .normal, [], nil),
            (.hdr, .hdr, [], nil),
            (nil, nil, [], nil),
        ] as [(MonitorTransfer?, ColorMode?, Set<String>, Int?)])
    func baseISOStarsOnlyTheLogFloor(
        transfer: MonitorTransfer?, colorMode: ColorMode?, stars: Set<String>, base: Int?
    ) {
        #expect(CamCapIso.markedLabels(transfer: transfer) == stars)
        #expect(CamCapIso.markedLabels(colorMode: colorMode) == stars)
        #expect(CamCapIso.baseISO(transfer: transfer) == base)
        #expect(CamCapIso.baseISO(colorMode: colorMode) == base)
    }

    /// #180: Auto ISO range labels use the body's Rec.709 floor. SET bytes stay
    /// `IsoLimit` — Pocket 3 "100–400" was 50–400 on the camera.
    @Test func rec709IsoAutoFloorFollowsTheBody() {
        let p3 = CameraModel.resolve(modelId: 0x0020, name: nil)
        let p4 = CameraModel.resolve(modelId: 0x0021, name: nil)
        let p4p = CameraModel.resolve(modelId: 0x0022, name: nil)
        #expect(p3.isoAutoRangeFloor == 50)
        #expect(p4.isoAutoRangeFloor == 50)
        #expect(p4p.isoAutoRangeFloor == 100)
        #expect(CameraModel.default.isoAutoRangeFloor == 100)
        #expect(
            CameraModel.resolve(modelId: nil, name: "OsmoPocket3-A1B2").isoAutoRangeFloor == 50)

        #expect(ColorMode.normal.isoAutoBase(for: p3) == 50)
        #expect(ColorMode.hdr.isoAutoBase(for: p3) == 50)
        #expect(ColorMode.dLogM.isoAutoBase(for: p3) == 50)
        #expect(ColorMode.normal.isoAutoBase(for: p4) == 50)
        #expect(ColorMode.normal.isoAutoBase(for: p4p) == 100)
        #expect(ColorMode.normal.isoAutoBase == 100, "unknown body keeps captured 4 Pro floor")
        #expect(ColorMode.dLog.isoAutoBase(for: p3) == 400, "D-Log floor is color, not body")
        #expect(ColorMode.dLog2.isoAutoBase(for: p3) == nil)

        #expect(ColorMode.normal.isoAutoLabels(for: p3).first == "50–200")
        #expect(ColorMode.normal.isoAutoLabels(for: p3).contains("50–400"))
        #expect(!ColorMode.normal.isoAutoLabels(for: p3).contains("100–400"))
        #expect(ColorMode.normal.isoAutoLabels(for: p4p).first == "100–200")
        #expect(IsoLimit.max400.label(base: 50) == "50–400")
    }

    @Test func emptyAvailableUsesDocumentedVideoLadder() {
        let wheel = CamCapShutter.wheelDenoms(available: [], current: 60)
        #expect(wheel.contains(60))
        #expect(wheel.contains(50))
        #expect(wheel.contains(48))
        #expect(wheel.contains(100))
        #expect(wheel.contains(8000))
        #expect(wheel.first == 8000)
        let withOdd = CamCapShutter.wheelDenoms(available: [], current: 80)
        #expect(withOdd.contains(80))
        #expect(withOdd.contains(100))
        let unknown = CamCapShutter.wheelDenoms(available: [], current: -1)
        #expect(unknown.contains(50))
        #expect(
            ShutterAngle.denom(degrees: 180, fps: 24, available: wheel) == 48,
            "angle apply must not snap every stop to the live 1/60")
    }

    @Test func pocket3VideoCapKeeps1by1And9by16() {
        let rates: [UInt8] = [1, 2, 3, 4, 5, 6]
        let formats = CamCapVideoFormat.parse(
            Self.packVideoFormats(
                [0x10, 0x2D, 0x0A, 0x6B, 0x6A, 0x69, 0x6C, 0x43, 0x42].map { ($0, rates) }))
        #expect(formats.count == 54)
        #expect(
            CamCapVideoFormat.aspects(available: formats, current: nil)
                == [.sixteenNine, .oneOne, .nineSixteen])
        #expect(
            CamCapVideoFormat.resolutions(
                available: formats, aspect: .oneOne, current: nil
            ).map(\.rawValue) == [0x6B, 0x6A, 0x69])
        #expect(
            CamCapVideoFormat.resolutions(
                available: formats, aspect: .nineSixteen, current: nil
            ).map(\.rawValue) == [0x6C, 0x43, 0x42])
        #expect(VideoFormat(resolution: .p3K_1x1, frameRate: .fps24).chipLabel == "3K 1:1 · 24p")
        #expect(VideoFormat(resolution: .p3K_9x16, frameRate: .fps30).chipLabel == "3K 9:16 · 30p")
    }

    @Test func unknownCamcapByteIsKept() {
        let formats = CamCapVideoFormat.parse(Self.packVideoFormats([(0x11, [1])]))
        #expect(formats.count == 1)
        #expect(formats[0].resolution.rawValue == 0x11)
        #expect(formats[0].resolution.aspect == nil)
        #expect(formats[0].resolution.tabTitle == "11")
        #expect(formats[0].chipLabel == "0x11 · 24p")
    }

    @Test func colorModesFollowTheBody() {
        let pro = CameraModel.resolve(modelId: 0x0022, name: nil)
        let pocket4 = CameraModel.resolve(modelId: 0x0021, name: nil)
        let pocket3 = CameraModel.resolve(modelId: 0x0020, name: nil)
        let nano = CameraModel.resolve(modelId: 0x0019, name: nil)
        #expect(ColorMode.available(for: pro) == [.normal, .hdr, .dLog, .dLog2])
        #expect(ColorMode.available(for: pocket4) == [.normal, .hdr, .dLog])
        #expect(ColorMode.available(for: pocket3) == [.normal, .hdr, .dLogM])
        #expect(ColorMode.available(for: nano) == [.normal, .normal10, .dLogM])
        #expect(ColorMode.dLogM.label(for: .pocket) == "D-Log M")
        #expect(ColorMode(label: "D-Log M") == .dLogM)
        #expect(
            ColorMode.available(for: CameraModel.resolve(modelId: nil, name: "OsmoPocket4P-ABCD"))
                .contains(.dLog2))
        #expect(
            !ColorMode.available(for: CameraModel.resolve(modelId: nil, name: "OsmoPocket4-ABCD"))
                .contains(.dLog2))
        #expect(
            ColorMode.available(for: CameraModel.resolve(modelId: nil, name: "OsmoPocket3-ABCD"))
                == [.normal, .hdr, .dLogM])
        #expect(
            !CamCapColorMode.wheel(
                available: [.normal, .hdr, .dLog, .dLog2], model: pocket3
            ).contains(.dLog2))
        #expect(
            !CamCapColorMode.wheel(
                available: [.normal, .hdr, .dLog, .dLog2], model: pocket4
            ).contains(.dLog2))
        #expect(
            CamCapColorMode.wheel(
                available: [.normal, .hdr, .dLog, .dLog2], model: pro
            ) == [.normal, .hdr, .dLog, .dLog2])
    }

    @Test func optimisticZoomPinExpiresWhenTheBodyNeverConfirms() {
        // The chip rides the same pin as every other control, with
        // `CamFov.matches` standing in for equality.
        func held(_ ask: Double, live: Double?, age: Double) -> Double? {
            var pin: CameraValuePin<Double>? = CameraValuePin(ask, now: 0)
            return CameraValuePin.reconcile(
                &pin, reported: live, now: age, confirms: CamFov.matches)
        }
        // Fresh ask: the chip holds the target through the round trip.
        #expect(held(3, live: 1, age: 0) == 3)
        #expect(held(3, live: nil, age: 0) == 3)
        // Body confirmed — the pin has done its job, live takes over.
        #expect(held(3, live: 3, age: 0) == nil)
        #expect(held(3, live: 2.97, age: 0) == nil)
        // Body clamped, or moved the lens on its own (FORMAT change resets to
        // 1×). It never reports 3×, so only the deadline can free the chip.
        #expect(held(3, live: 1, age: 2) == nil)
        #expect(held(4, live: 2, age: 5) == nil)
        #expect(held(3, live: nil, age: 5) == nil)
        // A pin that outlived its ask must not win the readout.
        #expect(CamFov.readout(live: 1, preview: nil, fallback: 3, optimistic: nil) == 1)
    }

    private static let shutter25p = hex(
        "016d000002000101001e00052180be00409f00009900889300a08f00808c00c48900d08700408600e28400e88300208300808200f48100908100408100f08000c88000a080007880006480005080003c80003280002880001e80001980000c80000a8000088000068000058000048000"
    )
    private static let shutter60p = hex(
        "0164000002000101001e00051e80be00409f00009900889300a08f00808c00c48900d08700408600e28400e88300208300808200f48100908100408100f08000c88000a080007880006480005080003c80003280000c80000a8000088000068000058000048000"
    )
    private static let shutter24p = hex(
        "0161000002000101001e00051d80be00409f00009900889300a08f00808c00c48900d08700408600e28400e88300208300808200f48100908100408100f08000c88000a080007880006480005080003c80000c80000a8000088000068000058000048000"
    )
    private static let isoDLog2: [UInt8] = [
        0x01, 0x08, 0x00, 0x00, 0x06, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
    ]
    private static let isoAutoOnly: [UInt8] = [0x01, 0x03, 0x00, 0x00, 0x01, 0x00]
    /// `camcap_video_format` Pocket 4 Pro Video mode (`mimo-live-start-20260828`).
    private static let videoFormatPocket4Pro = hex(
        "0125000c1001001002001003001004001005001006000a06000a05000a04000a03000a02000a0100"
    )
    /// DJI Nano Video matrix: 4K 4:3 24–50, then 16:9/4:3 4K/2.7K/1080 24–60.
    private static let videoFormatNanoVideo: [UInt8] = packVideoFormats(
        [(0x67, [1, 2, 3, 4, 5])]
            + [0x10, 0x5F, 0x2D, 0x0C, 0x0A].map { res in (res, [1, 2, 3, 4, 5, 6]) }
    )

    private static func packVideoFormats(_ groups: [(UInt8, [UInt8])]) -> [UInt8] {
        let pairs = groups.flatMap { res, rates in rates.map { (res, $0) } }
        let inner = 1 + pairs.count * 3
        var out: [UInt8] = [
            0x01, UInt8(inner & 0xFF), UInt8((inner >> 8) & 0xFF), UInt8(pairs.count),
        ]
        for (res, fps) in pairs {
            out += [res, fps, 0x00]
        }
        return out
    }

    private static func hex(_ s: String) -> [UInt8] {
        stride(from: 0, to: s.count, by: 2).map {
            let i = s.index(s.startIndex, offsetBy: $0)
            return UInt8(s[i..<s.index(i, offsetBy: 2)], radix: 16)!
        }
    }
}
