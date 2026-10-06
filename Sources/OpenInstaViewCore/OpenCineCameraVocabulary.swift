// The camera control vocabulary (modes, ISO, formats, zoom, status, media listing, LUT choice,
// the live-tap ceiling) lives in OpenCine's OpenCineCameraVocabulary, shared with OpenPocketCine.
// Re-exported so app and facade call sites keep importing only this module. This app's bundled
// I-Log look stays here.
@_exported import OpenCineCameraVocabulary

/// The vocabulary's per-source live-tap ceiling. Declared here so it shadows OpenCineMedia's base
/// class of the same name for every file that imports this module.
public typealias ScopeExposureCeiling = OpenCineCameraVocabulary.ScopeExposureCeiling

// MARK: - Official Rec.709 looks for the 709 false-colour reading

extension LiveColorScience {
    /// Grey axis (33 points) of the bundled Luna I-Log to Rec.709 (BT.1886) s33 v2 cube.
    static let iLogRec709LookCurve = [
        0.0011, 0.0011, 0.0011, 0.0050, 0.0291, 0.0509, 0.0733, 0.0996, 0.1309, 0.1673,
        0.2093, 0.2563, 0.3080, 0.3636, 0.4216, 0.4813, 0.5402, 0.5974, 0.6525, 0.7045,
        0.7530, 0.7982, 0.8388, 0.8751, 0.9065, 0.9325, 0.9528, 0.9680, 0.9791, 0.9871,
        0.9918, 0.9958, 0.9994,
    ]

    /// Luma of the grey axis (33 points) of the official Rec.709 cubes: DJI's (`DJILook`) and
    /// the bundled Luna I-Log cube. Curves without an official look (Rec.709, HLG) return `nil`
    /// and stay on the signal.
    public static func rec709LookCurve(_ transfer: MonitorTransfer) -> [Double]? {
        transfer == .ilog ? iLogRec709LookCurve : DJILook.rec709LookCurve(transfer)
    }

    /// Video level (0…100 IRE) of an encoded neutral code through the official look.
    public static func rec709LookIRE(encoded: Double, transfer: MonitorTransfer) -> Double? {
        rec709LookIRE(encoded: encoded, lookCurve: rec709LookCurve(transfer))
    }

    /// True when the 709 reading applies: the operator picked 709 and this curve has an
    /// official Rec.709 look.
    public static func readsThroughLook(transfer: MonitorTransfer, rec709: Bool) -> Bool {
        readsThroughLook(lookCurve: rec709LookCurve(transfer), rec709: rec709)
    }

    /// ``falseColorReading(encoded:transfer:rec709:lookCurve:scale:)`` through the official look.
    public static func falseColorReading(
        encoded: Double, transfer: MonitorTransfer, rec709: Bool,
        scale: LiveFalseColorScale = .ire
    ) -> (encoded: Double, transfer: MonitorTransfer) {
        falseColorReading(
            encoded: encoded, transfer: transfer, rec709: rec709,
            lookCurve: rec709LookCurve(transfer), scale: scale)
    }

    /// ``falseColorClip(scale:transfer:rec709:lookCurve:clipEncoded:)`` for a source whose
    /// live ceiling for `transfer` is `clipByte` (see ``ScopeExposureCeiling``).
    public static func falseColorClip(
        scale: LiveFalseColorScale, transfer: MonitorTransfer, rec709: Bool, clipByte: Int
    ) -> (transfer: MonitorTransfer, ceiling: Double) {
        falseColorClip(
            scale: scale, transfer: transfer, rec709: rec709,
            lookCurve: rec709LookCurve(transfer), clipEncoded: Double(clipByte) / 255)
    }
}
