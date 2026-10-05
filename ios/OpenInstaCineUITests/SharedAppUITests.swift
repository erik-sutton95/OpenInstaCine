import OpenCineAppUITesting

// The UI tests every app shares (OpenCine `OpenCineAppUITesting`) run as this app's tests.
final class EVMeterUIFlowTests: OpenCineAppUITesting.EVMeterUIFlowTests {}
final class FeedStressTests: OpenCineAppUITesting.FeedStressTests {}
final class MotionUIFlowTests: OpenCineAppUITesting.MotionUIFlowTests {
    // A Luna move holds one zoom, and a Luna body zooms while recording (no D-Log2 color hop).
    override var zoomProgramUnavailableReason: String { "Luna moves cannot change zoom. Set every point at one zoom." }
    override var recordingZoomLockNote: String? { nil }
}
final class PerfSoakTests: OpenCineAppUITesting.PerfSoakTests {}
final class PhysicalDesqueezeTests: OpenCineAppUITesting.PhysicalDesqueezeTests {}
final class PhysicalMotionZoomTests: OpenCineAppUITesting.PhysicalMotionZoomTests {}
final class PhysicalNavigationTests: OpenCineAppUITesting.PhysicalNavigationTests {}
final class PhysicalReferenceAppTests: OpenCineAppUITesting.PhysicalReferenceAppTests {}
final class PhysicalShootingModeTests: OpenCineAppUITesting.PhysicalShootingModeTests {}
final class PhysicalVirtualJoystickTests: OpenCineAppUITesting.PhysicalVirtualJoystickTests {}
final class ShareUIFlowTests: OpenCineAppUITesting.ShareUIFlowTests {}
