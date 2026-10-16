import OpenCineAppUITesting
import OpenCineCore
import XCTest

/// The bundle's principal class (`NSPrincipalClass` in project.yml), created before any test runs.
/// It declares what the review body lays out: `OsmoMonitorPresentation.capabilities` for the Luna
/// the review stages (its gimbal with head tracking, zoom, focus and timecode, no audio levels, no
/// iris, plus the app's clip delete, clip star and internet hop). A UI test bundle cannot link the
/// app, so the value is declared here and the scenarios derive from it.
final class ConformanceApp: NSObject {
    override init() {
        ConformanceProfile.current = ConformanceProfile(
            app: "OpenInstaCine",
            capabilities: MonitorLayoutCapabilities(
                gimbal: true, zoom: true, focus: true, iris: false, audio: false, headTracking: true,
                clipDelete: true, clipStar: true, requiresInternetHop: true, timecode: true))
        super.init()
    }
}

// The conformance scenarios every app runs (OpenCine docs/conformance/SCENARIOS.md).
final class GalleryRoundTrip: OpenCineAppUITesting.GalleryRoundTrip {}
final class ShareRoundTrip: OpenCineAppUITesting.ShareRoundTrip {}
final class ConfirmationCancel: OpenCineAppUITesting.ConfirmationCancel {}
final class ChromeEditReturn: OpenCineAppUITesting.ChromeEditReturn {}
final class AccessibilityTraversal: OpenCineAppUITesting.AccessibilityTraversal {}
final class ConformanceCoverageTests: OpenCineAppUITesting.ConformanceCoverageTests {}
