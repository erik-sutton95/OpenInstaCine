import CoreVideo
import Foundation
import OpenCineApple
import OpenCineMedia
import OpenInstaViewCore

/// The app supplies source-qualified look curves; the native owner retains admission and CI work.
extension MonitorInspectorImageRenderer {
    convenience init(now: @escaping Clock = { DispatchTime.now().uptimeNanoseconds }, operation: RenderOperation? = nil,
        workerQoS: DispatchQoS = MonitorInspectorImageRenderer.defaultWorkerQoS) {
        let curves = Dictionary(uniqueKeysWithValues: MonitorTransfer.allCases.compactMap { transfer in
            LiveColorScience.rec709LookCurve(transfer).map { (transfer, $0) }
        })
        self.init(lookCurves: curves, now: now, operation: operation, workerQoS: workerQoS)
    }
}
