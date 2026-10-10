// The camera control vocabulary (modes, ISO, formats, zoom, status, media listing, LUT choice,
// the portable live-tap ceiling contract) lives in OpenCine's OpenCineCameraVocabulary, shared with OpenPocketCine.
// Re-exported so app and facade call sites keep importing only this module. This app's bundled
// I-Log look stays here.
@_exported import OpenCineCameraVocabulary
import OpenCineMedia

/// This source adapter supplies Luna's profile to the portable ceiling math.
public typealias ScopeExposureCeiling = LunaScopeExposureCeiling

// MARK: - Official Rec.709 looks for the 709 false-colour reading

extension LiveColorScience {
    /// Luna supplies its bundled I-Log samples; other transfers stay on the source signal.
    public static func rec709LookCurve(_ transfer: MonitorTransfer,
        sourceProfile: MonitorColorSourceProfile = LunaMonitorColorProfile.value) -> [Double]? {
        sourceProfile.rec709LookCurves[transfer]
    }

    /// Video level (0…100 IRE) of an encoded neutral code through the official look.
    public static func rec709LookIRE(encoded: Double, transfer: MonitorTransfer,
        sourceProfile: MonitorColorSourceProfile = LunaMonitorColorProfile.value) -> Double? {
        rec709LookIRE(encoded: encoded, lookCurve: rec709LookCurve(transfer, sourceProfile: sourceProfile))
    }

    /// True when the 709 reading applies: the operator picked 709 and this curve has an
    /// official Rec.709 look.
    public static func readsThroughLook(transfer: MonitorTransfer, rec709: Bool,
        sourceProfile: MonitorColorSourceProfile = LunaMonitorColorProfile.value) -> Bool {
        readsThroughLook(lookCurve: rec709LookCurve(transfer, sourceProfile: sourceProfile), rec709: rec709)
    }

    /// ``falseColorReading(encoded:transfer:rec709:lookCurve:scale:)`` through the official look.
    public static func falseColorReading(
        encoded: Double, transfer: MonitorTransfer, rec709: Bool,
        scale: LiveFalseColorScale = .ire,
        sourceProfile: MonitorColorSourceProfile = LunaMonitorColorProfile.value
    ) -> (encoded: Double, transfer: MonitorTransfer) {
        falseColorReading(
            encoded: encoded, transfer: transfer, rec709: rec709,
            lookCurve: rec709LookCurve(transfer, sourceProfile: sourceProfile), scale: scale)
    }

    /// ``falseColorClip(scale:transfer:rec709:lookCurve:clipEncoded:)`` for a source whose
    /// live ceiling for `transfer` is `clipByte` (see ``ScopeExposureCeiling``).
    public static func falseColorClip(
        scale: LiveFalseColorScale, transfer: MonitorTransfer, rec709: Bool, clipByte: Int,
        sourceProfile: MonitorColorSourceProfile = LunaMonitorColorProfile.value
    ) -> (transfer: MonitorTransfer, ceiling: Double) {
        falseColorClip(
            scale: scale, transfer: transfer, rec709: rec709,
            lookCurve: rec709LookCurve(transfer, sourceProfile: sourceProfile), clipEncoded: Double(clipByte) / 255)
    }
}
