import Foundation
import Testing

/// Owner style rule (hardware pass 2026-10-24): operator notes never use the em dash.
@Suite struct OperatorNoteCopyStyleTests {
    @Test func controlNotesNeverUseTheEmDash() throws {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("ios/OpenInstaCine")
        let files = try FileManager.default.contentsOfDirectory(at: app, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty)
        let note = try Regex(#"controlNote\s*=\s*"((?:[^"\\]|\\.)*)""#)
        var offenders: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in text.matches(of: note) {
                let literal = String(text[match.range])
                if literal.contains("\u{2014}") || literal.contains("\\u{2014}") { offenders.append(file.lastPathComponent + ": " + literal) }
            }
        }
        #expect(offenders.isEmpty, "\(offenders)")
    }
}
