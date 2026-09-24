#!/usr/bin/env python3
"""Brand-neutral hooks applied after every OpenPocketCine sync.

Keep these patches tiny. Camera protocol stays in Adapters/. If a hunk fails,
the sync must fail instead of shipping a blue OpenPocketCine clone.
"""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old not in text:
        raise SystemExit(f"{path}: expected overlay hunk missing:\n{old[:120]}")
    if text.count(old) != 1:
        raise SystemExit(f"{path}: overlay hunk matched {text.count(old)} times")
    path.write_text(text.replace(old, new, 1))


def main() -> None:
    theme = ROOT / "Sources/MonitorUI/MonitorTheme.swift"
    replace_once(
        theme,
        "        public static let accent = color(0x00A3E0)\n",
        "        /// Brand apps assign this once at launch before any view is built.\n"
        "        nonisolated(unsafe) public static var accentRGB: UInt32 = 0x00A3E0\n"
        "        public static var accent: Color { color(accentRGB) }\n",
    )

    palette = ROOT / "Apps/Android/monitor-ui/src/main/kotlin/com/opencapture/monitorui/MonitorTheme.kt"
    replace_once(
        palette,
        "    val accent = Color(0xFF00A3E0)\n",
        "    /** Brand shells assign this before composing shared screens. */\n"
        "    var accent = Color(0xFF00A3E0)\n",
    )

    colors = ROOT / "Shared/Apple/MonitorShell/Branding.swift"
    replace_once(
        colors,
        "    static let accent = Color(red: 0, green: 163 / 255, blue: 230 / 255)\n"
        "    static let accentSoft = Color(red: 0, green: 163 / 255, blue: 230 / 255).opacity(0.18)\n",
        "    static var accent: Color { MonitorTheme.accent }\n"
        "    static var accentSoft: Color { MonitorTheme.accent.opacity(0.18) }\n",
    )
    branding = colors.read_text()
    if "import MonitorUI" not in branding:
        colors.write_text(branding.replace("import SwiftUI\n", "import MonitorUI\nimport SwiftUI\n", 1))

    control = ROOT / "Sources/OpenPocketViewCore/CameraControl.swift"
    replace_once(
        control,
        """    case dLog2 = 0x41
    case normal10 = 0x3D
    case dLogM = 0x00
""",
        """    case dLog2 = 0x41
    case normal10 = 0x3D
    case dLogM = 0x00
    /// Insta360 I-Log. Not a DJI SET byte.
    case iLog = 0xE2
    /// Insta360 Dolby Vision. Not a DJI SET byte.
    case dolbyVision = 0xE5
""",
    )
    replace_once(
        control,
        """        case .dLog2: "D-Log2"
        case .normal10: "Normal 10-bit"
        case .dLogM: "D-Log M 10-bit"
""",
        """        case .dLog2: "D-Log2"
        case .normal10: "Normal 10-bit"
        case .dLogM: "D-Log M 10-bit"
        case .iLog: "I-Log"
        case .dolbyVision: "Dolby Vision"
""",
    )
    replace_once(
        control,
        """        switch self {
        case .dLog, .dLog2, .dLogM: true
        default: false
        }
""",
        """        switch self {
        case .dLog, .dLog2, .dLogM, .iLog: true
        default: false
        }
""",
    )

    transfer = ROOT / "Sources/OpenPocketViewCore/LiveColorScience.swift"
    replace_once(
        transfer,
        """        case .dLog: self = .dlog
        case .dLogM: self = .dlogm
        case .dLog2: self = .dlog2
""",
        """        case .dLog: self = .dlog
        case .dLogM: self = .dlogm
        case .dLog2: self = .dlog2
        case .iLog, .dolbyVision: self = .rec709
""",
    )

    app_model = ROOT / "Shared/Apple/MonitorShell/AppRoot.swift"
    replace_once(
        app_model,
        "    var isOnCameraAccessPoint: Bool { WiFiJoiner.isCameraPathReady() }\n",
        "    var isOnCameraAccessPoint: Bool { session.isOnCameraNetwork }\n",
    )


if __name__ == "__main__":
    main()
