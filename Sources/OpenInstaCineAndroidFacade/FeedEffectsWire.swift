import Foundation
import OpenCineMedia
import OpenCineCameraVocabulary
import OpenInstaViewCore

/// Compatibility facade for original callers. The packer is stateless; its caller owns caching.
/// Luna colour identities are not mode bytes, so typed callers name the curve.
public enum FeedEffectsWire {
    public static let falseColorCubeSize = MonitorFeedEffectsWire.falseColorCubeSize
    public static let assistScalarCount = MonitorFeedEffectsWire.assistScalarCount

    /// The stored Android I-Log identifier (65536) is retained for original callers.
    public static let storedAndroidIlogCode = 65_536

    public static func monitorTransfer(colorModeCode: Int) -> MonitorTransfer {
        colorModeCode == storedAndroidIlogCode
            ? .ilog : MonitorFeedEffectsWire.monitorTransfer(colorModeCode: colorModeCode)
    }
    public static func falseColorScale(_ ordinal: Int) -> LiveFalseColorScale? {
        MonitorFeedEffectsWire.falseColorScale(ordinal)
    }
    public static func readsRec709Look(_ ordinal: Int) -> Bool {
        MonitorFeedEffectsWire.readsRec709Look(ordinal)
    }
    public static func packedFalseColorPaint(scaleOrdinal: Int, colorModeCode: Int, iso: Int,
        sourceProfile: MonitorColorSourceProfile = LunaMonitorColorProfile.value) -> [UInt8]? {
        packedFalseColorPaint(scaleOrdinal: scaleOrdinal,
            transfer: monitorTransfer(colorModeCode: colorModeCode), iso: iso, sourceProfile: sourceProfile)
    }
    public static func packedFalseColorPaint(scaleOrdinal: Int, transfer: MonitorTransfer, iso: Int,
        sourceProfile: MonitorColorSourceProfile = LunaMonitorColorProfile.value) -> [UInt8]? {
        MonitorFeedEffectsWire.packedFalseColorPaint(scaleOrdinal: scaleOrdinal,
            transfer: transfer, iso: iso, sourceProfile: sourceProfile)
    }
    public static func packedFalseColorWeight(scaleOrdinal: Int, colorModeCode: Int, iso: Int,
        sourceProfile: MonitorColorSourceProfile = LunaMonitorColorProfile.value) -> [UInt8]? {
        packedFalseColorWeight(scaleOrdinal: scaleOrdinal,
            transfer: monitorTransfer(colorModeCode: colorModeCode), iso: iso, sourceProfile: sourceProfile)
    }
    public static func packedFalseColorWeight(scaleOrdinal: Int, transfer: MonitorTransfer, iso: Int,
        sourceProfile: MonitorColorSourceProfile = LunaMonitorColorProfile.value) -> [UInt8]? {
        MonitorFeedEffectsWire.packedFalseColorWeight(scaleOrdinal: scaleOrdinal,
            transfer: transfer, iso: iso, sourceProfile: sourceProfile)
    }
    public static func assistScalars(colorModeCode: Int, iso: Int, highlightIRE: Double,
        midtoneIRE: Double, sourceProfile: MonitorColorSourceProfile = LunaMonitorColorProfile.value) -> [Float] {
        assistScalars(transfer: monitorTransfer(colorModeCode: colorModeCode), iso: iso,
            highlightIRE: highlightIRE, midtoneIRE: midtoneIRE, sourceProfile: sourceProfile)
    }
    public static func assistScalars(transfer: MonitorTransfer, iso: Int, highlightIRE: Double,
        midtoneIRE: Double, sourceProfile: MonitorColorSourceProfile = LunaMonitorColorProfile.value) -> [Float] {
        MonitorFeedEffectsWire.assistScalars(transfer: transfer, iso: iso,
            highlightIRE: highlightIRE, midtoneIRE: midtoneIRE, sourceProfile: sourceProfile)
    }
    public static func peakingGateScale(for transfer: MonitorTransfer) -> Double {
        MonitorFeedEffectsWire.peakingGateScale(for: transfer)
    }
}
