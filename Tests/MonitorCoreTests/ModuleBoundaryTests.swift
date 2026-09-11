import Foundation
import Testing
import MonitorCore

@Suite struct ModuleBoundaryTests {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    /// These sources must compile with Foundation alone. Check imports as well
    /// as direct wire symbols so a future transport shortcut cannot silently
    /// couple the shared monitor to one camera or one platform.
    @Test func portableMonitorDoesNotImportPlatformOrCameraModules() throws {
        let directory = root.appendingPathComponent("Sources/MonitorCore")
        let files = try swiftFiles(in: directory)
        #expect(files.count >= 20)
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let imports = source.split(separator: "\n").filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("import ") }
            #expect(imports.allSatisfy { $0.trimmingCharacters(in: .whitespaces) == "import Foundation" },
                    "Platform or adapter import in \(file.lastPathComponent)")
        }
    }

    @Test func sharedCoreContractsAndAppleScreensDoNotOwnWireCodecs() throws {
        let forbidden = try NSRegularExpression(pattern:
            #"\b(?:Duml|DumlTransport|HevcDepacketizer|BleAdvert|Commands|UCD2Frame|UCD2Reassembler|UCD2Message|LunaProtocol)\b"#)
        for relative in ["Sources/MonitorCore", "Sources/MonitorContracts", "Shared/Apple"] {
            let directory = root.appendingPathComponent(relative)
            #expect(FileManager.default.fileExists(atPath: directory.path), "Missing boundary: \(relative)")
            for file in try swiftFiles(in: directory) {
                let source = try String(contentsOf: file, encoding: .utf8)
                // Comments preserve extraction provenance; executable references
                // and protocol names in string payloads still fail the boundary.
                let code = source.split(separator: "\n").filter {
                    !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//")
                }.joined(separator: "\n")
                let range = NSRange(code.startIndex..., in: code)
                #expect(forbidden.firstMatch(in: code, range: range) == nil,
                        "Camera wire ownership leaked into \(file.path.replacingOccurrences(of: root.path + "/", with: ""))")
            }
        }
    }

    @Test func neutralImportProvidesMonitorMathAndMediaPolicy() {
        // This target depends only on MonitorCore. These checks also prove the
        // public types need no compatibility import to serve another brand.
        let cube = BuiltInLook.mono.cube(size: 2)
        let mapped = cube.map(red: 0.4, green: 0.3, blue: 0.2)
        #expect(mapped.red == mapped.green && mapped.green == mapped.blue)
        #expect(MonitorTransfer.rec709.label == "Rec.709")
        #expect(MediaCacheGrade.resolve(hasOriginal: false, hasProxy: true).isPlayableOffline)
        #expect(!MediaCacheGrade.none.isPlayableOffline)
        #expect(MediaClipFormatting.durationLabel(seconds: 65) == "1:05")
        #expect(!FeedPresentPolicy.shouldFlushDisplayedImage(disconnecting: false, layerFailed: false, nextFrameReady: false))
        #expect(Hevc.nalType(0x42) == Hevc.sps)
        #expect(TrackingBox(x: 0, y: 0, width: 1, height: 1).contains(x: 0.5, y: 0.5))
    }

    private func swiftFiles(in directory: URL) throws -> [URL] {
        guard let iterator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return iterator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
}
