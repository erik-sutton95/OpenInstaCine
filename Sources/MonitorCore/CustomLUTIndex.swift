import Foundation

/// A `.cube` the operator imported into the on-device library.
///
/// OpenZCine `StoredLUT` for the Custom tab only — Pocket does not ship RED IPP2 download.
public struct StoredCustomLUT: Equatable, Sendable, Identifiable, Hashable {
    public let fileName: String

    public init(fileName: String) {
        self.fileName = fileName
    }

    public var id: String { fileName }

    /// File name without a trailing `.cube` (any case).
    public var displayName: String {
        CustomLUTIndex.displayName(fileName: fileName)
    }
}

/// Portable indexing for the custom LUT folder. File I/O stays in the iOS shell.
public enum CustomLUTIndex {
    /// Keeps only `.cube` entries and sorts them case-insensitively by file name.
    public static func stored(fromFileNames names: [String]) -> [StoredCustomLUT] {
        names
            .filter { $0.lowercased().hasSuffix(".cube") }
            .sorted { $0.lowercased() < $1.lowercased() }
            .map { StoredCustomLUT(fileName: $0) }
    }

    public static func displayName(fileName: String) -> String {
        fileName.lowercased().hasSuffix(".cube") ? String(fileName.dropLast(5)) : fileName
    }

    /// Rejects path components so a hostile name cannot escape the library directory.
    public static func isSafeFileName(_ name: String) -> Bool {
        !name.isEmpty
            && name == (name as NSString).lastPathComponent
            && !name.contains("/")
            && !name.contains("\\")
            && !name.contains(":")
    }
}
