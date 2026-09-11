import CoreText
import MonitorContracts
import OpenPocketViewCore
import SwiftUI

/// The only product identity the shared Apple shell needs. A brand app supplies
/// these values once, alongside its backend, before mounting any monitor views.
public struct MonitorBrand {
    public var displayName: String
    public var monogram: String
    public var accentRGB: UInt32
    public var cameraFamily: String
    public var discoveryHint: String
    public var protocolDescription: String
    public var protocolLabel: String
    public var trademarkNotice: String
    public var sourceURL: URL?
    public var supportURL: URL?
    public var privacyURL: URL?
    public var termsURL: URL?
    public var cameraLUTs: [CameraLUT]

    public init(
        displayName: String, monogram: String, accentRGB: UInt32,
        cameraFamily: String, discoveryHint: String, protocolDescription: String,
        protocolLabel: String, trademarkNotice: String,
        sourceURL: URL? = nil, supportURL: URL? = nil,
        privacyURL: URL? = nil, termsURL: URL? = nil,
        cameraLUTs: [CameraLUT] = []
    ) {
        self.displayName = displayName
        self.monogram = monogram
        self.accentRGB = accentRGB
        self.cameraFamily = cameraFamily
        self.discoveryHint = discoveryHint
        self.protocolDescription = protocolDescription
        self.protocolLabel = protocolLabel
        self.trademarkNotice = trademarkNotice
        self.sourceURL = sourceURL
        self.supportURL = supportURL
        self.privacyURL = privacyURL
        self.termsURL = termsURL
        self.cameraLUTs = cameraLUTs
    }

    var accent: Color {
        Color(red: Double((accentRGB >> 16) & 255) / 255,
              green: Double((accentRGB >> 8) & 255) / 255,
              blue: Double(accentRGB & 255) / 255)
    }
}

enum MonitorIdentity {
    // A single brand per process; set by MonitorAppRoot before creating state.
    static var current = MonitorBrand(
        displayName: "OpenCapture", monogram: "OC", accentRGB: 0xFFFFFF,
        cameraFamily: "camera", discoveryHint: "Turn your camera on and keep it nearby.",
        protocolDescription: "The camera backend supplies the connection and live feed.",
        protocolLabel: "Camera backend", trademarkNotice: "An independent camera monitor.")
}

private final class MonitorResourceToken {}
enum MonitorResources {
    static let bundle = Bundle(for: MonitorResourceToken.self)
    private static let registerOnce: Void = {
        guard let enumerator = FileManager.default.enumerator(
            at: bundle.bundleURL, includingPropertiesForKeys: nil) else { return }
        for case let url as URL in enumerator where ["ttf", "otf"].contains(url.pathExtension) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()
    static func registerFonts() { _ = registerOnce }
}

/// Public seam: new brand apps inherit the entire shell with these two inputs.
@MainActor
public struct MonitorAppRoot: View {
    private let backend: any CameraBackend

    public init(brand: MonitorBrand, backend: any CameraBackend) {
        MonitorIdentity.current = brand
        MonitorResources.registerFonts()
        self.backend = backend
    }

    public var body: some View {
        AppRoot(backend: backend)
            .tint(MonitorIdentity.current.accent)
            .statusBarHidden(true)
    }
}
