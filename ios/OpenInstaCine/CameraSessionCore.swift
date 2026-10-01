import Foundation
import OpenCineCore
import OpenPocketViewCore

/// The app's camera-control state for the OpenCineCore session (CORE-02).
///
/// ISO, shutter, white balance and record reach the camera only as common `CameraCommand`s
/// submitted here, and their reported values come only from the session's snapshots. This file
/// uses no camera-protocol type.
///
/// Pending targets are presentation state: a drum shows the operator's target while its
/// operation is unfinished and falls back to the reported value when it ends. They are never
/// written into the session's snapshot. Record shows its pending state only as `controlBusy`.
struct CoreControl {
    var session: (any OpenCineCore.CameraSession)?
    var snapshot: CameraSnapshot?
    var feed: Task<Void, Never>?
    var pending: [SettingKey: (operation: OperationID, value: SettingValue)] = [:]
    var recordOperation: OperationID?
}

extension CameraSession {
    // MARK: - Session lifetime

    /// Makes `session` the target of the common controls and follows its snapshots.
    func attachCore(_ session: any OpenCineCore.CameraSession) {
        detachCore()
        core.session = session
        core.feed = Task { [weak self] in
            for await snapshot in await session.snapshots() {
                guard let self, !Task.isCancelled else { return }
                self.applyCoreSnapshot(snapshot)
            }
        }
    }

    /// Closes the session. Closing never sends a camera command (it never stops a recording).
    func detachCore() {
        core.feed?.cancel()
        if let session = core.session { Task { await session.close(.requested) } }
        if core.recordOperation != nil { controlBusy = false }
        core = CoreControl()
        reportedRecording = nil
    }

    func applyCoreSnapshot(_ snapshot: CameraSnapshot) {
        core.snapshot = snapshot
        let recording: Bool? =
            switch snapshot.recording.value {
            case .recording?: true
            case .idle?: false
            default: nil
            }
        if reportedRecording != recording { reportedRecording = recording }
        var next = status
        applyCorePresentation(to: &next)
        status = next
    }

    /// Reported ISO, shutter, WB and recording from the last snapshot, pending targets on top.
    func applyCorePresentation(to status: inout CameraStatus) {
        guard let snapshot = core.snapshot else { return }
        func shown(_ key: SettingKey) -> SettingValue? {
            core.pending[key]?.value ?? snapshot.value(of: key).value
        }
        var isoAuto: Bool?
        var shutterAuto: Bool?
        if case .iso(let iso)? = shown(.iso) {
            switch iso {
            case .manual(let value):
                status.isoIndex = IsoIndex.allCases.first { $0.isoValue == value }
                status.iso = value
                isoAuto = false
            case .auto, .autoLimited:
                status.isoIndex = .auto
                isoAuto = true
            }
        } else {
            status.isoIndex = nil
        }
        if case .shutter(let shutter)? = shown(.shutter) {
            if case .duration(let seconds) = shutter {
                // The live readout already shows a reported shutter; only a target replaces it.
                if core.pending[.shutter] != nil {
                    status.shutterDenom = Int((1 / seconds.doubleValue).rounded())
                }
                shutterAuto = false
            } else {
                shutterAuto = true
            }
        }
        if let isoAuto, let shutterAuto {
            status.expoMode = isoAuto && shutterAuto ? .auto : .manual
        }
        switch shown(.whiteBalance) {
        case .whiteBalance(.kelvin(let kelvin))?:
            status.whiteBalance = .custom(kelvin: kelvin, tint: 0)
            status.whiteBalanceKelvin = kelvin
            status.whiteBalanceTint = 0
        case .whiteBalance?:
            status.whiteBalance = .auto(tint: 0)
            status.whiteBalanceTint = 0
        default:
            status.whiteBalance = nil
        }
        status.isRecording = snapshot.recording.value == .recording
    }

    // MARK: - Settings

    func setISO(_ index: IsoIndex) {
        guard canSendControl else { return }
        let iso: ISOValue
        if index == .auto {
            iso = .auto
        } else if let value = index.isoValue {
            iso = .manual(value)
        } else {
            return
        }
        submitSetting(.iso(iso), "ISO \(index.label)")
    }

    func setShutterDenom(_ denom: Int) {
        guard canSendControl, denom > 0 else { return }
        submitSetting(.shutter(.duration(Rational(1, denom))), "1/\(denom)")
    }

    func setExpoMode(_ mode: ExpoMode) {
        guard canSendControl else { return }
        autoExposureLock = nil
        if mode == .auto {
            submitSetting(.iso(.auto), "Auto exposure")
            submitSetting(.shutter(.auto), "Auto exposure")
            return
        }
        // Manual needs a shutter: keep the current one, else the nearest offered 180 degrees.
        let fps = max(status.fps, 25)
        let wanted = status.shutterDenom > 0 ? status.shutterDenom : fps * 2
        let denom = status.availableShutterDenoms.min { abs($0 - wanted) < abs($1 - wanted) } ?? wanted
        submitSetting(.shutter(.duration(Rational(1, denom))), "Manual exposure")
    }

    func setWhiteBalanceAuto(tint: Int? = nil) {
        guard canSendControl else { return }
        autoWhiteBalanceLock = nil
        submitSetting(.whiteBalance(.auto), "WB Auto")
    }

