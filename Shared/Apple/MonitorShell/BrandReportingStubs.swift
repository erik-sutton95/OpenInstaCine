import Foundation
import OpenPocketViewCore
import SwiftUI

/// OpenInstaCine does not ship PocketCine's Sentry reliability pipeline.
/// These stand-ins keep the shared shell compiling without that SDK.
enum FeedIncidentJSON {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

enum ReliabilityReporting {
    static var isAvailable: Bool { false }
    static var isOptedIn: Bool { false }
    static func setConsent(_ enabled: Bool) {}
    static func setCameraSessionActive(_ active: Bool) {}
    static func install() {}
    static func setFinalizedSpoolLoader(_ loader: @escaping () -> [FeedIncidentBundle]) {}
    static func setSessionSummaryLoader(_ loader: @escaping () -> [FeedIncidentSessionSummary]) {}
    static func isFinalized(_ bundle: FeedIncidentBundle) -> Bool { true }
    static func enqueueFinalizedFromSpool() {}
    static func noteBreadcrumb(_ source: FeedIncidentBreadcrumb) {}
    static func noteRepair(_ repair: FeedRepairRecord) {}
    static func noteSessionSummary(_ summary: FeedIncidentSessionSummary) {}
}

enum ReliabilityReportingConsent {
    static var defaults = UserDefaults.standard
    static var hasDecision: Bool { true }
    static func setOptedIn(_ enabled: Bool) {}
}

struct ReliabilityConsentPrompt: View {
    var onChoice: (Bool) -> Void
    var body: some View { EmptyView().onAppear { onChoice(false) } }
}

@MainActor
final class ProblemReporting {
    static let shared = ProblemReporting()
    func tick() {}
}

struct ProblemReportView: View {
    var body: some View {
        NavigationStack {
            Text("Problem reports are not configured in this build.")
                .font(LiveType.ui(size: 15))
                .foregroundStyle(LiveDesign.muted)
                .padding()
                .navigationTitle("Report a problem")
        }
    }
}

enum ReliabilityReportingVerification {
    static var mode: String? { nil }
}

enum FeedIncidentOrigin {
    static func currentTestSource(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        injectionActivated: Bool = false
    ) -> FeedIncidentTestSource { .manual }
    static func currentBuildIdentity() -> String { "openinstacine" }
}

enum FeedStressAutomation {
    static var isEnabled: Bool { false }
    static var injectionDidActivate: Bool { false }
    static func installIfRequested() {}
    static func notePresent() {}
    static func noteDecodeSubmit() {}
    static func noteDecoded() {}
    static func shouldSilenceOutput() -> Bool { false }
    static func noteSourceObserved(videoPackets: Int, accessUnits: Int) {}
    static func noteSourceDelivered(videoPackets: Int, accessUnits: Int) {}
    static func shouldDropPacket(seq: UInt64) -> Bool { false }
}
