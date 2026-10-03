import AVFoundation
import OSLog
import OpenPocketViewCore
import OpenCineApple
import SwiftUI

private let playbackAudioLogger = Logger(
    subsystem: "OpenInstaCine", category: "media-playback-audio")

/// Configures `AVAudioSession` for in-app clip playback so audio plays through the mute switch.
enum MediaPlaybackAudioSession {
    static func activateForPlayback() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            playbackAudioLogger.error(
                "Failed to activate playback audio session: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    static func deactivateAfterPlayback() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            playbackAudioLogger.error(
                "Failed to deactivate playback audio session: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}

/// App audio policy maps an absent source to empty meter bars and keeps its log namespace.
@MainActor
final class PlaybackAudioMeterController {
    private let runtime = MonitorPlaybackAudioMeterRuntime(onTapFailure: { status in
        playbackAudioLogger.error("MTAudioProcessingTapCreate failed: \(status)")
    })
    func attach(to item: AVPlayerItem) { runtime.attach(to: item) }
    func detach(from item: AVPlayerItem?) { runtime.detach(from: item) }
    func startPolling(onLevels: @escaping @MainActor (AudioMeterLevels) -> Void) {
        runtime.startPolling { onLevels($0 ?? .silent) }
    }
    func stopPolling() { runtime.stopPolling() }
}

/// Playback assist chip: same icon + label as live, gated on `playbackVisibleTools`.
struct PlaybackAssistToolButton: View {
    @Environment(AppModel.self) private var model
    let tool: LiveAssistTool
    var onConfigure: (LiveAssistTool) -> Void
    @State private var buildup: Task<Void, Never>?

    var body: some View {
        AssistToolChip(tool: tool, isOn: model.assist.isPlaybackVisible(tool), compact: true)
            .contentShape(Rectangle())
            .minTapTarget()
            .onTapGesture {
                model.assist.togglePlayback(tool)
            }
            .onLongPressGesture(minimumDuration: 0.25) {
                cancelBuildup()
                guard tool.hasConfiguration else { return }
                AssistBarHaptics.confirm()
                onConfigure(tool)
            } onPressingChanged: { pressing in
                guard tool.hasConfiguration else { return }
                if pressing {
                    buildup = AssistBarHaptics.buildup()
                } else {
                    cancelBuildup()
                }
            }
            .accessibilityLabel(tool.title)
    }

    private func cancelBuildup() {
        buildup?.cancel()
        buildup = nil
    }
}
