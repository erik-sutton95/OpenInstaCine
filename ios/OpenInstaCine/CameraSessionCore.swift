import Foundation
import Insta360Apple
import OpenCineAppKit
import OpenCineCore
import OpenInstaViewCore

/// The app's typed adapters onto the shared monitor controls (`MonitorControlModel`, SHELL-03).
///
/// The shell binds the connected camera's common session to `control` (its one snapshot
/// subscription); ISO, shutter, white balance and record reach the camera only as the shared
/// model's commands. What stays here is temporary (I-2 moves capture onto descriptors): the
/// mapping from this app's drum values (`IsoIndex`, shutter denominators, Kelvin) and the
/// projection of the shared readouts into `CameraStatus` for the views that still read it.
extension CameraSession {
    /// The common session of the camera on the monitor, if any.
    var coreSession: (any OpenCineCore.CameraSession)? { control.session }

    /// One operation's concrete integration port, retained by the shared control queue.
    func commandDispatchAdmission(_ admission: LunaCommandAdmission) -> CommandDispatchAdmission? {
        guard let target = lunaSession, admission.admits(target.commandOwner),
            coreSession?.id == target.id
        else { return nil }
        let snapshot = target.current
        return CommandDispatchAdmission(
            session: snapshot.session, epoch: snapshot.epoch,
            isCurrent: { admission.admits(target.commandOwner) },
            submit: { command in await target.submit(command, admission: admission) })
    }

    private func writeSetting(
        _ value: SettingValue, label: String, admission: CommandDispatchAdmission?
    ) {
        if let admission { control.set(value, label: label, admission: admission) }
        else { control.set(value, label: label) }
    }

    static let notApplied = " was not applied by the camera."

    /// Main's control copy (`sendControl`): a request that failed said "X was not applied by the
    /// camera."; a write the camera took but did not show reverted silently. A stale camera state
    /// (a kept wrong-camera guard) and not being connected keep the shared copy.
    static func controlNote(for stage: CommandStage, _ label: String) -> String? {
        guard let shared = MonitorControlModel.note(for: stage, label) else { return nil }
        switch stage {
        case .timedOut, .failed(.notApplied): return nil
        case .rejected(.staleEpoch), .rejected(.staleCapabilities): return shared
        default: return shared == MonitorControlModel.connectFirst ? shared : label + notApplied
        }
    }

    /// Notes, the media refresh after a confirmed stop, and the status projection.
    func adoptControl() {
        control.noteFor = CameraSession.controlNote(for:_:)
        control.onNote = { [weak self] note in
            self?.controlNote = note
            // Link Health counted a request the camera did not take, as main did; never "connect
            // first" or a stale camera state.
            if note.hasSuffix(CameraSession.notApplied) { self?.noteCommandFailure() }
        }
        control.onRecordFinished = { [weak self] receipt in
            guard receipt.intent == .stopRecording, receipt.stage == .confirmed else { return }
            Task { await self?.refreshMediaAfterCapture() }
        }
        control.onChange = { [weak self] in
            guard let self else { return }
            var next = self.status
            self.applyCorePresentation(to: &next)
            self.status = next
        }
    }

