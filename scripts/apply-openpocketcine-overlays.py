#!/usr/bin/env python3
"""Brand hunks applied after every OpenPocketCine sync (see sync-openpocketcine.sh).

Keep these patches tiny and exact. Camera protocol lives in the sibling OpenCine
package (Insta360 products) and in the
Luna-owned shell files listed in sync-openpocketcine.sh. If a hunk stops matching,
the sync fails instead of silently shipping a blue OpenPocketCine clone.
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "ios/OpenInstaCine"


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if new in text:
        return  # already applied
    count = text.count(old)
    if count != 1:
        sys.exit(f"{path.relative_to(ROOT)}: overlay hunk matched {count} times:\n{old[:160]}")
    path.write_text(text.replace(old, new, 1))


def replace_phrase(path: Path, old: str, new: str) -> None:
    """Every occurrence of a copy phrase. Fails if the phrase and its brand version are both gone."""
    text = path.read_text()
    if old not in text:
        if new not in text:
            sys.exit(f"{path.relative_to(ROOT)}: overlay phrase missing:\n{old[:160]}")
        return  # already applied
    path.write_text(text.replace(old, new))


def main() -> None:
    # --- Brand accent: OpenCineUI's settable MonitorTheme.accentRGB, assigned once at launch
    # (OpenInstaCineBrand.apply). The theme itself is no longer synced. ---
    branding = APP / "Branding.swift"
    replace_once(
        branding,
        "/// OpenInstaCine brand palette — DJI Sky Blue on Black.\n",
        "/// OpenInstaCine brand palette: Luna yellow on black.\n",
    )
    replace_once(
        branding,
        "    static let accent = Color(red: 0, green: 163 / 255, blue: 230 / 255)\n"
        "    static let accentSoft = Color(red: 0, green: 163 / 255, blue: 230 / 255).opacity(0.18)\n",
        "    static var accent: Color { MonitorTheme.accent }\n"
        "    static var accentSoft: Color { MonitorTheme.accent.opacity(0.18) }\n",
    )
    text = branding.read_text()
    if "import MonitorUI" not in text:
        branding.write_text(text.replace("import SwiftUI\n", "import MonitorUI\nimport SwiftUI\n", 1))

    startup = APP / "StartupChrome.swift"
    replace_once(
        startup,
        "    static var accent: Color { LiveHDRDisplay.chromeColor(hex: 0x00A3E0) }\n",
        "    static var accent: Color { LiveHDRDisplay.chromeColor(hex: MonitorTheme.accentRGB) }\n",
    )

    # --- Pairing and connection copy: the Insta360 app, not DJI Mimo / Frame Tap, holds a Luna. ---
    for old_phrase, new_phrase in (
        ("DJI Frame Tap or a running DJI Mimo holds", "A running Insta360 app holds"),
        ("turn off DJI Frame Tap and force quit DJI Mimo", "force quit the Insta360 app"),
        ("Turn off DJI Frame Tap and force quit DJI Mimo", "Force quit the Insta360 app"),
        ("Force quit DJI Mimo", "Force quit the Insta360 app"),
    ):
        replace_phrase(startup, old_phrase, new_phrase)
    pairing_tests = ROOT / "ios/OpenInstaCineTests/CameraPagePresentationTests.swift"
    for old_phrase, new_phrase in (
        ("turn off DJI Frame Tap and force quit DJI Mimo", "force quit the Insta360 app"),
        ("Turn off DJI Frame Tap and force quit DJI Mimo", "Force quit the Insta360 app"),
        ('.contains("DJI Frame Tap")', '.contains("Insta360 app")'),
    ):
        replace_phrase(pairing_tests, old_phrase, new_phrase)

    # --- Insta360 calls Normal "Standard" (ColorMode.labelOverrides, set at launch). ---
    snapshot_tests = ROOT / "ios/OpenInstaCineTests/CaptureQuickSnapshotTests.swift"
    replace_phrase(
        snapshot_tests,
        'XCTAssertEqual(color.options, ["Normal", "HDR", "D-Log"])',
        'XCTAssertEqual(color.options, ["Standard", "HDR", "D-Log"])',
    )
    replace_phrase(
        snapshot_tests,
        'XCTAssertEqual(color.selection, "Normal")',
        'XCTAssertEqual(color.selection, "Standard")',
    )

    # --- Luna AF modes (focus drum lists only what the camera offers) and metering row. ---
    for name in ("CaptureControlSheets.swift", "CaptureQuickControl.swift"):
        replace_phrase(APP / name, "FocusOption.allCases", "CaptureLists.focusOptions")
    replace_phrase(
        snapshot_tests,
        'XCTAssertEqual(snapshot.options, ["AF-S", "AF-C", "Showcase", "Lock", "Priority"])',
        'XCTAssertEqual(snapshot.options, ["AF-S", "AF-C", "Showcase"])',
    )
    replace_phrase(snapshot_tests, "for option in FocusOption.allCases {", "for option in CaptureLists.focusOptions {")

    # --- ISO sheet: the DJI native-ISO hop toggle only for cameras that hop (not Luna). ---
    replace_once(
        APP / "CaptureControlSheets.swift",
        "if sheet == .iso { nativeIsoHopToggle }",
        "if sheet == .iso, model.session.supportsNativeIsoHop { nativeIsoHopToggle }",
    )

    # --- EV meter: a camera without metered EV (Luna) meters the picture instead. ---
    fx = APP / "LiveMonitorFx.swift"
    replace_once(fx, "    var ndMeter = false\n    var lutDimension = 0\n",
                 "    var ndMeter = false\n    /// EV meter reading the picture: the scope tap must run.\n    var evMeter = false\n    var lutDimension = 0\n")
    replace_once(fx, "        histogram || waveform || parade || vectorscope || trafficLights || ndMeter\n    }",
                 "        histogram || waveform || parade || vectorscope || trafficLights || ndMeter || evMeter\n    }")
    replace_once(fx, "    func withFaceAF(_ on: Bool) -> LiveImageEffects {",
                 "    func withEVMeter(_ on: Bool) -> LiveImageEffects {\n        var fx = self\n        fx.evMeter = on\n        return fx\n    }\n\n    func withFaceAF(_ on: Bool) -> LiveImageEffects {")
    assists = APP / "LiveAssists.swift"
    replace_once(assists, "    var monitorFamily: CameraBodyFamily = .pocket\n",
                 "    var monitorFamily: CameraBodyFamily = .pocket\n    /// The camera reports no metered EV, so the EV meter reads the picture.\n    var evMeterFromPicture = false\n")
    replace_once(assists, "        .withInspectorDemand(inspectorSceneActive && !gradesClip ? configureTool : nil)\n",
                 "        .withEVMeter(evMeterFromPicture && isVisible(.evMeter))\n        .withInspectorDemand(inspectorSceneActive && !gradesClip ? configureTool : nil)\n")
    replace_once(assists, "        fx.ndMeter = isPlaybackVisible(.ndMeter)\n",
                 "        fx.ndMeter = isPlaybackVisible(.ndMeter)\n        fx.evMeter = false\n")
    replace_once(APP / "AppRoot.swift", "        let photo = session.status.isPhoto\n        assist.syncLUT(\n",
                 "        let photo = session.status.isPhoto\n        assist.evMeterFromPicture = !session.reportsMeteredEV\n        assist.cameraHasAudio = session.supportsAudio\n        assist.syncLUT(\n")
    ev = APP / "CameraEVMeter.swift"
    replace_once(ev, """        let reading = ExposureMeterReading(
            cameraValue: model.session.sessionRecovery.isRecovering || model.session.feedRecovering
                ? nil : model.session.status.meteredEv)
