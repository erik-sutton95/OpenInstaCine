import OpenCineCameraVocabulary
import MonitorPresentation
import XCTest

@testable import OpenInstaCine

/// The facade's motion and sharing choices go through the shared owners under the keys and
/// defaults this app has always used, so every stored choice carries over.
final class OperatorPreferencesAdoptionTests: XCTestCase {
    private let suffixes = [
        "HeadTrackingEnabled", "GimbalStickSensitivity", "VirtualJoystickInvertPan",
        "VirtualJoystickInvertTilt", "VirtualJoystickDeadzonePercent", "VirtualJoystickResponseCurve",
        "VirtualJoystickSize", "GimbalRamp", "GimbalDoubleTap", "ShareThisFeed", "ControlRequests",
        "BroadcastPriority", "AssistToolUsage.v1",
    ]

    private func preservingStoredChoices(_ body: () throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let keys = suffixes.map { "OpenInstaCine." + $0 }
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }
        keys.forEach(defaults.removeObject(forKey:))
        try body()
    }

    func testAbsentChoicesReadTheExistingDefaultsWithoutWriting() {
        preservingStoredChoices {
            XCTAssertFalse(OperatorPrefs.headTrackingEnabled)
            XCTAssertEqual(OperatorPrefs.gimbalStickSensitivity, 4)
            XCTAssertFalse(OperatorPrefs.virtualJoystickInvertPan || OperatorPrefs.virtualJoystickInvertTilt)
            XCTAssertEqual(OperatorPrefs.virtualJoystickDeadzonePercent, 8)
            XCTAssertEqual(OperatorPrefs.virtualJoystickResponseCurve, .standard)
            XCTAssertEqual(OperatorPrefs.virtualJoystickSize, .medium)
            XCTAssertEqual(OperatorPrefs.gimbalRamp, .off)
            XCTAssertEqual(OperatorPrefs.gimbalDoubleTap, .recenter)
            XCTAssertFalse(OperatorPrefs.shareThisFeed)
            XCTAssertTrue(OperatorPrefs.controlRequests)
            XCTAssertEqual(OperatorPrefs.broadcastPriority, 0)
            XCTAssertEqual(OperatorPrefs.assistToolUsage, MonitorToolUsage())
            for suffix in suffixes {
                XCTAssertNil(UserDefaults.standard.object(forKey: "OpenInstaCine." + suffix), suffix)
            }
        }
    }

    func testStoredChoicesKeepTheirKeysRangesAndUnknownRawValues() {
        preservingStoredChoices {
            let defaults = UserDefaults.standard
            defaults.set(false, forKey: "OpenInstaCine.ControlRequests")
            defaults.set(9, forKey: "OpenInstaCine.BroadcastPriority")
            defaults.set(99, forKey: "OpenInstaCine.GimbalStickSensitivity")
            defaults.set(-4, forKey: "OpenInstaCine.VirtualJoystickDeadzonePercent")
            defaults.set("future-curve", forKey: "OpenInstaCine.VirtualJoystickResponseCurve")
            defaults.set(7, forKey: "OpenInstaCine.GimbalRamp")
            XCTAssertFalse(OperatorPrefs.controlRequests)
            XCTAssertEqual(OperatorPrefs.broadcastPriority, 3)
            XCTAssertEqual(OperatorPrefs.gimbalStickSensitivity, 5)
            XCTAssertEqual(OperatorPrefs.virtualJoystickDeadzonePercent, 0)
            XCTAssertEqual(OperatorPrefs.virtualJoystickResponseCurve, .standard)
            XCTAssertEqual(OperatorPrefs.gimbalRamp, .off)
            XCTAssertEqual(defaults.string(forKey: "OpenInstaCine.VirtualJoystickResponseCurve"), "future-curve",
                "Reading an unknown curve leaves the stored value for the build that wrote it")

            OperatorPrefs.headTrackingEnabled = true
            OperatorPrefs.gimbalStickSensitivity = 0
            OperatorPrefs.virtualJoystickSize = .large
            OperatorPrefs.gimbalDoubleTap = .level
            OperatorPrefs.broadcastPriority = 2
            OperatorPrefs.shareThisFeed = true
            XCTAssertTrue(defaults.bool(forKey: "OpenInstaCine.HeadTrackingEnabled"))
            XCTAssertEqual(defaults.integer(forKey: "OpenInstaCine.GimbalStickSensitivity"), 1)
            XCTAssertEqual(defaults.string(forKey: "OpenInstaCine.VirtualJoystickSize"), "large")
            XCTAssertEqual(defaults.integer(forKey: "OpenInstaCine.GimbalDoubleTap"), GimbalDoubleTap.level.rawValue)
            XCTAssertEqual(defaults.integer(forKey: "OpenInstaCine.BroadcastPriority"), 2)
            XCTAssertTrue(defaults.bool(forKey: "OpenInstaCine.ShareThisFeed"))

            var usage = MonitorToolUsage()
            usage.recordUse(of: "WAVE", at: 1_000)
            OperatorPrefs.assistToolUsage = usage
            XCTAssertEqual(OperatorPrefs.assistToolUsage, usage)
            XCTAssertNotNil(defaults.data(forKey: "OpenInstaCine.AssistToolUsage.v1"))
        }
    }
}
