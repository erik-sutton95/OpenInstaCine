import Foundation
import Testing

@testable import OpenPocketViewCore

/// The app's camera access point policy; the redactor and reports are tested in OpenCineMedia.
@Suite struct DiagnosticsTests {
    @Test func keepsCameraSSIDAndSoftAPAddress() {
        let raw = "ssid=OsmoPocket3-A1B2 path=192.168.2.15 seq=42054"
        let out = PrivacyRedactor.redact(raw)
        #expect(out.contains("OsmoPocket3-A1B2"))
        #expect(out.contains("192.168.2.15"))
        #expect(out.contains("seq=42054"))
    }

    @Test func cameraNetworkDetection() {
        #expect(PrivacyRedactor.isCameraNetwork("OsmoPocket3-AAAA"))
        #expect(PrivacyRedactor.isCameraNetwork("Xtra-Muse-1"))
        #expect(!PrivacyRedactor.isCameraNetwork("ErikHome"))
    }
}
