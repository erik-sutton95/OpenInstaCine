import Foundation
import OpenCineAppKit
import OpenInstaViewCore

/// Structured expo lines for the agent loop: os.Logger + a capped Documents journal
/// (OpenCine's `DiagnosticJournal`). Pull `Documents/control-live.log` from the
/// `com.opencapture.openinstacine` app container with `xcrun devicectl device copy from`.
let ControlLiveLog = DiagnosticJournal(
    subsystem: "com.opencapture.openinstacine", category: "session",
    file: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
        .appendingPathComponent("control-live.log"),
    redact: { PrivacyRedactor.redact($0) })