    func setWhiteBalanceCustom(kelvin: Int, tint: Int) {
        guard canSendControl else { return }
        let kelvin = min(max(kelvin, 2_000), 10_000)
        // Custom from AWB Lock keeps the locked value; the camera is already there.
        if autoWhiteBalanceLock != nil, status.whiteBalance == .custom(kelvin: kelvin, tint: 0) {
            autoWhiteBalanceLock = nil
            return
        }
        autoWhiteBalanceLock = nil
        submitSetting(.whiteBalance(.kelvin(kelvin)), "WB \(kelvin)K")
    }

    /// Shows `value` at once; submits it after the coalescing window (latest per setting wins).
    private func submitSetting(_ value: SettingValue, _ label: String) {
        core.pending[value.key] = (OperationID(), value)
        var next = status
        applyCorePresentation(to: &next)
        status = next
        exposureCoalescer.submit(key: value.key.rawValue) { [weak self] in
            self?.submitPending(value.key, label)
        }
    }

    private func submitPending(_ key: SettingKey, _ label: String) {
        guard let pending = core.pending[key] else { return }
        let operation = pending.operation
        guard let session = core.session, let snapshot = core.snapshot else {
            finishSetting(key, operation, note: "Connect the camera to use its controls.")
            return
        }
        let command = CameraCommand(
            .set(pending.value), preconditions: CommandPreconditions(snapshot), operation: operation)
        Task { [weak self] in
            let receipt = await Self.finished(command, on: session)
            self?.finishSetting(key, operation, note: Self.note(for: receipt.stage, label))
        }
    }

    private func finishSetting(_ key: SettingKey, _ operation: OperationID, note: String?) {
        // A newer edit of the same setting owns the drum now.
        guard core.pending[key]?.operation == operation else { return }
        core.pending[key] = nil
        if let note {
            controlNote = note
            noteCommandFailure()
        }
        refreshShownSettings()
    }

    // MARK: - Record

    /// The record lamp without a confirmation: start or stop as a fresh camera report says.
    /// Unknown recording sends nothing; there is no blind toggle.
    func toggleRecording() {
        record(start: nil)
    }

    /// A confirmed start or stop (the dialog already checked lock and link). If the camera
    /// already reports it, nothing is sent.
    func setRecording(start: Bool) {
        record(start: start)
    }

    private func record(start: Bool?) {
        guard core.recordOperation == nil else { return }
        guard let session = core.session else {
            controlNote = "Connect the camera to use its controls."
            return
        }
        let operation = OperationID()
        core.recordOperation = operation
        controlBusy = true
        Task { [weak self] in
            let snapshot = await session.currentSnapshot()
            let intent: CameraCommandIntent?
            switch (start, snapshot?.recording.value) {
            case (true?, _): intent = .startRecording
            case (false?, _): intent = .stopRecording
            case (nil, .recording?): intent = .stopRecording
            case (nil, .idle?): intent = .startRecording
            default: intent = nil
            }
            guard let intent, let snapshot else {
                self?.finishRecord(operation, note: "Recording state is not known yet. Try again in a moment.", stopped: false)
                return
            }
            let command = CameraCommand(
                intent, preconditions: CommandPreconditions(snapshot), operation: operation)
            let receipt = await Self.finished(command, on: session)
            self?.finishRecord(
                operation, note: Self.note(for: receipt.stage, intent == .startRecording ? "Record" : "Stop"),
                stopped: intent == .stopRecording && receipt.stage == .confirmed)
        }
    }

    private func finishRecord(_ operation: OperationID, note: String?, stopped: Bool) {
        guard core.recordOperation == operation else { return }
        core.recordOperation = nil
        controlBusy = false
        if let note {
            controlNote = note
            noteCommandFailure()
        }
        if stopped { Task { await refreshMediaAfterCapture() } }
    }

    // MARK: - Outcomes

    private static func finished(
        _ command: CameraCommand, on session: any OpenCineCore.CameraSession
    ) async -> CommandReceipt {
        let receipt = await session.submit(command)
        if receipt.isFinished { return receipt }
        return await session.outcome(of: command.operation) ?? receipt
    }

    /// Operator copy for an outcome that is not a confirmation.
    static func note(for stage: CommandStage, _ label: String) -> String? {
        switch stage {
        case .confirmed:
            return nil
        case .rejected(.cameraRefused):
            return "\(label): the camera refused it."
        case .rejected(.outOfDomain), .rejected(.unsupported), .rejected(.supportUnknown):
            return "\(label) is not offered by this camera."
        case .rejected(.staleCapabilities), .rejected(.staleEpoch):
            return "\(label) was not sent: the camera state changed. Try again."
        case .rejected(.unavailable(let reason)):
            return reason == .mode
                ? "\(label) is not available in this mode."
                : "\(label) is not available right now."
        case .rejected:
            return "Connect the camera to use its controls."
        case .failed(.notApplied):
            return "\(label) was not applied by the camera."
        case .failed(.notSent):
            return "\(label) was not sent."
        case .failed(.superseded):
            // A newer write to the same setting replaced it; that receipt carries the outcome.
            return nil
        case .timedOut:
            return "The camera did not confirm \(label)."
        case .outcomeUnknown:
            return "\(label): the camera link dropped before it confirmed."
        case .created, .admitted, .sent, .accepted, .awaitingObservation:
            return "The camera did not confirm \(label)."
        }
    }
}
