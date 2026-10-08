import OpenCineMedia

/// The bundled Luna I-Log look. No measured preview clip calibration has been supplied.
public enum LunaMonitorColorProfile {
    public static let iLogRec709LookCurve = [
        0.0011, 0.0011, 0.0011, 0.0050, 0.0291, 0.0509, 0.0733, 0.0996, 0.1309, 0.1673,
        0.2093, 0.2563, 0.3080, 0.3636, 0.4216, 0.4813, 0.5402, 0.5974, 0.6525, 0.7045,
        0.7530, 0.7982, 0.8388, 0.8751, 0.9065, 0.9325, 0.9528, 0.9680, 0.9791, 0.9871,
        0.9918, 0.9958, 0.9994,
    ]
    public static let value = MonitorColorSourceProfile(
        rec709LookCurves: [.ilog: iLogRec709LookCurve])
}

/// One Luna source uses generic ceiling math with only Luna's declared facts.
public final class LunaScopeExposureCeiling: OpenCineMedia.ScopeExposureCeiling, @unchecked Sendable {
    public static let sourceProfile = LunaMonitorColorProfile.value.clip
    public init() { super.init(profile: Self.sourceProfile) }
    public static func referenceClipByte(transfer: MonitorTransfer) -> Int {
        LunaScopeExposureCeiling().clipByte(transfer: transfer)
    }
}