    /// Temporary projection: reported ISO, shutter, WB and recording with pending targets on top.
    func applyCorePresentation(to status: inout CameraStatus) {
        guard control.snapshot != nil else { return }
        var isoAuto: Bool?
        var shutterAuto: Bool?
        if case .iso(let iso)? = control.shown(.iso) {
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
        if case .shutter(let shutter)? = control.shown(.shutter) {
            if case .duration(let seconds) = shutter {
                // The live readout already shows a reported shutter; only a target replaces it.
                if control.pending[.shutter] != nil {
                    status.shutterDenom = Int((1 / seconds.doubleValue).rounded())
                }
                shutterAuto = false
            } else if case .angle = shutter {
                // The emulated angle is a fixed shutter (Angle preference); only Auto is automatic.
                shutterAuto = false
            } else {
                shutterAuto = true
            }
        }
        if let isoAuto, let shutterAuto {
            status.expoMode = isoAuto && shutterAuto ? .auto : .manual
        }
        switch control.shown(.whiteBalance) {
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
        status.isRecording = control.recording == .recording
    }

    // MARK: - Settings

    func setISO(_ index: IsoIndex) {
        setISO(index, suppliedAdmission: nil)
    }

    func setISO(_ index: IsoIndex, admission: LunaCommandAdmission) {
        guard let dispatch = commandDispatchAdmission(admission) else { return }
        setISO(index, suppliedAdmission: dispatch)
    }

    private func setISO(_ index: IsoIndex, suppliedAdmission admission: CommandDispatchAdmission?) {
        guard canSendControl else { return }
        if index == .auto {
            writeSetting(.iso(.auto), label: "ISO \(index.label)", admission: admission)
        } else if let value = index.isoValue {
            writeSetting(.iso(.manual(value)), label: "ISO \(index.label)", admission: admission)
        }
    }

    func setShutterDenom(_ denom: Int) {
        setShutterDenom(denom, suppliedAdmission: nil)
    }

    func setShutterDenom(_ denom: Int, admission: LunaCommandAdmission) {
        guard let dispatch = commandDispatchAdmission(admission) else { return }
        setShutterDenom(denom, suppliedAdmission: dispatch)
    }

    private func setShutterDenom(_ denom: Int, suppliedAdmission admission: CommandDispatchAdmission?) {
        guard canSendControl, denom > 0 else { return }
        writeSetting(.shutter(.duration(Rational(1, denom))), label: "1/\(denom)", admission: admission)
    }

    func setExpoMode(_ mode: ExpoMode) {
        guard canSendControl else { return }
        autoExposureLock = nil
        if mode == .auto {
            control.set(.iso(.auto), label: "Auto exposure")
            control.set(.shutter(.auto), label: "Auto exposure")
            return
        }
        // Manual needs a shutter: keep the current one, else the nearest offered 180 degrees.
        let fps = max(status.fps, 25)
        let wanted = status.shutterDenom > 0 ? status.shutterDenom : fps * 2
        let denom = status.availableShutterDenoms.min { abs($0 - wanted) < abs($1 - wanted) } ?? wanted
        control.set(.shutter(.duration(Rational(1, denom))), label: "Manual exposure")
    }

    func setWhiteBalanceAuto(tint: Int? = nil) {
        setWhiteBalanceAuto(tint: tint, suppliedAdmission: nil)
    }

    func setWhiteBalanceAuto(tint: Int? = nil, admission: LunaCommandAdmission) {
        guard let dispatch = commandDispatchAdmission(admission) else { return }
        setWhiteBalanceAuto(tint: tint, suppliedAdmission: dispatch)
    }

    private func setWhiteBalanceAuto(tint: Int?, suppliedAdmission admission: CommandDispatchAdmission?) {
        guard canSendControl else { return }
        autoWhiteBalanceLock = nil
        writeSetting(.whiteBalance(.auto), label: "WB Auto", admission: admission)
    }

    func setWhiteBalanceCustom(kelvin: Int, tint: Int) {
        setWhiteBalanceCustom(kelvin: kelvin, tint: tint, suppliedAdmission: nil)
    }

    func setWhiteBalanceCustom(kelvin: Int, tint: Int, admission: LunaCommandAdmission) {
        guard let dispatch = commandDispatchAdmission(admission) else { return }
        setWhiteBalanceCustom(kelvin: kelvin, tint: tint, suppliedAdmission: dispatch)
    }

    private func setWhiteBalanceCustom(kelvin: Int, tint: Int, suppliedAdmission admission: CommandDispatchAdmission?) {
        guard canSendControl else { return }
        let kelvin = min(max(kelvin, 2_000), 10_000)
        // Custom from AWB Lock keeps the locked value; the camera is already there.
        if autoWhiteBalanceLock != nil, status.whiteBalance == .custom(kelvin: kelvin, tint: 0) {
            autoWhiteBalanceLock = nil
            return
        }
        autoWhiteBalanceLock = nil
        writeSetting(.whiteBalance(.kelvin(kelvin)), label: "WB \(kelvin)K", admission: admission)
    }

    // MARK: - Record

    /// The record lamp without a confirmation: start or stop as a fresh camera report says.
    func toggleRecording() { control.record(start: nil) }

    func toggleRecording(admission: LunaCommandAdmission) {
        guard let dispatch = commandDispatchAdmission(admission) else { return }
        control.record(start: nil, admission: dispatch)
    }

    /// The Watch needs to know whether the existing common control has an actual record command.
    /// Keep the original Void entry points for local callers and stored function references.
    func dispatchWatchRecording(admission: LunaCommandAdmission?) -> Bool {
        guard let editor = control.recordEditor() else { return false }
        if let admission {
            return commitRecording(from: editor, admission: admission)
        }
        return control.commitRecord(from: editor)
    }

    /// A confirmed start or stop (the dialog already checked lock and link).
    func setRecording(start: Bool) { control.record(start: start) }

    func setRecording(start: Bool, admission: LunaCommandAdmission) {
        guard let dispatch = commandDispatchAdmission(admission) else { return }
        control.record(start: start, admission: dispatch)
    }

    @discardableResult
    func commitRecording(
        from editor: MonitorControlModel.RecordEditor, admission: LunaCommandAdmission
    ) -> Bool {
        guard let dispatch = commandDispatchAdmission(admission) else { return false }
        return control.commitRecord(from: editor, admission: dispatch)
    }
}
