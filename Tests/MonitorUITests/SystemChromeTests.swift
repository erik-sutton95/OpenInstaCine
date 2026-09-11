import XCTest

@testable import MonitorUI

/// iPad used to keep the system time / battery bar. The hosting controller
/// prefers hidden, and the plist has an iPad-specific key for launch.
final class SystemChromeTests: XCTestCase {
    func testInfoPlistHidesTheSystemStatusBarOnIPhoneAndIPad() throws {
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "UIStatusBarHidden") as? Bool, true)
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "UIViewControllerBasedStatusBarAppearance")
                as? Bool, true)
        // `object(forInfoDictionaryKey:)` drops `~ipad` variants on iPhone.
        // The merged Info-Frameio.plist is what iPad reads at launch.
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Apps/Apple/OpenInstaCine/Info.plist")
        let raw = try XCTUnwrap(NSDictionary(contentsOf: source))
        XCTAssertEqual(raw["UIStatusBarHidden"] as? Bool, true)
        XCTAssertEqual(raw["UIStatusBarHidden~ipad"] as? Bool, true)
    }
}
