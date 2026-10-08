import Foundation
import MonitorPresentation
import OpenCineAppKitApple
import OpenCineApple
import OpenCineMedia
import OpenInstaViewCore

typealias MonitorBackdropRenderer = OpenCineAppKitApple.MonitorBackdropRenderer
typealias MonitorVideoBackdropRenderer = OpenCineAppKitApple.MonitorVideoBackdropRenderer
typealias MonitorVideoBackdropSource = OpenCineAppKitApple.MonitorVideoBackdropSource
typealias MonitorVideoBackdropConfiguration = OpenCineAppKitApple.MonitorVideoBackdropConfiguration

extension OpenCineAppKitApple.MonitorVideoBackdropRenderer {
    convenience init(clock: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
        minimumInterval: @escaping @Sendable () -> Double = { MonitorBackdropPolicy.minimumInterval },
        operation: Operation? = nil) {
        self.init(lookCurves: LunaMonitorColorProfile.value.rec709LookCurves,
            clock: clock, minimumInterval: minimumInterval, operation: operation)
    }
}
