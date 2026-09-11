import Foundation

public enum MediaKind: String, Sendable, Codable {
    case video
    case photo

    public static func from(extension ext: String) -> MediaKind {
        switch ext.uppercased() {
        case "JPG", "JPEG", "DNG", "HEIC", "TIF", "TIFF", "PANO":
            return .photo
        default:
            return .video
        }
    }
}

/// What the phone has for a clip. Playback grades the proxy; Share needs the original.
public enum MediaCacheGrade: String, Sendable, Equatable {
    case none
    case proxy
    case original

    public var isPlayableOffline: Bool { self != .none }
    public var isProxyOnly: Bool { self == .proxy }

    public static func resolve(hasOriginal: Bool, hasProxy: Bool) -> MediaCacheGrade {
        if hasOriginal { return .original }
        if hasProxy { return .proxy }
        return .none
    }
}

public enum MediaLibraryTab: String, Sendable, CaseIterable {
    case all, videos, photos, favorites
}

public enum MediaLibrarySort: String, Sendable, CaseIterable {
    case newest, oldest, name, rating
}

public enum MediaClipFormatting {
    public static func durationLabel(seconds: Int) -> String {
        guard seconds > 0 else { return "0:00" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    public static func byteLabel(_ bytes: UInt64) -> String {
        guard bytes > 0 else { return "" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        let mb = kb / 1024
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        return String(format: "%.2f GB", mb / 1024)
    }
}
