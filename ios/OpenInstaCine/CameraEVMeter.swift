import MonitorUI
import OpenPocketViewCore
import SwiftUI

/// Fixed camera telemetry chrome. It has no assist state, gestures or pixel sampling.
enum CameraEVMeter {
    static func frame(in feed: CGRect, avoiding obstacle: CGRect? = nil) -> CGRect {
        let width: CGFloat = 28
        let minimumHeight: CGFloat = 72
        guard feed.width >= width + 12, feed.height >= minimumHeight + 12 else { return .zero }
        let x = feed.minX + 6
        let top = feed.minY + 6
        let bottom = feed.maxY - 6
        let preferredY = feed.midY - 16 - min(180, bottom - top) / 2
        func fitting(top: CGFloat, bottom: CGFloat) -> CGRect {
            let height = min(180, bottom - top)
            guard height >= minimumHeight else { return .zero }
            return CGRect(
                x: x, y: min(max(preferredY, top), bottom - height), width: width, height: height)
        }
        let preferred = fitting(top: top, bottom: bottom)
        guard let obstacle, !obstacle.isEmpty,
            obstacle.minX < preferred.maxX, obstacle.maxX > preferred.minX,
            obstacle.minY - 12 < preferred.maxY, obstacle.maxY + 12 > preferred.minY
        else { return preferred }
        // Move up before shortening; the expanded palette may occupy the whole left edge.
        let above = fitting(top: top, bottom: min(bottom, obstacle.minY - 12))
        if !above.isEmpty { return above }
        return fitting(top: max(top, obstacle.maxY + 12), bottom: bottom)
    }
}

struct CameraEVMeterOverlay: View {
    @Environment(AppModel.self) private var model
    let feed: CGRect
    var avoiding: CGRect?

    /// Image-estimated EV from the live picture, for cameras that report none.
    private var pictureEV: EvComp? {
        guard model.assist.evMeterFromPicture else { return nil }
        let bundle = model.monitorSamples.bundle
        guard let picture = NDFilterRecommendation.pictureStops(
            lumaHistogram: bundle.samples.histogramLuma, transfer: bundle.transfer)
        else { return nil }
        let session = model.session
        let status = session.status
        let stops = session.pictureEV.stops(
            picture: picture, context: session.pictureEVContext(transfer: bundle.transfer),
            evComp: status.expoMode == .auto ? status.evComp.map { Double($0.thirds) / 3 } : nil,
            now: ProcessInfo.processInfo.systemUptime)
        return stops.value.map { EvComp(thirds: Int(($0 * 3).rounded())) }
    }

    var body: some View {
        let frame = CameraEVMeter.frame(in: feed, avoiding: avoiding)
        let recovering = model.session.sessionRecovery.isRecovering || model.session.feedRecovering
        let reported = model.session.status.meteredEv
        let reading = ExposureMeterReading(
            cameraValue: recovering ? nil : reported ?? pictureEV,
            imageEstimated: reported == nil)
        MonitorExposureGauge(value: reading.label, needleFraction: reading.needleFraction)
            .frame(width: frame.width, height: frame.height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("EV meter")
            .accessibilityValue(reading.accessibilityValue)
            .accessibilityIdentifier("monitor.ev.meter")
            .accessibilityHidden(frame.isEmpty)
            .position(x: frame.midX, y: frame.midY)
            .opacity(frame.isEmpty ? 0 : 1)
            .allowsHitTesting(false)
    }
}