""", """        let recovering = model.session.sessionRecovery.isRecovering || model.session.feedRecovering
        let reading = ExposureMeterReading(
            cameraValue: recovering ? nil : model.session.status.meteredEv ?? pictureEV)
""")
    replace_once(ev, "    var avoiding: CGRect?\n\n    var body: some View {\n        let frame = CameraEVMeter.frame(in: feed, avoiding: avoiding)\n",
                 "    var avoiding: CGRect?\n\n    /// Metered EV from the live picture, for cameras that report none.\n    private var pictureEV: EvComp? {\n        guard model.assist.evMeterFromPicture else { return nil }\n        let bundle = model.monitorSamples.bundle\n        guard let picture = NDFilterRecommendation.pictureStops(\n            lumaHistogram: bundle.samples.histogramLuma, transfer: bundle.transfer)\n        else { return nil }\n        let status = model.session.status\n        let stops = PictureEVMeter.shared.stops(\n            picture: picture, transfer: bundle.transfer,\n            evComp: status.expoMode == .auto ? status.evComp.map { Double($0.thirds) / 3 } : nil,\n            now: ProcessInfo.processInfo.systemUptime)\n        return EvComp(thirds: Int((stops * 3).rounded()))\n    }\n\n    var body: some View {\n        let frame = CameraEVMeter.frame(in: feed, avoiding: avoiding)\n")

    # --- AUDIO only where the camera reports levels (the Luna sends none); clip playback keeps it. ---
    replace_once(assists, "    var evMeterFromPicture = false\n",
                 "    var evMeterFromPicture = false\n    /// The camera reports audio levels (AUDIO in the live rail and View Assist list).\n    var cameraHasAudio = true\n")
    replace_once(APP / "FieldMonitorChrome.swift", "        return LiveAssistTool.toolbarCases + [.audioMeters]\n",
                 "        return LiveAssistTool.toolbarCases + (model.session.supportsAudio ? [.audioMeters] : [])\n")
    replace_once(assists, "                ForEach(LiveAssistTool.settingsCases) { tool in\n",
                 "                ForEach(LiveAssistTool.settingsCases.filter { $0 != .audioMeters || assist.cameraHasAudio }) { tool in\n")
    replace_once(APP / "Assists/AssistLongPressChrome.swift", "        LiveAssistTool.settingsCases.filter(\\.hasConfiguration)\n",
                 "        LiveAssistTool.settingsCases.filter { $0.hasConfiguration && ($0 != .audioMeters || assist.cameraHasAudio) }\n")
    replace_once(APP / "SettingsRootView.swift",
                 "\"Show the camera's exposure meter at the picture's left edge in DISP 1. Auto and Manual use the camera reading without changing exposure settings.\"",
                 "\"Show the exposure meter at the picture's left edge in DISP 1. It reads the camera's metered EV, or meters the picture when the camera reports none. It never changes exposure settings.\"")

    # --- Luna METER tile (Matrix / Face Priority, option 46) beside EXPOSURE. ---
    bar = APP / "LiveCameraControlBar.swift"
    replace_once(bar, "        4 + (model.session.supportsFocusMode ? 1 : 0) + (model.session.supportsAperture ? 1 : 0)\n",
                 "        4 + (model.session.supportsFocusMode ? 1 : 0) + (model.session.supportsAperture ? 1 : 0)\n            + (model.session.supportsFaceMetering ? 1 : 0)\n")
    replace_once(bar, "            tile(.exposure, label: \"EXPOSURE\", value: expoValue, widest: \"Manual\")\n",
                 "            tile(.exposure, label: \"EXPOSURE\", value: expoValue, widest: \"Manual\")\n            LunaMeteringTile(session: model.session)\n")

    # --- Wordmark (the sync rename is case-sensitive) and public pages on the combined site. ---
    for name in ("StartupChrome.swift", "AppSettings.swift"):
        replace_phrase(APP / name, 'Text("OPENPOCKETCINE")', 'Text("OPENINSTACINE")')
    site = "https://opencapture.org/openinstacine"
    for name, pairs in (
        ("AppSettings.swift", (("https://openinstacine.app/privacy/", f"{site}/privacy"),
                               ("https://openinstacine.app/terms/", f"{site}/terms"))),
        ("LegalScreens.swift", (("https://openinstacine.app/privacy/", f"{site}/privacy"),
                                ("openinstacine.app/privacy and /terms", "opencapture.org/openinstacine/privacy and /terms"),
                                ("support@openinstacine.app", "support@opencapture.org"))),
        ("ProblemReportView.swift", (("support@openinstacine.app", "support@opencapture.org"),)),
        ("ProblemReporting.swift", (("support@openinstacine.app", "support@opencapture.org"),)),
        ("SettingsRootView.swift", (("support@openinstacine.app", "support@opencapture.org"),)),
    ):
        for old_phrase, new_phrase in pairs:
            replace_phrase(APP / name, old_phrase, new_phrase)
    # --- Launch wiring + gates that assumed a DJI datalink. ---
    replace_once(
        APP / "OpenInstaCineApp.swift",
        "        MonitorTheme.prepareResources()\n",
        "        OpenInstaCineBrand.apply()\n        MonitorTheme.prepareResources()\n",
    )
    for name in ("GimbalGamepad.swift", "HeadphoneMotion.swift"):
        replace_once(
            APP / name,
            "        return model.isLive && model.session.datalink != nil\n",
            "        return model.isLive && model.session.hasControlLink\n",
        )
    # Luna renders head tracking on its own clock, so it needs each AirPods sample's time.
    replace_once(
        APP / "HeadphoneMotion.swift",
        "model.session.updateNativeHeadTrack(target: target, token: token)",
        "model.session.updateNativeHeadTrack(target: target, token: token, measuredAt: lastHeadMeasuredAt)",
    )


if __name__ == "__main__":
    main()
