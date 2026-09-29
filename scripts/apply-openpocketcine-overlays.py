#!/usr/bin/env python3
"""Brand hunks applied after every OpenPocketCine sync (see sync-openpocketcine.sh).

Keep these patches tiny and exact. Camera protocol lives in Adapters/ and in the
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
    # --- Brand accent: one engine token, assigned once at launch. ---
    theme = ROOT / "Sources/MonitorUI/MonitorTheme.swift"
    replace_once(
        theme,
        "        public static var accent: Color { edrAccent(gain: hdrGain) }\n",
        "        /// Brand storefronts assign this once at launch, before any view is built.\n"
        "        nonisolated(unsafe) public static var accentRGB: UInt32 = 0x00A3E0\n"
        "        public static var accent: Color { edrAccent(gain: hdrGain) }\n"
        "        /// Ink for text/icons drawn ON an accent fill. Light accents (yellow) need dark ink.\n"
        "        public static var onAccent: Color { accentIsLight ? color(0x111213) : .white }\n"
        "        public static var accentIsLight: Bool {\n"
        "            let r = Double((accentRGB >> 16) & 255), g = Double((accentRGB >> 8) & 255)\n"
        "            let b = Double(accentRGB & 255)\n"
        "            return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255 > 0.6\n"
        "        }\n",
    )
    replace_once(
        theme,
        "            edrSRGB(red: 0, green: 163 / 255, blue: 230 / 255, gain: gain)\n",
        "            edrSRGB(\n"
        "                red: CGFloat((accentRGB >> 16) & 255) / 255,\n"
        "                green: CGFloat((accentRGB >> 8) & 255) / 255,\n"
        "                blue: CGFloat(accentRGB & 255) / 255, gain: gain)\n",
    )

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

    # --- Xcode project: Luna adapter packages, usage copy, official-app XC driver. ---
    project = ROOT / "ios/project.yml"
    replace_once(
        project,
        "  OpenPocketViewCore:\n    path: ..\n",
        "  OpenPocketViewCore:\n    path: ..\n"
        "  Insta360Protocol:\n    path: ../Adapters/Insta360Protocol\n",
    )
    replace_once(
        project,
        "targets:\n  OpenInstaCine:\n",
        "targets:\n"
        "  # Luna wire I/O: CoreBluetooth, camera Wi-Fi, TCP 6666, screen KCP.\n"
        "  Insta360Apple:\n"
        "    type: framework\n"
        "    platform: iOS\n"
        "    sources:\n"
        "      - ../Adapters/Insta360Apple/Sources/Insta360Apple\n"
        "      - path: ../Adapters/Insta360Apple/Sources/CKcp\n"
        "        excludes:\n"
        "          - module.modulemap\n"
        "          - LICENSE\n"
        "    dependencies:\n"
        "      - package: OpenPocketViewCore\n"
        "        product: MonitorContracts\n"
        "      - package: Insta360Protocol\n"
        "        product: Insta360Protocol\n"
        "    settings:\n"
        "      base:\n"
        '        SWIFT_VERSION: "5.0"\n'
        "        PRODUCT_BUNDLE_IDENTIFIER: com.opencapture.insta360adapter\n"
        "        CLANG_ENABLE_MODULES: YES\n"
        "        GENERATE_INFOPLIST_FILE: YES\n"
        '        DEVELOPMENT_TEAM: "4V4EGQ6LZA"\n'
        "        CODE_SIGN_STYLE: Automatic\n"
        "        SKIP_INSTALL: YES\n"
        "\n"
        "  OpenInstaCine:\n",
    )
    replace_once(
        project,
        "      - package: OpenPocketViewCore\n        product: MonitorPresentation\n"
        "      - target: OpenInstaCineWatch\n",
        "      - package: OpenPocketViewCore\n        product: MonitorPresentation\n"
        "      - package: OpenPocketViewCore\n        product: MonitorContracts\n"
        "      - package: Insta360Protocol\n        product: Insta360Protocol\n"
        "      - target: Insta360Apple\n"
        "      - target: OpenInstaCineWatch\n",
    )
    replace_once(
        project,
        '"OpenInstaCine uses Bluetooth to find and pair with your DJI Osmo Pocket and hand off Wi-Fi."',
        '"OpenInstaCine uses Bluetooth to find your Insta360 Luna, ask it for approval, and hand off to its Wi-Fi."',
    )
    replace_once(
        project,
        "schemes:\n",
        "  # Lab-only XC driver for the official Insta360 app (capture sessions).\n"
        "  LunaOfficialUITests:\n"
        "    type: bundle.ui-testing\n"
        "    platform: iOS\n"
        "    sources:\n"
        "      - LunaOfficialUITests\n"
        "    dependencies:\n"
        "      - target: OpenInstaCine\n"
        "    settings:\n"
        "      base:\n"
        '        SWIFT_VERSION: "5.0"\n'
        "        GENERATE_INFOPLIST_FILE: YES\n"
        "        PRODUCT_BUNDLE_IDENTIFIER: com.opencapture.openinstacine.official-uitests\n"
        "        TEST_TARGET_NAME: OpenInstaCine\n"
        '        DEVELOPMENT_TEAM: "4V4EGQ6LZA"\n'
        "        CODE_SIGN_STYLE: Automatic\n"
        "\n"
        "schemes:\n"
        "  LunaOfficialCapture:\n"
        "    build:\n"
        "      targets:\n"
        "        OpenInstaCine: all\n"
        "        LunaOfficialUITests: [test]\n"
        "    test:\n"
        "      targets:\n"
        "        - LunaOfficialUITests\n",
    )

    replace_once(
        project,
        "      - target: OpenInstaCine\n      - package: OpenPocketViewCore\n        product: OpenPocketViewCore\n    settings:\n      base:\n        SWIFT_VERSION: \"5.0\"\n        GENERATE_INFOPLIST_FILE: YES\n        PRODUCT_BUNDLE_IDENTIFIER: com.opencapture.openinstacine.tests\n",
        "      - target: OpenInstaCine\n      - package: OpenPocketViewCore\n        product: OpenPocketViewCore\n      - package: Insta360Protocol\n        product: Insta360Protocol\n    settings:\n      base:\n        SWIFT_VERSION: \"5.0\"\n        GENERATE_INFOPLIST_FILE: YES\n        PRODUCT_BUNDLE_IDENTIFIER: com.opencapture.openinstacine.tests\n",
    )

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


if __name__ == "__main__":
    main()
