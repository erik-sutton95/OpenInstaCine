import Foundation
import OpenPocketViewCore
import SwiftUI

/// LUT long-press body: Insta360 / Creative / Custom, then exposure and 50/50.
///
/// Auto follows color with the official Insta360 I-Log to Rec.709 cube. Creative is Mono /
/// Contrast / Warm / Cool. Custom is imported `.cube` files. The assist-bar
/// chip is off. Exposure is input-referred stops before the cube (ETTR pull).
enum LUTAssist {
    static let exposureTitle = "Exposure"
    static let exposureHelp = "Input stops before the cube. Pull 1–2 after ETTR."
    /// Live Photo / Photo is Rec.709; do not label a stale D-Log conversion.
    static let photoRec709Caption = "Photo live view is Rec.709 — log conversions are off"

    @ViewBuilder
    static func longPressMenu(assist: LiveAssistState) -> some View {
        LUTPicker(assist: assist, embedded: true)
    }

    @ViewBuilder
    static func longPressMenu(_ assist: LiveAssistState) -> some View {
        LUTPicker(assist: assist, embedded: true)
    }

    /// Pinned under the catalog so landscape never scrolls exposure / 50/50 off-screen.
    @ViewBuilder
    static func longPressFooter(assist: LiveAssistState) -> some View {
        LUTSplitComparisonBar(assist: assist)
    }
}

/// Official Insta360 Luna I-Log to Rec.709 cube from the app bundle. Parsed once.
enum BundledLunaLUT {
    static let resourceName = "Luna_I-Log_to_Rec709_BT1886_s33_v2"
    private static let lock = NSLock()
    private static var cache: CubeLUT?

    static var iLogToRec709: CubeLUT? {
        lock.lock()
        defer { lock.unlock() }
        if let cache { return cache }
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "cube"),
            let text = try? String(contentsOf: url, encoding: .utf8),
            let parsed = try? CubeLUT.parse(text)
        else { return nil }
        cache = parsed
        return parsed
    }
}

/// On-disk custom slots — one `.cube` for Rec.709/HLG, D-Log, and D-Log2.
enum CustomLUTStore {
    private static var cubeCache: [String: CubeLUT] = [:]

    static var root: URL {
        let documents =
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return documents.appendingPathComponent("luts/custom", isDirectory: true)
    }

    static func list() -> [StoredCustomLUT] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return CustomLUTIndex.stored(fromFileNames: names)
    }

    static func fileName(for slot: CustomLUTSlot) -> String? {
        OperatorPrefs.customFileName(for: slot)
    }

    static func hasCube(_ slot: CustomLUTSlot) -> Bool {
        guard let name = fileName(for: slot), CustomLUTIndex.isSafeFileName(name) else {
            return false
        }
        return FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path)
    }

    static func displayName(for slot: CustomLUTSlot) -> String? {
        guard let name = fileName(for: slot), hasCube(slot) else { return nil }
        return CustomLUTIndex.displayName(fileName: name)
    }

    static func cube(_ slot: CustomLUTSlot) -> CubeLUT? {
        guard let name = fileName(for: slot) else { return nil }
        return cube(fileName: name)
    }

    @discardableResult
    static func importFile(from source: URL) throws -> StoredCustomLUT {
        let fileName = source.lastPathComponent
        guard CustomLUTIndex.isSafeFileName(fileName) else {
            throw CustomLUTStoreError.invalidFileName
        }
        let text: String
        do {
            text = try String(contentsOf: source, encoding: .utf8)
        } catch {
            throw CustomLUTStoreError.unreadable
        }
        let parsed = try CubeLUT.parse(text)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: source, to: destination)
        cubeCache[fileName] = parsed
        return StoredCustomLUT(fileName: fileName)
    }

    @discardableResult
    static func importFile(from source: URL, into slot: CustomLUTSlot) throws -> StoredCustomLUT {
        let previous = fileName(for: slot)
        let stored = try importFile(from: source)
        OperatorPrefs.setCustomFileName(stored.fileName, for: slot)
        if let previous, previous != stored.fileName, !isShared(previous, excluding: slot) {
            try? remove(StoredCustomLUT(fileName: previous))
        }
        return stored
    }

    static func cube(_ lut: StoredCustomLUT) -> CubeLUT? {
        cube(fileName: lut.fileName)
    }

    static func cube(fileName: String) -> CubeLUT? {
        guard CustomLUTIndex.isSafeFileName(fileName) else { return nil }
        if let cached = cubeCache[fileName] { return cached }
        let url = root.appendingPathComponent(fileName)
        guard let text = try? String(contentsOf: url, encoding: .utf8),
            let parsed = try? CubeLUT.parse(text)
        else { return nil }
        cubeCache[fileName] = parsed
        return parsed
    }

    static func remove(_ lut: StoredCustomLUT) throws {
        guard CustomLUTIndex.isSafeFileName(lut.fileName) else {
            throw CustomLUTStoreError.invalidFileName
        }
        do {
            try FileManager.default.removeItem(at: root.appendingPathComponent(lut.fileName))
            cubeCache[lut.fileName] = nil
        } catch {
            throw CustomLUTStoreError.deletionFailed(lut.displayName)
        }
    }

    static func clear(_ slot: CustomLUTSlot) throws {
        let name = fileName(for: slot)
        OperatorPrefs.setCustomFileName(nil, for: slot)
        if let name, !isShared(name, excluding: slot) {
            try remove(StoredCustomLUT(fileName: name))
        }
    }

    private static func isShared(_ fileName: String, excluding slot: CustomLUTSlot) -> Bool {
        slot.others.contains { OperatorPrefs.customFileName(for: $0) == fileName }
    }
}

enum CustomLUTStoreError: LocalizedError {
    case invalidFileName
    case unreadable
    case deletionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidFileName:
            return "The LUT file name is not valid."
        case .unreadable:
            return "The .cube file could not be read."
        case .deletionFailed(let name):
            return "The LUT “\(name)” could not be deleted."
        }
    }
}
