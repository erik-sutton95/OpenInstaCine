import Foundation
import MonitorCore

extension FacePriorityExposure {
    /// Next EV third, or `nil` when already inside the deadband / unchanged.
    public static func nextEV(
        current: EvComp,
        encoded: Double,
        transfer: MonitorTransfer
    ) -> EvComp? {
        let stops = LiveColorScience.stops(encoded: encoded, transfer: transfer)
        guard stops.isFinite else { return nil }
        if abs(stops) < deadbandStops { return nil }
        var deltaThirds = Int((-stops * 3).rounded())
        if deltaThirds == 0 { return nil }
        deltaThirds = min(max(deltaThirds, -maxStepThirds), maxStepThirds)
        let next = EvComp(thirds: current.thirds + deltaThirds)
        return next == current ? nil : next
    }

    /// EV to write when Face Priority turns off.
    public static func restoreEV(saved: EvComp?) -> EvComp {
        saved ?? .zero
    }
}
