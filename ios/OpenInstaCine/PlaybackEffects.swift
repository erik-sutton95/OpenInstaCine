import CoreImage
import Foundation
import OpenCineApple
import OpenPocketViewCore

/// App-owned output location and source curve adapter for the shared native exporter.
enum MediaLUT {
    typealias ExportResult = MonitorMediaExporter.ExportResult

    enum ExportError: LocalizedError {
        case invalidFilename
        var errorDescription: String? { "Enter a valid filename." }
    }

    static func colorContext(preservingEncodedValues: Bool) -> CIContext {
        MonitorMediaExporter.colorContext(preservingEncodedValues: preservingEncodedValues)
    }

    static func transformFitting(_ source: CGRect, to target: CGRect) -> CGAffineTransform {
        MonitorMediaExporter.transformFitting(source, to: target)
    }

    static func mappedExportProgress(_ sessionProgress: Float) -> Double {
        MonitorMediaExporter.mappedExportProgress(sessionProgress)
    }

    static func exportPreset(bakingLUT: Bool, compatible: [String]) -> String {
        MonitorMediaExporter.exportPreset(bakingLUT: bakingLUT, compatible: compatible)
    }

    static func export(
        sourceURL: URL, outputFilename: String, format: MediaExportFormat, cube: CubeLUT?,
        logTransform: LogColorTransform? = nil, metadata: MediaClipDeliveryMetadata?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> ExportResult {
        let outputURL = try makeExportURL(filename: outputFilename, format: format)
        progress(0.02)
        let look: MonitorMediaExporter.Look?
        if let logTransform {
            look = .init(
                cube: logTransform.cube(), preservingEncodedValues: true,
                metadataReplacement: .init(
                    key: ClipColorProfile.gammaKey, value: logTransform.destination.label))
        } else if let cube {
            look = .init(cube: cube)
        } else {
            look = nil
        }
        return try await MonitorMediaExporter.export(
            sourceURL: sourceURL, outputURL: outputURL, format: format, look: look,
            metadata: metadata, progress: progress)
    }

    private static func makeExportURL(filename: String, format: MediaExportFormat) throws -> URL {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ExportError.invalidFilename }
        let exports = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
        var name = trimmed
        if (name as NSString).pathExtension.isEmpty {
            name = "\(name).\(format.rawValue)"
        }
        let url = exports.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        return url
    }

}
