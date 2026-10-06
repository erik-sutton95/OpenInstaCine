import Insta360Apple
import OpenCineCore
import OpenPocketViewCore
import XCTest

@testable import OpenInstaCine

/// OpenZCine `ChromeEditorReturnTests` — Edit view entry, exit, and force-mount.
@MainActor
final class ChromeEditorReturnTests: XCTestCase {
    /// A connect presents the monitor through the shell: no leftover cover or Edit view.
    @MainActor
    func testBecomingLiveDismissesSettingsAndHomePanels() {
        let model = AppModel()
        model.shell.open(.settings)
        model.operatorSettingsTab = .display
        model.chromeEditorMode = .live
        model.chromeEditorReturnMode = .live

        model.shell.present(Self.camera(model))
        model.noteMonitorChanged()

        XCTAssertTrue(model.isLive)
        XCTAssertNil(model.shell.cover)
        XCTAssertNil(model.chromeEditorMode)
        XCTAssertNil(model.chromeEditorReturnMode)
        XCTAssertFalse(model.liveChromeInteractive)
        model.shell.close()
    }

    @MainActor
    func testLeavingLiveDismissesOperatorSetup() {
        let model = AppModel()
        model.shell.present(Self.camera(model))
        model.shell.open(.settings)
        model.chromeEditorMode = .clean

        model.shell.close()
        model.noteMonitorChanged()

        XCTAssertFalse(model.isLive)
        XCTAssertNil(model.shell.cover)
        XCTAssertNil(model.chromeEditorMode)
        XCTAssertTrue(model.liveChromeInteractive)
    }

    /// An unconnected Luna session on the monitor, as a connect hands it over.
    @MainActor
    static func camera(_ model: AppModel) -> ConnectedCamera {
        ConnectedCamera(
            saved: SavedCamera(id: UUID().uuidString, integration: LunaCameraSession.integration, advertisedName: "Luna", model: "Luna Ultra"),
            session: model.session.backend.openSession())
    }

    @MainActor
    func testOpeningTheEditorLeavesSettingsAndSwitchesMode() {
        let model = AppModel()
        model.shell.open(.settings)
        model.assist.clean = false

        model.beginChromeEditing(.clean)

        XCTAssertNil(model.shell.cover)
        XCTAssertTrue(model.assist.clean)
        XCTAssertEqual(model.chromeEditorMode, .clean)
        XCTAssertEqual(model.currentDispMode, .clean)
    }

    @MainActor
    func testDoneReturnsToDisplaySettingsOnEditedSection() {
        let model = AppModel()
        model.beginChromeEditing(.clean)

        model.endChromeEditing()

        XCTAssertNil(model.chromeEditorMode)
        XCTAssertEqual(model.shell.cover, .settings)
        XCTAssertEqual(model.operatorSettingsTab, .display)
        XCTAssertEqual(model.chromeEditorReturnMode, .clean)
    }

    @MainActor
    func testToggleChromeOnlyTouchesTheEditedMode() {
        let model = AppModel()
        let savedLive = model.dispLive
        let savedClean = model.dispClean
        defer {
            model.dispLive = savedLive
            model.dispClean = savedClean
        }
        model.dispLive = .liveDefaults
        // Start clean from the same full set so the flip is unambiguous.
        model.dispClean = .liveDefaults

        model.toggleChrome(.statusBar, for: .clean)

        XCTAssertTrue(model.dispLive.statusBar)
        XCTAssertFalse(model.dispClean.statusBar)
        XCTAssertTrue(model.dispClean.railRecord)
    }

    @MainActor
    func testChromeForceMountsWhileEditingHiddenItems() {
        let model = AppModel()
        let savedLive = model.dispLive
        defer { model.dispLive = savedLive }
        model.dispLive = .liveDefaults
        model.dispLive.statusBar = false
        model.assist.clean = false

        XCTAssertFalse(model.chromeSectionMounts(.statusBar))

        model.beginChromeEditing(.live)

        XCTAssertTrue(model.chromeSectionMounts(.statusBar))
        XCTAssertTrue(model.isEditingChrome)
    }

    @MainActor
    func testSettingsRailRemainsReachableIfBothModesHideIt() {
        let model = AppModel()
        let savedLive = model.dispLive
        let savedClean = model.dispClean
        defer {
            model.dispLive = savedLive
            model.dispClean = savedClean
        }
        model.dispLive = .liveDefaults
        model.dispClean = .cleanDefaults
        model.dispLive.railSettings = false
        model.dispClean.railSettings = false
        model.assist.clean = false

        XCTAssertTrue(model.chromeSectionMounts(.railSettings))
    }

    func testCleanViewPinsFilterWithoutMutatingOnOff() {
        let assist = LiveAssistState()
        assist.histogram = true
        assist.peaking = true
        assist.cleanViewPinnedTools = [.peaking]
        assist.clean = false

        XCTAssertTrue(assist.isVisible(.peaking))
        XCTAssertTrue(assist.isVisible(.histogram))
        XCTAssertTrue(assist.effects.histogram)

        assist.clean = true

        XCTAssertTrue(assist.isVisible(.peaking))
        XCTAssertFalse(assist.isVisible(.histogram))
        XCTAssertTrue(assist.isOn(.histogram))
        XCTAssertTrue(assist.effects.peaking)
        XCTAssertFalse(assist.effects.histogram)
    }

    func testCleanViewPinCannotResurrectASwitchedOffTool() {
        let assist = LiveAssistState()
        assist.waveform = false
        assist.clean = true
        assist.cleanViewPinnedTools = [.waveform]
        XCTAssertFalse(assist.isVisible(.waveform))
        XCTAssertFalse(assist.effects.waveform)
    }

    func testAbsentCleanPinPrefsLoadStockSet() {
        let key = "OpenInstaCine.CleanViewPins.v1"
        let saved = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        XCTAssertEqual(
            OperatorPrefs.cleanViewPinnedTools,
            LiveAssistState.cleanViewDefaultPinnedTools
        )
    }
}
