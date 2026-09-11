import Foundation

/// A brand-supplied display conversion. The shell loads the named cube through
/// its platform asset loader; the shared engine owns sampling and exposure math.
/// Input transfer describes the LUT's domain, never the connected camera's SET
/// or the actual preview encoding. Selecting a look does not change source metadata.
public struct CameraLUT: Equatable, Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let fileName: String
    public let inputTransfer: MonitorTransfer

    public init(id: String, title: String, fileName: String, inputTransfer: MonitorTransfer) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.inputTransfer = inputTransfer
    }
}
