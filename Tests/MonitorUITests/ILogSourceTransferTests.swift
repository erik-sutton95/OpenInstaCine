import CoreImage
import MonitorContracts
import OpenPocketViewCore
import XCTest

@testable import MonitorUI

@MainActor
final class ILogSourceTransferTests: XCTestCase {
    func testSourceTransferOverridesLegacyMetadataWithoutInventingDJIMode() {
        var effects = LiveImageEffects()
        effects.colorMode = .dLog2
        XCTAssertEqual(effects.monitorTransfer, .dlog2)
        effects.sourceTransfer = .ilog
        XCTAssertEqual(effects.monitorTransfer, .ilog)
        XCTAssertNil(MonitorTransfer.ilog.colorMode)
        XCTAssertEqual(MonitorTransfer.resolved(.ilog, colorMode: .normal), .ilog)
        XCTAssertNil(PocketScopeSampler.monitorCube(for: .ilog, effects: effects))

        effects.sourceTransfer = .rec709
        XCTAssertEqual(effects.monitorTransfer, .rec709)
    }

    func testSourceInformationRemainsSeparateFromCameraRecordingProfile() {
        let backend = SourceMetadataBackend()
        let session = CameraSession(backend: backend)
        session.activateBackend()
        backend.eventHandler?(
            .information(.init(model: "Test source", previewTransfer: .iLog)))
        XCTAssertEqual(session.monitorTransfer, .ilog)
        XCTAssertNil(session.status.colorMode)
        XCTAssertNil(session.status.videoFormat)

        backend.eventHandler?(
            .information(.init(model: "Test source", previewTransfer: .rec709)))
        XCTAssertEqual(session.monitorTransfer, .rec709)
        XCTAssertNil(session.status.colorMode)
        session.disconnect()
    }

    func testIlogSurvivesDecodedFramePublication() async {
        let bus = LiveFrameSampleBus()
        let decoder = HevcDecoder()
        var effects = LiveImageEffects()
        effects.histogram = true
        effects.colorMode = .dLog2
        decoder.attach(sampleBus: bus, effects: { effects }, transfer: { .ilog })
        decoder.effects = effects
        decoder.handleDecodedFrame(
            ScopeTestBuffers.makeFlatBuffer(code: 108), effects: effects, transfer: .ilog)
        let deadline = Date().addingTimeInterval(3)
        while bus.publishedScopes == 0, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertGreaterThan(bus.publishedScopes, 0)
        XCTAssertEqual(bus.transfer, .ilog)
        XCTAssertEqual(bus.bundle.transfer, .ilog)
        XCTAssertNil(bus.colorMode, "I-Log does not have a DJI ColorMode equivalent")
        XCTAssertGreaterThan(bus.bundle.samples.histogramLuma[108], 0)
        decoder.reset()
    }

    func testIlogScopeSamplerUsesBT2020WeightsOnSourceCodes() {
        let sampled = PocketScopeSampler.sample(
            bytes: [0, 0, 255, 255], width: 1, height: 1, bytesPerRow: 4,
            transfer: .ilog, includePoints: true, look: nil, previous: .empty)
        XCTAssertEqual(sampled.samples.points.first?.red, 255)
        XCTAssertEqual(sampled.samples.points.first?.luma, 67)
        XCTAssertEqual(sampled.samples.histogramLuma[67], 1)
    }

    func testIlogZebraDoesNotInheritDJIPreviewClippingCeiling() {
        ScopeExposureCeiling.reset()
        defer { ScopeExposureCeiling.reset() }
        let buffer = ScopeTestBuffers.makeFlatBuffer(code: 248)
        let source = CIImage(cvPixelBuffer: buffer, options: LiveMonitorWorkingSpace.imageOptions)
        var effects = LiveImageEffects()
        effects.zebra = true
        effects.zebraMidtone = false
        effects.zebraHighlightIRE = 100
        effects.colorMode = .dLog2
        effects.sourceTransfer = .ilog
        let ilog = LiveMonitorCompositor.assistOverlay(from: source, effects: effects)
        XCTAssertLessThan(maxAlpha(ilog), 0.04)

        effects.sourceTransfer = nil
        let legacy = LiveMonitorCompositor.assistOverlay(from: source, effects: effects)
        XCTAssertGreaterThan(maxAlpha(legacy), 0.4)
    }

    func testIlogStopsPaintSameExposureForNeutralAndColoredSceneLuminance() {
        let cube = PocketFalseColorMap.overlayPaintCube(scale: .stops, transfer: .ilog)
        let black = Float(MonitorTransfer.ilog.encodeLinear(0))
        let gray = Float(MonitorTransfer.ilog.encodeLinear(0.18))
        // BT.2020 red contributes 0.2627 of scene luminance. This red-only
        // patch and the neutral patch therefore both meter at 18% / zero stops.
        let red = Float(MonitorTransfer.ilog.encodeLinear(0.18 / 0.2627))
        let neutral = cube.map(red: gray, green: gray, blue: gray)
        let colored = cube.map(red: red, green: black, blue: black)
        XCTAssertGreaterThan(neutral.green - neutral.red, 0.2)
        XCTAssertGreaterThan(colored.green - colored.red, 0.2)
        XCTAssertGreaterThan(colored.green - colored.blue, 0.2)
        // Gray detail is blended equally into RGB; band chroma stays the same.
        XCTAssertEqual(
            colored.green - colored.red, neutral.green - neutral.red, accuracy: 0.04)
    }

    func testIlogFalseColorReferenceUsesSourceCurve() {
        let reference = FalseColorAssist.referenceDisplay(scale: .stops, transfer: .ilog)
        XCTAssertEqual(reference.transfer, .ilog)
        XCTAssertEqual(FalseColorReference.curveKeyLabel(reference.transfer), "I-Log")
        XCTAssertEqual(FalseColorLegend(scale: .stops, transfer: .ilog).transfer, .ilog)
        XCTAssertEqual(FalseColorLegend(scale: .stops, colorMode: .dLog2).transfer, .dlog2)
    }

    private func maxAlpha(_ image: CIImage) -> Float {
        let width = 32
        let height = 32
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let scaled = image.transformed(
            by: CGAffineTransform(
                scaleX: CGFloat(width) / image.extent.width,
                y: CGFloat(height) / image.extent.height))
        let context = CIContext(options: LiveMonitorWorkingSpace.contextOptions)
        context.render(
            scaled, toBitmap: &bytes, rowBytes: width * 4,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBA8, colorSpace: nil)
        return stride(from: 3, to: bytes.count, by: 4)
            .map { Float(bytes[$0]) / 255 }.max() ?? 0
    }
}

@MainActor
private final class SourceMetadataBackend: CameraBackend {
    let capabilities: CameraCapabilities = [.liveVideo]
    var eventHandler: ((CameraBackendEvent) -> Void)?
    var isOnCameraNetwork = false
    func startScan() async throws {}
    func connect(to camera: MonitorCamera) async throws {}
    func disconnect() {}
    func forget(cameraID: UUID) {}
    func leaveCameraNetwork() {}
    func rejoinCameraNetwork() async throws {}
}
