import OpenCineApple
import OpenCineDJI
import OpenCineMedia

@testable import OpenInstaCine

/// Original mixed-source goldens explicitly exercise a DJI preview, rather than Luna defaults.
typealias ScopeExposureCeiling = DJIScopeExposureCeiling

enum DeclaredDJIMonitorFixture {
    static var assistConfiguration: MonitorAssistConfiguration {
        var value = LiveAssistEngine.configuration
        value.clipProfile = DJIMonitorColorProfile.value.clip
        value.lookCurves = DJIMonitorColorProfile.value.rec709LookCurves
        value.inferTransfer = { DJIMonitorColorProfile.inferredTransfer(minByte: $0, maxByte: $1, fallback: $2) }
        return value
    }
}
