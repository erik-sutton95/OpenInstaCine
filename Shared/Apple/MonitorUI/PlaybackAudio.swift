import AVFoundation
import CoreAudio
import Accelerate
import MediaToolbox
import OSLog
import OpenPocketViewCore
import SwiftUI

private let playbackAudioLogger = Logger(
    subsystem: "com.opencapture.monitor", category: "media-playback-audio")

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

/// Lock-guarded per-channel linear peak accumulator shared between the `MTAudioProcessingTap`
/// render-thread callbacks and the main-actor polling loop.
final class AudioLevelTapBox: @unchecked Sendable {
    private struct State {
        var leftPeak: Float = 0
        var rightPeak: Float = 0
        var isFloat32 = false
        var isInterleaved = false
        var channelCount = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func setFormat(_ description: AudioStreamBasicDescription) {
        state.withLock {
            $0.isFloat32 =
                description.mFormatID == kAudioFormatLinearPCM
                && description.mFormatFlags & kAudioFormatFlagIsFloat != 0
                && description.mBitsPerChannel == 32
            $0.isInterleaved = description.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
            $0.channelCount = Int(description.mChannelsPerFrame)
        }
    }

    var format: (isFloat32: Bool, isInterleaved: Bool, channelCount: Int) {
        state.withLock { ($0.isFloat32, $0.isInterleaved, $0.channelCount) }
    }

    func ingest(left: Float, right: Float) {
        state.withLock {
            $0.leftPeak = max($0.leftPeak, left)
            $0.rightPeak = max($0.rightPeak, right)
        }
    }

    func readAndReset() -> (left: Float, right: Float) {
        state.withLock { current in
            let peaks = (current.leftPeak, current.rightPeak)
            current.leftPeak = 0
            current.rightPeak = 0
            return peaks
        }
    }
}

enum AudioLevelTapFactory {
    static func makeTap(box: AudioLevelTapBox) -> MTAudioProcessingTap? {
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque()),
            init: { _, clientInfo, tapStorageOut in
                tapStorageOut.pointee = clientInfo
            },
            finalize: { tap in
                Unmanaged<AudioLevelTapBox>.fromOpaque(MTAudioProcessingTapGetStorage(tap))
                    .release()
            },
            prepare: { tap, _, processingFormat in
                Unmanaged<AudioLevelTapBox>.fromOpaque(MTAudioProcessingTapGetStorage(tap))
                    .takeUnretainedValue()
                    .setFormat(processingFormat.pointee)
            },
            unprepare: nil,
            process: { tap, numberFrames, _, bufferListInOut, numberFramesOut, flagsOut in
                let status = MTAudioProcessingTapGetSourceAudio(
                    tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut)
                guard status == noErr else { return }
                let box = Unmanaged<AudioLevelTapBox>
                    .fromOpaque(MTAudioProcessingTapGetStorage(tap))
                    .takeUnretainedValue()
                let format = box.format
                guard format.isFloat32 else { return }
                let buffers = UnsafeMutableAudioBufferListPointer(bufferListInOut)
                var left: Float = 0
                var right: Float = 0
                if format.isInterleaved, let buffer = buffers.first, let data = buffer.mData {
                    let channels = max(1, format.channelCount)
                    let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                    let frames = sampleCount / channels
                    guard frames > 0 else { return }
                    let samples = data.assumingMemoryBound(to: Float.self)
                    vDSP_maxmgv(samples, vDSP_Stride(channels), &left, vDSP_Length(frames))
                    if channels > 1 {
                        vDSP_maxmgv(
                            samples + 1, vDSP_Stride(channels), &right, vDSP_Length(frames))
                    } else {
                        right = left
                    }
                } else {
                    for (index, buffer) in buffers.enumerated() where index < 2 {
                        guard let data = buffer.mData else { continue }
                        let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                        guard count > 0 else { continue }
                        var peak: Float = 0
                        vDSP_maxmgv(
                            data.assumingMemoryBound(to: Float.self), 1, &peak,
                            vDSP_Length(count))
                        if index == 0 { left = peak } else { right = peak }
                    }
                    if buffers.count < 2 { right = left }
                }
                box.ingest(left: left, right: right)
            }
        )
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
        guard status == noErr, let tap else {
            Unmanaged.passUnretained(box).release()
            playbackAudioLogger.error("MTAudioProcessingTapCreate failed: \(status)")
            return nil
        }
        return tap
    }
}

@MainActor
final class PlaybackAudioMeterController {
    private let box = AudioLevelTapBox()
    private var pollTask: Task<Void, Never>?
    private var attachGeneration = 0

    func attach(to item: AVPlayerItem) {
        attachGeneration += 1
        let generation = attachGeneration
        Task { @MainActor [weak self, weak item] in
            guard let self, let item else { return }
            guard let track = try? await item.asset.loadTracks(withMediaType: .audio).first
            else { return }
            guard generation == self.attachGeneration else { return }
            guard let tap = AudioLevelTapFactory.makeTap(box: self.box) else { return }
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.audioTapProcessor = tap
            let mix = AVMutableAudioMix()
            mix.inputParameters = [parameters]
            item.audioMix = mix
        }
    }

    func detach(from item: AVPlayerItem?) {
        attachGeneration += 1
        item?.audioMix = nil
        _ = box.readAndReset()
    }

    func startPolling(onLevels: @escaping @MainActor (AudioMeterLevels) -> Void) {
        pollTask?.cancel()
        pollTask = Task { @MainActor [box] in
            var levels = AudioMeterLevels.silent
            var lastTick = CFAbsoluteTimeGetCurrent()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(42))
                if Task.isCancelled { return }
                let now = CFAbsoluteTimeGetCurrent()
                let dt = now - lastTick
                lastTick = now
                let peaks = box.readAndReset()
                levels = AudioMeterLevels(
                    left: AudioMeterBallistics.step(
                        levels.left, peakLinear: Double(peaks.left), dt: dt),
                    right: AudioMeterBallistics.step(
                        levels.right, peakLinear: Double(peaks.right), dt: dt))
                onLevels(levels)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
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
