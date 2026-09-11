import Foundation

/// One channel of a broadcast-style dBFS bar meter: the decaying level bar plus its peak-hold
/// marker. Values are dBFS clamped to `AudioMeterBallistics.floorDB`…0.
/// Ported from OpenZCine `AudioLevelMeter`.
public struct AudioMeterChannel: Equatable, Sendable {
    /// Bar level in dBFS.
    public var levelDB: Double
    /// Peak-hold marker in dBFS (never reads below `levelDB`).
    public var peakDB: Double
    /// Seconds the current peak marker has been held — drives the hold-then-decay release.
    public var peakAge: Double

    public init(
        levelDB: Double = AudioMeterBallistics.floorDB,
        peakDB: Double = AudioMeterBallistics.floorDB,
        peakAge: Double = 0
    ) {
        self.levelDB = levelDB
        self.peakDB = peakDB
        self.peakAge = peakAge
    }

    public static let silent = AudioMeterChannel()
}

/// Stereo readout published to the live audio-levels panel.
public struct AudioMeterLevels: Equatable, Sendable {
    /// Shared 15-segment indicator scale, from silence (0) to peak (14).
    public static let maxSegment = 14
    public var left: AudioMeterChannel
    public var right: AudioMeterChannel

    public init(left: AudioMeterChannel, right: AudioMeterChannel) {
        self.left = left
        self.right = right
    }

    public static let silent = AudioMeterLevels(left: .silent, right: .silent)
}

extension AudioMeterLevels {
    /// Maps a 15-segment camera indicator onto the meter's dBFS scale. Segment 0 sits at the
    /// meter floor (silence), segment 14 at 0 dBFS, spaced evenly in dB between. Same mapping
    /// OpenZCine uses for the Nikon LiveViewObject sound bytes.
    public init(segments currentLeft: Int, currentRight: Int, peakLeft: Int, peakRight: Int) {
        func decibels(_ segment: Int) -> Double {
            let fraction =
                Double(min(max(segment, 0), Self.maxSegment))
                / Double(Self.maxSegment)
            return AudioMeterBallistics.floorDB * (1 - fraction)
        }
        self.init(
            left: AudioMeterChannel(levelDB: decibels(currentLeft), peakDB: decibels(peakLeft)),
            right: AudioMeterChannel(levelDB: decibels(currentRight), peakDB: decibels(peakRight)))
    }
}

/// dBFS conversion and meter ballistics (instant attack, timed decay, peak hold). Pure — a
/// tap or subscribe snapshot supplies linear frame peaks and a wall-clock `dt`.
public enum AudioMeterBallistics {
    /// Meter floor — anything quieter renders as silence.
    public static let floorDB = -60.0
    /// Bar fall rate once the signal drops (dB per second) — fast but readable, PPM-style.
    public static let levelDecayPerSecond = 26.0
    /// How long a peak marker holds before it starts to fall.
    public static let peakHoldSeconds = 1.8
    /// Peak-marker fall rate once the hold expires (dB per second).
    public static let peakDecayPerSecond = 12.0

    /// Linear amplitude (0…1) → dBFS, clamped to `floorDB`…0.
    public static func decibels(fromLinear amplitude: Double) -> Double {
        guard amplitude > 0 else { return floorDB }
        return max(floorDB, min(0, 20 * log10(amplitude)))
    }

    /// Advances one channel by `dt` seconds, given the loudest linear sample amplitude observed
    /// since the previous step. The bar attacks instantly and decays at `levelDecayPerSecond`; the
    /// peak marker grabs new maxima, holds `peakHoldSeconds`, then falls at `peakDecayPerSecond`.
    public static func step(
        _ channel: AudioMeterChannel, peakLinear: Double, dt: Double
    ) -> AudioMeterChannel {
        let dt = max(0, dt)
        let incoming = decibels(fromLinear: peakLinear)
        var next = channel
        let decayed = max(floorDB, channel.levelDB - levelDecayPerSecond * dt)
        next.levelDB = max(incoming, decayed)
        if incoming >= channel.peakDB {
            next.peakDB = incoming
            next.peakAge = 0
        } else {
            next.peakAge = channel.peakAge + dt
            if next.peakAge > peakHoldSeconds {
                next.peakDB = max(floorDB, channel.peakDB - peakDecayPerSecond * dt)
            }
        }
        next.peakDB = max(next.peakDB, next.levelDB)
        return next
    }
}
