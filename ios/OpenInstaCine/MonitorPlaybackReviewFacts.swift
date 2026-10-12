#if DEBUG && targetEnvironment(simulator)
import AVFoundation
import Observation
import OpenCineApple
import SwiftUI
import UIKit

/// SIMULATED review only. Reads the already-mounted native host; never owns or drives it.
@MainActor @Observable
private final class MonitorPlaybackReviewObserver {
    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private weak var host: MonitorPlaybackFeedHost?
    @ObservationIgnored private weak var player: AVPlayer?
    @ObservationIgnored private var lastItem: String?
    @ObservationIgnored private var retiredItems = Set<String>()
    @ObservationIgnored private var sequence = 0
    @ObservationIgnored private let evidenceURL: URL?
    var json = "{}"

    init(model: AppModel) {
        self.model = model
        if let path = ProcessInfo.processInfo.environment["OPV_UI_REVIEW_PLAYBACK_FACTS"], path.hasPrefix("/") {
            evidenceURL = URL(fileURLWithPath: path)
        } else { evidenceURL = nil }
    }
    private func identity(_ object: AnyObject?) -> String? { object.map { String(describing: ObjectIdentifier($0)) } }
    private func mountedHosts(_ view: UIView, in window: UIWindow) -> [MonitorPlaybackFeedHost] {
        guard !view.isHidden, view.alpha > 0 else { return [] }
        var result: [MonitorPlaybackFeedHost] = []
        if let candidate = view as? MonitorPlaybackFeedHost,
            candidate.window === window,
            !candidate.convert(candidate.bounds, to: window).intersection(window.bounds).isEmpty {
            result.append(candidate)
        }
        for child in view.subviews { result.append(contentsOf: mountedHosts(child, in: window)) }
        return result
    }
    func read() {
        guard let model else { return }
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows).filter { !$0.isHidden && $0.alpha > 0 && !$0.bounds.isEmpty }
        let candidates = windows.flatMap { mountedHosts($0, in: $0) }
        if candidates.count == 1, let mounted = candidates.first {
            host = mounted; player = mounted.playerLayer.player
        }
        let item = player?.currentItem
        let itemID = identity(item)
        let matched = candidates.count == 1 ?
            item != nil && host === candidates.first && host?.playerLayer.player === player && player?.currentItem === item :
            !windows.isEmpty && candidates.isEmpty && item == nil
        // Ambiguity or a hidden live host supplies no authoritative item or retirement observation.
        if matched {
            if let lastItem, itemID != lastItem { retiredItems.insert(lastItem) }
            lastItem = itemID
        }
        let library = model.session.mediaLibrary
        let service = MonitorUIReview.mediaService
        let null = NSNull()
        func value<T>(_ optional: T?) -> Any { optional.map { $0 as Any } ?? null }
        let time = player.map { CMTimeGetSeconds($0.currentTime()) }.flatMap { $0.isFinite ? $0 : nil }
        let duration = item.map { CMTimeGetSeconds($0.duration) }.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        sequence += 1
        let values: [String: Any] = [
            "sequence": sequence, "monotonic": ProcessInfo.processInfo.systemUptime,
            "matched": matched, "hostCandidates": candidates.count,
            "mounted": matched && candidates.count == 1,
            "library": value(identity(library)), "lifetime": value(library?.lifetimeToken.uuidString),
            "browsing": library?.browsing ?? false, "bound": library?.binding != nil,
            "galleryOrder": value(library?.displayedRecords.map { $0.asset.filename }),
            "opens": service.opens, "closes": service.browse.closes,
            "cover": model.shell.cover == .media ? "media" as Any : null,
            "host": value(identity(host)), "player": value(identity(player)),
            "item": value(itemID), "file": value((item?.asset as? AVURLAsset)?.url.lastPathComponent),
            "ready": host?.playerLayer.isReadyForDisplay ?? false,
            "rate": value(player.map { Double($0.rate) }), "time": value(time), "duration": value(duration),
            "width": value(item.map { Double($0.presentationSize.width) }),
            "height": value(item.map { Double($0.presentationSize.height) }),
            "retiredItems": retiredItems.sorted(),
        ]
        if let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]),
            let text = String(data: data, encoding: .utf8) {
            if json != text { json = text }
            // Opt-in fixture output only; atomic publication never changes the player or its UI.
            if let evidenceURL { try? data.write(to: evidenceURL, options: [.atomic]) }
        }
    }
}

@MainActor struct MonitorPlaybackReviewFacts: View {
    @State private var observer: MonitorPlaybackReviewObserver
    init(model: AppModel) { _observer = State(initialValue: MonitorPlaybackReviewObserver(model: model)) }
    var body: some View {
        Text("SIMULATED actual-player facts")
            .font(.system(size: 1)).foregroundStyle(.clear).frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("monitor.review.playback.facts")
            .accessibilityLabel("SIMULATED actual-player facts")
            .accessibilityValue(observer.json)
            .task {
                while !Task.isCancelled {
                    observer.read()
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                }
            }
    }
}
#endif
