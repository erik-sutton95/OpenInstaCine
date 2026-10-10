import AVFoundation
import MonitorUI
import OSLog
import OpenInstaViewCore
import OpenCineApple
import SwiftUI

private let playbackAudioLogger = Logger(
    subsystem: "OpenInstaCine", category: "media-playback-audio")

/// Configures `AVAudioSession` for in-app clip playback so audio plays through the mute switch.
enum MediaPlaybackAudioSession {
    @MainActor static func makeMeter() -> MonitorPlaybackAudioMeterRuntime {
        MonitorPlaybackAudioMeterRuntime(onTapFailure: tapFailure)
    }
    nonisolated static func tapFailure(_ status: Int32) {
        playbackAudioLogger.error("MTAudioProcessingTapCreate failed: \(status)")
    }
    nonisolated static func audioFailure(_ message: String) {
        playbackAudioLogger.error("Playback audio session failed: \(message, privacy: .public)")
    }
}
