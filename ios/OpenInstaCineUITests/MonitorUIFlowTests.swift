import MonitorPresentation
import OpenCineAppUITesting
import UIKit
import XCTest

/// These exercise rendered hit targets and navigation, not camera transport.
/// Optional OPV_SIM_FEED_CLIP points at private local footage for the live feed; media screens
/// stage generated clips (`ReviewClip`). Screenshots are attached to the local xcresult only.
final class MonitorUIFlowTests: SharedAppUITestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchEnvironment = ReviewLaunch(screen: .live).environment
        for key in ["OPV_SIM_FEED_CLIP", "OPV_SIM_FEED_CLIP_B", "OPV_SIM_FEED_MANIFEST", "OPV_UI_REVIEW_PLAYBACK_FACTS"] {
            if let value = ProcessInfo.processInfo.environment[key] { app.launchEnvironment[key] = value }
        }
    }

    override func tearDown() {
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testUnknownCoreReportsStayUnknownAndCannotApproveRecording() {
        app.launchEnvironment["OPV_UI_REVIEW_CORE_UNKNOWN"] = "1"
        app.launch()
        let record = app.buttons["monitor.system.record"]
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        XCTAssertEqual(record.label, "Recording state unknown")
        XCTAssertFalse(record.isEnabled)
        let tally = app.descendants(matching: .any)["monitor.recording.readout"].firstMatch
        XCTAssertEqual(tally.label, "Recording state unknown")
        let iso = app.buttons["monitor.capture.iso"]
        XCTAssertEqual(iso.value as? String, "Not set")
        XCTAssertFalse(iso.isEnabled)
        record.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertFalse(app.buttons["Start"].exists)
        capture("SIMULATED-monitor-core-unknown")
    }

    func testMonitorControlsAcrossBothLandscapeOrientationsAndPortrait() {
        app.launchEnvironment["OPV_UI_REVIEW_FIT"] = "1"
        app.launch()
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft, .landscapeRight] {
            rotate(orientation)
            let record = app.buttons["monitor.system.record"]
            XCTAssertTrue(record.waitForExistence(timeout: 10))
            XCTAssertTrue(record.isHittable)
            XCTAssertTrue(app.buttons["monitor.system.settings"].isHittable)
            XCTAssertTrue(app.buttons["monitor.system.media"].isHittable)
            XCTAssertEqual(app.buttons.matching(identifier: "monitor.capture.iso").count, 1)
            XCTAssertTrue(app.buttons["monitor.capture.iso"].isHittable)
            let buttonFrame = record.frame
            XCTAssertGreaterThanOrEqual(buttonFrame.minX, 0)
            XCTAssertLessThanOrEqual(buttonFrame.maxX, app.frame.width)
            XCTAssertLessThanOrEqual(buttonFrame.maxY, app.frame.height)
            if UIDevice.current.userInterfaceIdiom == .phone, orientation != .portrait,
                app.frame.width > 700
            {
                XCTAssertEqual(
                    app.buttons["monitor.system.settings"].frame.minY,
                    8 + app.frame.height * 0.025, accuracy: 1,
                    "Phone corner clearance must stay small and separate from iPad window exclusions"
                )
            }
            let lockFrame = app.buttons["monitor.system.lock"].frame
            let settingsFrame = app.buttons["monitor.system.settings"].frame
            XCTAssertEqual(lockFrame.width, settingsFrame.width, accuracy: 0.5)
            XCTAssertEqual(lockFrame.height, settingsFrame.height, accuracy: 0.5)
            XCTAssertEqual(lockFrame.midY, settingsFrame.midY, accuracy: 0.5)
            let format = app.buttons["monitor.capture.format"]
            let tally = app.descendants(matching: .any)["monitor.recording.readout"].firstMatch
            XCTAssertTrue(tally.exists)
            if orientation == .portrait {
                // Portrait stacks the format over its detail in one trailing column, so the
                // header aligns component tops (OpenCine docs/ui, MonitorScreenshotLayoutTests).
                XCTAssertEqual(format.frame.minY, tally.frame.minY, accuracy: 1)
            } else {
                XCTAssertEqual(format.frame.midY, tally.frame.midY, accuracy: 1)
            }
            let cameraBattery = app.descendants(matching: .any)["monitor.telemetry.camera"]
                .firstMatch
            XCTAssertTrue(cameraBattery.exists)
            // The shared gauge speaks its title as the label and the charge as the value.
            XCTAssertEqual(cameraBattery.label, "Camera battery")
            XCTAssertEqual(cameraBattery.value as? String, "68 percent")
            capture("monitor-\(orientation.rawValue)")
        }
    }

    func testAssistPaletteAndValueDrumRemainReachable() {
        app.launch()
        rotate(.landscapeLeft)
        let expand = app.buttons["monitor.assists.expand"]
        XCTAssertTrue(expand.waitForExistence(timeout: 10))
        let systemFrame = app.buttons["monitor.system.settings"].frame
        for tool in ["PEAK", "FALSE"] {
            let frame = app.buttons["monitor.assist.\(tool)"].frame
            XCTAssertEqual(frame.width, systemFrame.width, accuracy: 1)
            XCTAssertEqual(frame.height, systemFrame.height, accuracy: 1)
        }
        XCTAssertEqual(expand.frame.width, 27, accuracy: 1)
        capture("assist-favorites")
        expand.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let wave = app.buttons["monitor.assist.WAVE"]
        XCTAssertTrue(wave.waitForExistence(timeout: 5))
        XCTAssertEqual(wave.frame.width, systemFrame.width, accuracy: 1)
        XCTAssertEqual(wave.frame.height, systemFrame.height, accuracy: 1)
        wave.tap()
        capture("assist-palette")
        app.buttons["Collapse View Assist tools"].tap()
        app.buttons["monitor.capture.iso"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["Value"].firstMatch.waitForExistence(timeout: 5))
        capture("iso-drum")
    }

    func testPortraitToolsStayInPlaceWhenFitFillChanges() {
        app.launchEnvironment["OPV_UI_REVIEW_FIT"] = "1"
        app.launch()
        let aspect = app.buttons.matching(
            NSPredicate(format: "label IN %@", ["Fill frame with feed", "Fit feed in frame"])
        ).firstMatch
        XCTAssertTrue(aspect.waitForExistence(timeout: 10))
        let peak = app.buttons["monitor.assist.PEAK"]
        XCTAssertTrue(peak.waitForExistence(timeout: 5))
        XCTAssertTrue(peak.isHittable, "Portrait collapsed View Assist must show a favorite tool")
        XCTAssertEqual(peak.frame.height, MonitorSystemButtonMetrics.side(tablet: UIDevice.current.userInterfaceIdiom == .pad), accuracy: 1)
        let tools = [
            app.buttons["monitor.assists.expand"],
            peak,
            app.buttons["monitor.system.zoom"],
            app.buttons["monitor.system.gimbalControls"],
            app.descendants(matching: .any)["monitor.system.gimbal"].firstMatch,
            aspect,
        ]
        let frames = tools.map(\.frame)
        for value in ["Fill", "Fit"] {
            aspect.tap()
            expectation(for: NSPredicate(format: "value == %@", value), evaluatedWith: aspect)
            waitForExpectations(timeout: 5)
            for (tool, frame) in zip(tools, frames) {
                XCTAssertEqual(tool.frame.minX, frame.minX, accuracy: 0.5)
                XCTAssertEqual(tool.frame.minY, frame.minY, accuracy: 0.5)
                XCTAssertEqual(tool.frame.width, frame.width, accuracy: 0.5)
                XCTAssertEqual(tool.frame.height, frame.height, accuracy: 0.5)
                XCTAssertLessThan(tool.frame.maxY, app.buttons["monitor.capture.iso"].frame.minY)
            }
            capture("portrait-fixed-tools-\(value.lowercased())")
        }
    }

    func testSettingsTabsKeepBaselineSpacingAndSelection() {
        let physicalReview = ProcessInfo.processInfo.environment["OPV_PHYSICAL_UI_REVIEW"] == "1"
        if physicalReview { app.launchEnvironment["OPV_PHYSICAL_UI_REVIEW"] = "1" }
        app.launch()
        let liveSettings = app.buttons["monitor.system.settings"]
        let homeSettings = app.buttons["cameras.settings"]
        expectation(
            for: NSPredicate { _, _ in liveSettings.exists || homeSettings.exists },
            evaluatedWith: app)
        waitForExpectations(timeout: 20)
        // On hardware the launch splash can cover controls already in the AX tree.
        if physicalReview { Thread.sleep(forTimeInterval: 3) }
        let settings = liveSettings.exists ? liveSettings : homeSettings
        XCTAssertTrue(settings.isHittable)
        settings.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            rotate(orientation)
            let link = app.buttons["monitor.settings.tab.Link"]
            let sharing = app.buttons["monitor.settings.tab.Sharing"]
            XCTAssertTrue(link.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(link.frame.height, 44 - 0.001)
            XCTAssertGreaterThanOrEqual(sharing.frame.height, 44 - 0.001)
            // Preserve the six-point gap measured in the app before shared settings adoption.
            if orientation == .portrait {
                XCTAssertEqual(sharing.frame.minX - link.frame.maxX, 6, accuracy: 0.5)
            } else {
                XCTAssertEqual(sharing.frame.minY - link.frame.maxY, 6, accuracy: 0.5)
            }
            sharing.tap()
            XCTAssertTrue(sharing.isSelected)
            XCTAssertFalse(link.isSelected)
            link.tap()
            XCTAssertTrue(link.isSelected)
            XCTAssertFalse(sharing.isSelected)
            capture("settings-joined-tabs-\(orientation.rawValue)")
        }
    }

    /// A2-24: the problem report opens over the app root and closing it returns to Settings,
    /// in portrait and landscape.
    func testSettingsReportOpensOverTheRootAndReturnsToSettings() {
        launch(ReviewLaunch(screen: .settings))
        let tabs = app.scrollViews["monitor.settings.tabs"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            rotate(orientation)
            let system = app.buttons["monitor.settings.tab.System"]
            reveal(system, in: tabs, portrait: orientation == .portrait)
            system.tap()
            let report = app.buttons["support.report.open"]
            XCTAssertTrue(report.waitForExistence(timeout: 5))
            for _ in 0..<4 where !report.isHittable { app.swipeUp() }
            report.tap()
            XCTAssertTrue(app.textViews["What happened?"].waitForExistence(timeout: 5))
            capture("settings-report-\(orientation.rawValue)")
            app.buttons["Close"].firstMatch.tap()
            XCTAssertTrue(system.waitForExistence(timeout: 5))
            XCTAssertFalse(app.textViews["What happened?"].exists)
            XCTAssertTrue(system.isSelected)
        }
    }

    /// A2-84: Settings reopens on the tab it was left on, scrolled where it was left.
    func testSettingsReopenOnTheLastTabAtItsScrollPosition() throws {
        app.launch()
        let open = app.buttons["monitor.system.settings"]
        XCTAssertTrue(open.waitForExistence(timeout: 20))
        open.tap()
        let tabs = app.scrollViews["monitor.settings.tabs"]
        let assist = app.buttons["monitor.settings.tab.View Assist"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        reveal(assist, in: tabs, portrait: true)
        assist.tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
            .press(forDuration: 0.01,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
        let cards = app.staticTexts.matching(identifier: "monitor.settings.card.title")
        // Measure where the page comes to rest after the fling, the position it must keep.
        var resting = CGRect.null
        for _ in 0..<20 {
            Thread.sleep(forTimeInterval: 0.3)
            let frame = cards.firstMatch.frame
            if frame == resting { break }
            resting = frame
        }
        let window = app.frame
        // The first card title fully inside the page, below the tab rail.
        let marker = try XCTUnwrap(cards.allElementsBoundByIndex.first {
            $0.frame.minY > window.minY + 160 && $0.frame.maxY < window.maxY - 60
        }, "A card title is on screen after scrolling")
        let label = marker.label
        let top = marker.frame.minY
        capture("settings-scroll-before-close")
        app.buttons["Back to live"].tap()
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        XCTAssertTrue(assist.waitForExistence(timeout: 5))
        XCTAssertTrue(assist.isSelected, "Settings reopens on the last tab")
        let again = cards.matching(NSPredicate(format: "label == %@", label)).firstMatch
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        // Exact: the page commits the offset it comes to rest at, not the last throttled sample.
        XCTAssertEqual(again.frame.minY, top, accuracy: 0.5, "The tab keeps its scroll position")
        capture("settings-scroll-after-reopen")
    }

    func testSettingsCoverageAndCardTitleSpacing() throws {
        app.launch()
        rotate(.landscapeLeft)
        app.buttons["monitor.system.settings"].tap()
        let back = app.buttons["Back to live"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["monitor.system.record"].isHittable)
        app.buttons["monitor.settings.tab.View Assist"].tap()
        let zebra = app.staticTexts.matching(
            NSPredicate(
                format: "identifier == %@ AND label == %@",
                "monitor.settings.card.title", "Zebra")
        ).firstMatch
        let falseColor = app.staticTexts.matching(
            NSPredicate(format: "identifier == %@ AND label == %@",
                "monitor.settings.card.title", "False Color")).firstMatch
        let evMeter = app.staticTexts.matching(
            NSPredicate(format: "identifier == %@ AND label == %@",
                "monitor.settings.card.title", "EV Meter")).firstMatch
        if app.frame.width > 700 {
            // main: the tool cards stay in one column, with EV Meter and LUT beside them.
            XCTAssertEqual(zebra.frame.minX, falseColor.frame.minX, accuracy: 1,
                "Zebra sits in False Color's column")
            XCTAssertGreaterThan(zebra.frame.minY, falseColor.frame.maxY)
            XCTAssertGreaterThan(evMeter.frame.minX, falseColor.frame.maxX,
                "EV Meter sits beside the tool column")
        }
        for _ in 0..<6 where !zebra.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.8))
                .press(
                    forDuration: 0.01,
                    thenDragTo:
                        app.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.4)))
        }
        XCTAssertTrue(zebra.isHittable, "The Zebra title remains visible")
        let title = zebra.frame
        let units = try XCTUnwrap(
            app.staticTexts.matching(identifier: "monitor.settings.row.title")
                .allElementsBoundByIndex
                .filter { $0.label == "Units" && abs($0.frame.minX - title.minX) < 30 }
                .min { abs($0.frame.minY - title.maxY) < abs($1.frame.minY - title.maxY) })
        XCTAssertGreaterThanOrEqual(units.frame.minY - title.maxY, 8)
        capture("settings-zebra-spacing")
        back.tap()
        XCTAssertTrue(app.buttons["monitor.system.record"].isHittable)
        XCTAssertTrue(app.buttons["monitor.capture.iso"].isHittable)
    }

    func testCoveredPickerControlsAreInaccessibleAndReturnWithTheirState() {
        app.launch()
        rotate(.portrait)
        app.buttons["monitor.capture.iso"].tap()
        let panel = app.descendants(matching: .any)["monitor.capture.panel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        for (control, backLabel) in [("settings", "Back to live"), ("media", "Back")] {
            let navigation = app.buttons["monitor.system.\(control)"]
            XCTAssertTrue(navigation.isHittable)
            navigation.tap()
            let back = app.buttons[backLabel].firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            capture("covered-picker-\(control)")
            // XCTest still inventories mounted layout containers and hidden
            // controls. Test actionable reachability rather than query omission.
            XCTAssertFalse(app.buttons["monitor.capture.close"].isHittable)
            XCTAssertFalse(app.buttons["monitor.system.record"].isHittable)
            XCTAssertFalse(app.buttons["monitor.capture.iso"].isHittable)
            XCTAssertFalse(navigation.isHittable)
            back.tap()
            XCTAssertTrue(panel.isHittable, "The same picker returns after \(control)")
            XCTAssertTrue(app.buttons["monitor.capture.close"].isHittable)
            XCTAssertTrue(app.buttons["monitor.system.record"].isHittable)
        }
        app.buttons["monitor.capture.close"].tap()
        XCTAssertTrue(app.buttons["monitor.capture.iso"].isHittable)
    }

    func testRecordHoldDoesNotRecordAndLockedControlsStayBlocked() {
        app.launch()
        let record = app.buttons["monitor.system.record"]
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        record.press(forDuration: 0.6)
        XCTAssertTrue(app.staticTexts["Shooting mode"].waitForExistence(timeout: 5))
        XCTAssertFalse(
            app.buttons["Start"].exists, "Holding Record must not also open its confirmation")
        capture("record-hold-mode")
        app.buttons["Close"].firstMatch.tap()
        XCTAssertFalse(
            app.staticTexts["Shooting mode"].exists,
            "Close must dismiss the recording picker before Lock is tapped"
        )
        app.buttons["monitor.system.lock"].tap()
        let locked = NSPredicate(format: "label == %@", "Unlock monitor controls")
        expectation(for: locked, evaluatedWith: app.buttons["monitor.system.lock"])
        waitForExpectations(timeout: 5)
        capture("monitor-locked")
        XCTAssertFalse(app.buttons["monitor.system.settings"].isEnabled)
        XCTAssertFalse(app.buttons["monitor.system.media"].isEnabled)
        XCTAssertFalse(record.isEnabled)
        record.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertFalse(
            app.buttons["Start"].exists,
            "A touch on the disabled Record control must not open confirmation"
        )
        XCTAssertFalse(app.staticTexts["Shooting mode"].exists)
        app.buttons["monitor.system.lock"].tap()
        XCTAssertTrue(record.isEnabled)
    }

    func testDrawersAndContinuousZoomSurviveRotation() {
        app.launch()
        let gimbal = app.buttons["monitor.system.gimbalControls"]
        XCTAssertTrue(gimbal.waitForExistence(timeout: 10))
        gimbal.tap()
        XCTAssertTrue(app.buttons["Close Gimbal"].waitForExistence(timeout: 5))
        capture("gimbal-portrait")
        rotate(.landscapeLeft)
        XCTAssertTrue(app.buttons["Close Gimbal"].isHittable)
        capture("gimbal-landscape")
        let gimbalPanel = app.otherElements["monitor.inspector"]
        let panelFrame = gimbalPanel.frame
        XCTAssertEqual(panelFrame.width, min(460, app.frame.width * 0.92), accuracy: 1)
        for tab in ["Speed", "Ramp", "Mode"] {
            app.buttons[tab].firstMatch.tap()
            XCTAssertTrue(app.descendants(matching: .any)["Value"].firstMatch.exists)
            XCTAssertEqual(gimbalPanel.frame.width, panelFrame.width, accuracy: 1)
            XCTAssertEqual(gimbalPanel.frame.height, panelFrame.height, accuracy: 1)
            capture("gimbal-tab-\(tab)")
        }
        app.buttons["Close Gimbal"].tap()
        app.buttons["monitor.system.zoom"].press(forDuration: 0.55)
        let dial = app.descendants(matching: .any)["monitor.zoom.dial"].firstMatch
        XCTAssertTrue(dial.waitForExistence(timeout: 5))
        for control in ["record", "display", "settings", "media"] {
            XCTAssertFalse(
                app.buttons["monitor.system.\(control)"].isHittable,
                "The zoom modal must cover underlying \(control) controls")
        }
        capture("zoom-dial-landscape")
        XCTAssertGreaterThan(
            dial.frame.height, dial.frame.width,
            "Landscape zoom disc must be a trailing half-circle")
        XCTAssertGreaterThan(
            dial.frame.minX, app.frame.midX - 24,
            "Landscape zoom disc must sit on the trailing edge, not over the picture")
        XCTAssertEqual(dial.frame.maxX, app.frame.maxX, accuracy: 12)
        rotate(.portrait)
        XCTAssertTrue(dial.isHittable)
        XCTAssertGreaterThan(
            dial.frame.width, dial.frame.height,
            "Portrait zoom disc must be a bottom half-circle")
        XCTAssertEqual(
            dial.frame.maxY, app.frame.maxY, accuracy: 12,
            "Portrait zoom disc must sit on the screen bottom edge")
        let record = app.buttons["monitor.system.record"]
        XCTAssertTrue(record.exists)
        XCTAssertFalse(
            record.isHittable,
            "The portrait zoom disc covers the bottom system controls")
        capture("zoom-dial-portrait")
        app.buttons["Close zoom dial"].tap()
        let iso = app.buttons["monitor.capture.iso"]
        let display = app.buttons["monitor.system.display"]
        // Dismissal keeps the overlay mounted through its exit animation.
        expectation(
            for: NSPredicate { _, _ in
                !dial.exists && iso.isHittable && record.isHittable && display.isHittable
            }, evaluatedWith: app)
        waitForExpectations(timeout: 3)
        XCTAssertTrue(app.buttons["monitor.capture.iso"].isHittable)
        XCTAssertTrue(app.buttons["monitor.system.record"].isHittable)
        XCTAssertTrue(app.buttons["monitor.system.display"].isHittable)
    }

    func testFocusRecenterShowsInPortraitAndLandscape() {
        app.launch()
        let reset = app.buttons["monitor.system.focusReset"]
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            rotate(orientation)
            XCTAssertTrue(app.buttons["monitor.system.record"].waitForExistence(timeout: 10))
            // An off-centre tap-to-focus is what offers Recenter.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3)).tap()
            XCTAssertTrue(reset.waitForExistence(timeout: 5))
            XCTAssertTrue(reset.isHittable)
            capture("focus-recenter-\(orientation.rawValue)")
            reset.tap()
            XCTAssertTrue(reset.waitForNonExistence(timeout: 5))
        }
    }

    func testAssistInspectorTabsSurviveRotation() {
        app.launch()
        app.buttons["monitor.assists.expand"].tap()
        let peak = app.buttons["monitor.assist.PEAK"]
        XCTAssertTrue(peak.waitForExistence(timeout: 5))
        peak.press(forDuration: 0.55)
        let inspector = app.otherElements["monitor.inspector"]
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        capture("assist-inspector-portrait")
        rotate(.landscapeRight)
        XCTAssertTrue(inspector.exists)
        app.buttons["Zebra"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Close Zebra"].waitForExistence(timeout: 5))
        capture("assist-inspector-landscape")
    }

    func testScopeTuningDeliversSelectionSliderAndGuideInputAcrossRotation() {
        app.launch()
        let expand = app.buttons["monitor.assists.expand"]
        XCTAssertTrue(expand.waitForExistence(timeout: 10))
        expand.tap()
        let wave = app.buttons["monitor.assist.WAVE"]
        XCTAssertTrue(wave.waitForExistence(timeout: 5))
        wave.press(forDuration: 0.55)
        XCTAssertTrue(app.buttons["Close Waveform"].waitForExistence(timeout: 5))
        let luma = app.buttons["Luma"]
        XCTAssertTrue(luma.isHittable)
        luma.tap()
        XCTAssertTrue(luma.isSelected)
        let brightness = app.sliders.firstMatch
        XCTAssertTrue(brightness.isHittable)
        let prior = Int(brightness.value as? String ?? "") ?? 100
        brightness.adjust(toNormalizedSliderPosition: prior > 100 ? 0.25 : 0.75)
        guard let observed = Int(brightness.value as? String ?? "") else {
            XCTFail("Native slider must report the current stepped brightness")
            return
        }
        XCTAssertNotEqual(observed, prior)
        XCTAssertTrue((0...200).contains(observed))
        XCTAssertTrue(app.staticTexts["\(observed)%"].waitForExistence(timeout: 3))
        let clip = app.buttons["Safe clip"]
        let initial = clip.value as? String
        XCTAssertTrue(initial == "On" || initial == "Off")
        clip.tap()
        let changed = initial == "On" ? "Off" : "On"
        XCTAssertEqual(clip.value as? String, changed)
        rotate(.landscapeRight)
        XCTAssertTrue(app.buttons["Close Waveform"].exists)
        XCTAssertTrue(app.buttons["Luma"].isSelected)
        XCTAssertEqual(app.buttons["Safe clip"].value as? String, changed)
        XCTAssertTrue(app.staticTexts["\(observed)%"].exists)
        capture("SIMULATED-scope-tuning-landscape")
        app.buttons["Close Waveform"].tap()
        XCTAssertTrue(app.buttons["monitor.system.record"].isHittable)
    }

    func testAssistInspectorRepeatedTabSwitchesKeepOneStablePanel() {
        app.launch()
        rotate(.landscapeLeft)
        app.buttons["monitor.assists.expand"].tap()
        let peak = app.buttons["monitor.assist.PEAK"]
        XCTAssertTrue(peak.waitForExistence(timeout: 5))
        peak.press(forDuration: 0.55)
        let inspector = app.otherElements["monitor.inspector"]
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        let initialFrame = inspector.frame
        for iteration in 0..<20 {
            for title in ["False Color", "Zebra", "Peaking"] {
                app.buttons[title].firstMatch.tap()
                XCTAssertEqual(
                    app.state, .runningForeground, "Terminated at \(iteration): \(title)")
                XCTAssertTrue(app.buttons["Close \(title)"].waitForExistence(timeout: 3))
                XCTAssertEqual(inspector.frame.width, initialFrame.width, accuracy: 1)
                XCTAssertEqual(inspector.frame.height, initialFrame.height, accuracy: 1)
                if iteration == 0 { capture("assist-options-\(title)") }
            }
        }
        capture("assist-inspector-stress")
        app.buttons["Close Peaking"].tap()
        XCTAssertTrue(app.buttons["monitor.system.record"].isHittable)
    }

    func testTopRecordingFormatOpensFromLandscape() {
        app.launch()
        rotate(.landscapeLeft)
        let format = app.buttons["monitor.capture.format"]
        XCTAssertTrue(format.isHittable)
        XCTAssertGreaterThanOrEqual(format.frame.minY, 0)
        format.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["monitor.capture.panel"].firstMatch.waitForExistence(
                timeout: 5))
        capture("capture-top-format-landscape")
    }

    func testCameraPickersUseReferenceTopAndBottomAnchors() {
        app.launch()
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            rotate(orientation)
            let identifiers =
                // A Luna body reports no camera audio, so there is no AUDIO picker.
                ["iso", "shutter", "exposure", "wb", "focus", "format"]
                + (orientation == .landscapeLeft ? ["color", "mode"] : [])
            for id in identifiers {
                app.buttons["monitor.capture.\(id)"].tap()
                let panel = app.descendants(matching: .any)["monitor.capture.panel"].firstMatch
                XCTAssertTrue(panel.waitForExistence(timeout: 5), id)
                XCTAssertEqual(panel.frame.midX, app.frame.midX, accuracy: 1, id)
                XCTAssertLessThanOrEqual(panel.frame.maxY, app.frame.maxY + 1, id)
                if ["format", "color", "mode"].contains(id), orientation == .landscapeLeft {
                    XCTAssertEqual(panel.frame.minY, app.frame.minY, accuracy: 1, id)
                } else {
                    XCTAssertGreaterThan(panel.frame.minY, app.frame.minY, id)
                }
                XCTAssertTrue(app.buttons["monitor.system.record"].isHittable, id)
                XCTAssertTrue(app.buttons["monitor.system.display"].isHittable, id)
                XCTAssertFalse(app.buttons["monitor.system.zoom"].isHittable, id)
                if orientation == .landscapeLeft {
                    XCTAssertFalse(app.buttons["monitor.system.settings"].isHittable, id)
                    XCTAssertFalse(app.buttons["monitor.system.media"].isHittable, id)
                }
                capture("capture-\(id)-\(orientation.rawValue)")
                app.buttons["Close"].firstMatch.tap()
                XCTAssertFalse(panel.exists)
            }
        }
    }

    func testTopPickerKeepsLowerReadoutsInteractiveAndCanBeReplaced() {
        app.launch()
        for orientation in [UIDeviceOrientation.landscapeLeft, .landscapeRight] {
            rotate(orientation)
            for id in ["format", "color", "mode"] {
                app.buttons["monitor.capture.\(id)"].tap()
                let panel = app.descendants(matching: .any)["monitor.capture.panel"].firstMatch
                XCTAssertTrue(panel.waitForExistence(timeout: 5), id)
                XCTAssertEqual(panel.frame.minY, app.frame.minY, accuracy: 1, id)
                let iso = app.buttons["monitor.capture.iso"]
                XCTAssertTrue(iso.isHittable, id)
                iso.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                let replacement = NSPredicate { _, _ in
                    panel.exists && panel.frame.minY > self.app.frame.minY
                }
                expectation(for: replacement, evaluatedWith: app)
                waitForExpectations(timeout: 3)
                // Full ISO details can extend above the midpoint on short
                // landscape screens; the reference anchors its bottom edge.
                XCTAssertGreaterThan(panel.frame.minY, app.frame.minY, id)
                XCTAssertEqual(panel.frame.maxY, app.frame.maxY, accuracy: 1, id)
                XCTAssertEqual(app.buttons.matching(identifier: "monitor.capture.close").count, 1)
                app.buttons["monitor.capture.close"].tap()
                XCTAssertFalse(panel.exists)
            }
        }
    }

    func testTopReadoutPaddingOpensThePickerWithoutMovingItsLabel() {
        app.launch()
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft, .landscapeRight] {
            rotate(orientation)
            let controls = orientation == .portrait ? ["format"] : ["format", "color", "mode"]
            for id in controls {
                let readout = app.buttons["monitor.capture.\(id)"]
                XCTAssertTrue(readout.isHittable, id)
                let center = readout.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                center.withOffset(CGVector(dx: 0, dy: 18)).tap()
                let panel = app.descendants(matching: .any)["monitor.capture.panel"].firstMatch
                XCTAssertTrue(panel.waitForExistence(timeout: 5), "Padding tap: \(id)")
                app.buttons["monitor.capture.close"].tap()
                XCTAssertFalse(panel.exists)
            }
        }
    }

    /// A Luna body reports no camera audio: neither the AUDIO readout nor the audio meter tool is
    /// offered (Pocket, whose bodies record audio, keeps the meter test).
    func testCameraWithoutAudioOffersNoAudioReadoutOrMeter() {
        app.launch()
        rotate(.landscapeLeft)
        XCTAssertTrue(app.buttons["monitor.capture.iso"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["monitor.capture.audio"].exists)
        app.buttons["monitor.assists.expand"].tap()
        XCTAssertTrue(app.buttons["monitor.assist.PEAK"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["monitor.assist.AUDIO"].exists)
        capture("no-camera-audio")
    }

    func testFalseColorReferenceStartsCenteredAndCanBePlaced() {
        app.launch()
        rotate(.landscapeLeft)
        app.buttons["monitor.assists.expand"].tap()
        app.buttons["monitor.assist.FALSE"].tap()
        app.buttons["Collapse View Assist tools"].tap()
        let key = app.descendants(matching: .any)["monitor.falseColor.reference"].firstMatch
        XCTAssertTrue(key.waitForExistence(timeout: 5))
        XCTAssertEqual(key.frame.midX, app.frame.midX, accuracy: 1)
        XCTAssertEqual(key.frame.midY, app.frame.midY, accuracy: 1)
        let original = key.frame
        capture("false-color-reference-centered")
        let start = key.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 50, dy: -60)))
        XCTAssertGreaterThan(key.frame.midX, original.midX + 30)
        XCTAssertLessThan(key.frame.midY, original.midY - 40)
        capture("false-color-reference-placed")
    }

    func testActualOwnedVideoPlaybackBorrowsOneGalleryThroughTransportCoversAndRotation() throws {
        for key in ["OPV_SIM_FEED_CLIP", "OPV_SIM_FEED_CLIP_B", "OPV_SIM_FEED_MANIFEST", "OPV_UI_REVIEW_PLAYBACK_FACTS"] {
            XCTAssertNotNil(app.launchEnvironment[key], "Actual decoded-video input is required: \(key)")
        }
        // The decoded-video inputs ride on a connected camera's media source (`ReviewMediaService`).
        app.launchEnvironment.merge(ReviewLaunch(screen: .media, source: .camera, connected: true).environment) { $1 }
        app.launch()
        let factsElement = app.descendants(matching: .any)["monitor.review.playback.facts"].firstMatch
        XCTAssertTrue(factsElement.waitForExistence(timeout: 10))
        let factsURL = URL(fileURLWithPath: try XCTUnwrap(app.launchEnvironment["OPV_UI_REVIEW_PLAYBACK_FACTS"]))
        var lastSequence = 0
        func facts() -> [String: Any] {
            guard let data = try? Data(contentsOf: factsURL),
                let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let sequence = (value["sequence"] as? NSNumber)?.intValue, sequence >= lastSequence,
                let stamp = (value["monotonic"] as? NSNumber)?.doubleValue,
                stamp.isFinite, ProcessInfo.processInfo.systemUptime - stamp >= -0.1,
                ProcessInfo.processInfo.systemUptime - stamp < 1, value["matched"] as? Bool == true else { return [:] }
            if value["item"] as? String != nil,
                (value["host"] as? String == nil || value["player"] as? String == nil || value["mounted"] as? Bool != true) { return [:] }
            lastSequence = sequence
            return value
        }
        @discardableResult func awaitFacts(_ message: String, _ condition: @escaping ([String: Any]) -> Bool) -> [String: Any] {
            let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition(facts()) }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed, "\(message): \(facts())")
            return facts()
        }
        func number(_ value: [String: Any], _ key: String) -> Double { (value[key] as? NSNumber)?.doubleValue ?? .nan }
        func displayedRaster(_ screenshot: XCUIScreenshot) -> (width: Int, height: Int)? {
            guard let image = screenshot.image.cgImage else { return nil }
            switch screenshot.image.imageOrientation {
            case .up, .down, .upMirrored, .downMirrored:
                return (image.width, image.height)
            case .left, .right, .leftMirrored, .rightMirrored:
                return (image.height, image.width)
            @unknown default:
                return nil
            }
        }
        func assertPattern(_ name: String, requestedOrientation: UIDeviceOrientation = .portrait) throws {
            var accepted: XCUIScreenshot?
            var last: XCUIScreenshot?
            var observation = "No native pixels observed"
            let rendered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                if accepted != nil { return true }
                let screenshot = XCUIScreen.main.screenshot(); last = screenshot
                let applicationFrame = self.app.frame
                observation = "request=\(requestedOrientation.rawValue) AXframe=\(applicationFrame) raster=unknown"
                guard let image = screenshot.image.cgImage else { return false }
                let width = image.width, height = image.height
                let imageOrientation = screenshot.image.imageOrientation.rawValue
                observation = "request=\(requestedOrientation.rawValue) AXframe=\(applicationFrame) rawCG=\(width)x\(height) UIImageOrientation=\(imageOrientation) displayedRaster=unknown"
                guard let raster = displayedRaster(screenshot) else { return false }
                observation = "request=\(requestedOrientation.rawValue) AXframe=\(applicationFrame) rawCG=\(width)x\(height) UIImageOrientation=\(imageOrientation) displayedRaster=\(raster.width)x\(raster.height) pixels=unobserved"
                guard (raster.width > raster.height) == requestedOrientation.isLandscape else { return false }
                var pixels = [UInt8](repeating: 0, count: width * height * 4)
                let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
                    guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                        bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                    context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))); return true
                }
                guard drawn else { return false }
                var matched = 0
                for y in stride(from: 0, to: height, by: 8) {
                    for x in stride(from: 0, to: width, by: 8) {
                        let offset = (y * width + x) * 4
                        let r = pixels[offset], g = pixels[offset + 1], blue = pixels[offset + 2]
                        if name == "A" ? (r < 60 && g > 90 && blue < 65) : (r < 60 && g < 70 && blue > 130) { matched += 1 }
                    }
                }
                observation = "request=\(requestedOrientation.rawValue) AXframe=\(applicationFrame) rawCG=\(width)x\(height) UIImageOrientation=\(imageOrientation) displayedRaster=\(raster.width)x\(raster.height) pattern=\(name) matched=\(matched) minimum=\(width * height / 64 / 10)"
                if matched > width * height / 64 / 10 { accepted = screenshot; return true }
                return false
            }, object: nil)
            let result = XCTWaiter.wait(for: [rendered], timeout: 10)
            if result != .completed, let last {
                let failure = XCTAttachment(screenshot: last); failure.name = "UNACCEPTED-\(observation)"
                failure.lifetime = .keepAlways; add(failure)
            }
            XCTAssertEqual(result, .completed, "Actual decoded picture: \(observation)")
            let acceptedScreenshot = try XCTUnwrap(accepted)
            let acceptedRaster = try XCTUnwrap(displayedRaster(acceptedScreenshot))
            let attachment = XCTAttachment(screenshot: acceptedScreenshot)
            attachment.name = "SIMULATED-actual-player-\(name)-\(acceptedRaster.width > acceptedRaster.height ? "landscape" : "portrait")"
            attachment.lifetime = .keepAlways; add(attachment)
            let native = XCTAttachment(string: String(data: try Data(contentsOf: factsURL), encoding: .utf8) ?? "Missing native facts")
            native.lifetime = .keepAlways; add(native)
        }
        let first = "VID_20261003_140002_00_002.MP4"
        let second = "VID_20261003_140001_00_001.MP4"
        XCTAssertTrue(app.staticTexts[first].waitForExistence(timeout: 10))
        let gallery = awaitFacts("Actual gallery opens once") { $0["browsing"] as? Bool == true && number($0, "opens") == 1 && $0["bound"] as? Bool == true }
        XCTAssertEqual(gallery["galleryOrder"] as? [String], [first, second], "Actual displayed video order must put A before its Next B")
        let library = try XCTUnwrap(gallery["library"] as? String), lifetime = try XCTUnwrap(gallery["lifetime"] as? String)
        let monitor = try XCTUnwrap(gallery["monitor"] as? String)
        XCTAssertEqual(gallery["route"] as? String, "monitor")
        func assertBorrowed(_ value: [String: Any]) {
            XCTAssertEqual(value["monitor"] as? String, monitor); XCTAssertEqual(value["route"] as? String, "monitor")
            XCTAssertEqual(value["library"] as? String, library); XCTAssertEqual(value["lifetime"] as? String, lifetime)
            XCTAssertEqual(number(value, "opens"), 1); XCTAssertEqual(number(value, "closes"), 0)
            XCTAssertEqual(value["browsing"] as? Bool, true); XCTAssertEqual(value["cover"] as? String, "media")
        }
        app.staticTexts[first].tap()
        let opened = awaitFacts("A reaches actual native display") {
            $0["ready"] as? Bool == true && ($0["file"] as? String)?.contains("LRV_20261003_140002") == true &&
                abs(number($0, "duration") - 12) < 0.1 && number($0, "width") == 640 && number($0, "height") == 360
        }
        let host = try XCTUnwrap(opened["host"] as? String), player = try XCTUnwrap(opened["player"] as? String)
        let item = try XCTUnwrap(opened["item"] as? String)
        assertBorrowed(opened); try assertPattern("A", requestedOrientation: .portrait)
        app.buttons["Loop playback"].tap()
        XCTAssertEqual(app.buttons["Loop playback"].value as? String, "On")
        app.buttons["Pause"].tap()
        awaitFacts("Native transport pauses") { number($0, "rate") == 0 }
        let rail = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Playback position")).firstMatch
        XCTAssertTrue(rail.waitForExistence(timeout: 5)); XCTAssertGreaterThan(rail.frame.width, 100)
        func scrub(_ fraction: CGFloat) {
            let start = rail.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
            start.press(forDuration: 0.1, thenDragTo: rail.coordinate(withNormalizedOffset: CGVector(dx: fraction, dy: 0.5)))
        }
        scrub(0.25)
        awaitFacts("Paused native seek reaches interior time") { abs(number($0, "time") - 3) < 0.5 && number($0, "rate") == 0 }
        let pausedAdvance = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let observed = facts()
            let time = number(observed, "time"), rate = number(observed, "rate")
            return observed.isEmpty || observed["item"] as? String != item ||
                observed["host"] as? String != host || observed["player"] as? String != player ||
                !time.isFinite || !rate.isFinite || rate != 0 || abs(time - 3) > 0.5
        }, object: nil)
        pausedAdvance.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [pausedAdvance], timeout: 1), .completed)
        app.buttons["Play"].tap()
        awaitFacts("Native transport resumes") { number($0, "rate") > 0 && number($0, "time") > 3.5 }
        scrub(0.5)
        awaitFacts("Playing scrub resumes after final native seek") { number($0, "time") >= 5.5 && number($0, "time") < 8 && number($0, "rate") > 0 }
        app.buttons["Clip information"].tap(); XCTAssertTrue(app.buttons["Close clip information"].waitForExistence(timeout: 5))
        assertBorrowed(facts()); app.buttons["Close clip information"].tap()
        app.buttons["Share clip"].tap(); XCTAssertTrue(app.staticTexts["Frame.io"].firstMatch.waitForExistence(timeout: 5))
        awaitFacts("Actual Share pauses native playback") { number($0, "rate") == 0 }
        app.buttons["Close"].firstMatch.tap()
        let returned = awaitFacts("Share return retains paused item") { number($0, "rate") == 0 && $0["item"] as? String == item }
        assertBorrowed(returned)
        for orientation in [UIDeviceOrientation.landscapeLeft, .landscapeRight, .portrait] {
            rotate(orientation)
            let rotated = awaitFacts("Same native host survives actual rotation") { $0["ready"] as? Bool == true && $0["item"] as? String == item }
            XCTAssertEqual(rotated["host"] as? String, host); XCTAssertEqual(rotated["player"] as? String, player)
            assertBorrowed(rotated); try assertPattern("A", requestedOrientation: orientation)
        }
        app.buttons["Next clip"].tap()
        let next = awaitFacts("B replaces the native item with actual original bytes") {
            $0["ready"] as? Bool == true && ($0["file"] as? String)?.contains("VID_20261003_140001") == true
        }
        let nextItem = try XCTUnwrap(next["item"] as? String)
        assertBorrowed(next); try assertPattern("B", requestedOrientation: .portrait)
        if app.buttons["Loop playback"].value as? String != "On" { app.buttons["Loop playback"].tap() }
        if app.buttons["Pause"].exists { app.buttons["Pause"].tap() }
        awaitFacts("B pauses before end seek") { number($0, "rate") == 0 }
        scrub(0.95)
        awaitFacts("Real B seek reaches end region") { number($0, "time") > 10.8 && number($0, "rate") == 0 }
        app.buttons["Play"].tap()
        awaitFacts("Loop restarts same native B item") { number($0, "time") < 2 && number($0, "rate") > 0 && $0["item"] as? String == nextItem }
        app.buttons["Back to media"].tap()
        XCTAssertTrue(app.staticTexts[second].waitForExistence(timeout: 5))
        let back = awaitFacts("Returning player retires native item while retaining browse") {
            $0["item"] as? String == nil && ($0["retiredItems"] as? [String])?.contains(nextItem) == true
        }
        assertBorrowed(back)
        app.buttons["Back"].firstMatch.tap()
        let closed = awaitFacts("Outer native Back closes one browse") {
            $0["browsing"] as? Bool == false && $0["bound"] as? Bool == false && number($0, "closes") == 1
        }
        XCTAssertEqual(number(closed, "opens"), 1); XCTAssertNil(closed["item"] as? String)
        let returnedToLive = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let current = facts()
            guard current["monitor"] as? String == monitor, current["route"] as? String == "monitor",
                current["cover"] is NSNull else { return false }
            let picture = self.app.descendants(matching: .any)["monitor.native.picture"].firstMatch
            guard picture.exists else { return false }
            let frame = picture.frame
            return [frame.minX, frame.minY, frame.width, frame.height].allSatisfy { $0.isFinite } &&
                frame.width > 0 && frame.height > 0 && !frame.intersection(self.app.frame).isEmpty &&
                self.app.buttons["monitor.system.media"].isHittable && !self.app.buttons["cameras.pair"].exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [returnedToLive], timeout: 5), .completed,
            "Connected media Back returns to the same live monitor")
    }

    func testActualMediaLibraryFavoritesSelectionAndPhotoCoverSurviveRotation() {
        app.launchEnvironment.merge(ReviewLaunch(screen: .media).environment) { $1 }
        app.launchEnvironment["OPV_UI_REVIEW_MEDIA_PHOTOS"] = "1"
        app.launch()
        let first = "IMG_20261003_140001_00_001.JPG"
        let second = "IMG_20261003_140002_00_002.JPG"
        XCTAssertTrue(app.staticTexts[first].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[second].exists)
        app.buttons["Add favorite"].firstMatch.tap()
        app.buttons["Show Favorites media"].tap()
        XCTAssertTrue(app.buttons["Remove favorite"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Show All media"].tap()
        app.buttons["List view"].tap()
        let row = app.staticTexts[first]
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.5)
        XCTAssertTrue(app.staticTexts["1 selected"].waitForExistence(timeout: 5))
        rotate(.landscapeLeft)
        XCTAssertTrue(app.staticTexts["1 selected"].exists)
        XCTAssertTrue(app.buttons["Remove favorite"].firstMatch.exists)
        capture("SIMULATED-actual-owned-gallery-landscape-selection")
        app.buttons["Clear selection"].tap()
        app.staticTexts[first].tap()
        let close = app.buttons["Back to media"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        rotate(.portrait)
        close.tap()
        XCTAssertTrue(app.staticTexts[first].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Remove favorite"].firstMatch.exists)
        capture("SIMULATED-actual-owned-gallery-returned-photo")
    }

    func testMediaPageAdaptsToOrientation() {
        launch(ReviewLaunch(screen: .media))
        let navigation = app.otherElements["monitor.page.navigation"]
        XCTAssertTrue(navigation.waitForExistence(timeout: 10))
        rotate(.portrait)
        XCTAssertGreaterThan(navigation.frame.width, navigation.frame.height)
        rotate(.landscapeLeft)
        capture("media-rotation-regression")
        XCTAssertLessThan(
            navigation.frame.width, navigation.frame.height,
            "Landscape media must use its full-height navigation column")
        XCTAssertLessThan(
            navigation.frame.maxX, app.frame.midX,
            "Landscape navigation must leave room for the media detail")
    }

    func testBackButtonsStayOutsideFullHeightSidebarsAndMediaLayoutTogglesInPlace() {
        app.launch()
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            rotate(orientation)
            for (control, backLabel) in [("settings", "Back to live"), ("media", "Back")] {
                let systemButtonFrame = app.buttons["monitor.system.settings"].frame
                app.buttons["monitor.system.\(control)"].tap()
                let back = app.buttons[backLabel].firstMatch
                XCTAssertTrue(back.waitForExistence(timeout: 5))
                let heading = app.otherElements["monitor.page.heading"]
                let navigation = app.otherElements["monitor.page.navigation"]
                XCTAssertTrue(navigation.frame.contains(heading.frame))
                XCTAssertEqual(back.frame.width, systemButtonFrame.width, accuracy: 1)
                XCTAssertEqual(back.frame.height, systemButtonFrame.height, accuracy: 1)
                if orientation == .portrait {
                    XCTAssertTrue(navigation.frame.contains(back.frame))
                    XCTAssertLessThan(back.frame.maxX, heading.frame.minX)
                } else {
                    XCTAssertLessThan(back.frame.maxX, navigation.frame.minX)
                    XCTAssertEqual(back.frame.minY, systemButtonFrame.minY, accuracy: 1)
                    XCTAssertGreaterThan(navigation.frame.height, app.frame.height * 0.8)
                }
                XCTAssertTrue(back.isHittable)
                if control == "media" {
                    let displayControls = app.otherElements["monitor.media.displayControls"]
                    if orientation == .portrait {
                        XCTAssertGreaterThan(displayControls.frame.minY, app.frame.height * 0.8)
                        XCTAssertGreaterThan(displayControls.frame.minY, navigation.frame.maxY)
                    } else {
                        XCTAssertTrue(navigation.frame.contains(displayControls.frame))
                        XCTAssertEqual(
                            displayControls.frame.maxY, navigation.frame.maxY - 10, accuracy: 1)
                    }
                    XCTAssertFalse(app.buttons["Refresh camera media"].exists)
                    let filter = app.buttons["monitor.media.filter"]
                    let sort = app.buttons["Sort"]
                    XCTAssertTrue(filter.isHittable)
                    XCTAssertTrue(sort.isHittable)
                    XCTAssertEqual(filter.frame.height, sort.frame.height, accuracy: 1)
                    XCTAssertEqual(filter.frame.midY, sort.frame.midY, accuracy: 1)
                    filter.tap()
                    let popup = app.otherElements["monitor.media.filter.popup"]
                    XCTAssertTrue(popup.waitForExistence(timeout: 2))
                    XCTAssertGreaterThanOrEqual(popup.frame.minX, -0.5)
                    XCTAssertGreaterThanOrEqual(popup.frame.minY, -0.5)
                    XCTAssertLessThanOrEqual(popup.frame.maxX, app.frame.width + 0.5)
                    XCTAssertLessThanOrEqual(popup.frame.maxY, app.frame.height + 0.5)
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
                    XCTAssertTrue(popup.waitForNonExistence(timeout: 2))
                    let grid = app.buttons["monitor.media.layout.grid"]
                    let list = app.buttons["monitor.media.layout.list"]
                    XCTAssertTrue(grid.isHittable)
                    XCTAssertTrue(list.isHittable)
                    XCTAssertEqual(grid.frame.midY, list.frame.midY, accuracy: 1)
                    XCTAssertEqual(grid.frame.width, 32, accuracy: 1)
                    XCTAssertEqual(grid.frame.height, 28, accuracy: 1)
                    XCTAssertEqual(displayControls.frame.width, 172, accuracy: 2)
                    XCTAssertEqual(displayControls.frame.height, 34, accuracy: 2)
                    for size in ["Small", "Medium", "Large"] {
                        let button = app.buttons["\(size) thumbnails"]
                        XCTAssertTrue(button.isHittable)
                        XCTAssertTrue(displayControls.frame.contains(button.frame))
                        XCTAssertEqual(button.frame.midY, grid.frame.midY, accuracy: 1)
                        XCTAssertEqual(button.frame.width, 28, accuracy: 1)
                        XCTAssertEqual(button.frame.height, 28, accuracy: 1)
                    }
                    let originalGrid = grid.frame
                    XCTAssertTrue(
                        (grid.value as? String)?.contains("Selected") == true
                            || grid.isSelected)
                    list.tap()
                    XCTAssertTrue(
                        list.isSelected || (list.value as? String)?.contains("Selected") == true)
                    XCTAssertEqual(grid.frame.minX, originalGrid.minX, accuracy: 1)
                    XCTAssertEqual(grid.frame.width, originalGrid.width, accuracy: 1)
                    grid.tap()
                    XCTAssertTrue(
                        grid.isSelected || (grid.value as? String)?.contains("Selected") == true)
                }
                capture("\(control)-page-header-\(orientation.rawValue)")
                back.tap()
                XCTAssertTrue(app.buttons["monitor.system.record"].isHittable)
            }
        }
    }

    func testPopulatedMediaLayoutsAndPlayback() {
        let reviews = [
            ("media-grid", ReviewLaunch(screen: .media, mediaCount: 12)),
            ("media-list", ReviewLaunch(screen: .media, layout: .list, mediaCount: 12)),
            ("media-selection", ReviewLaunch(screen: .media, mediaCount: 12)),
            ("playback", ReviewLaunch(screen: .playback, mediaCount: 12)),
        ]
        for (name, review) in reviews {
            launch(review)
            let expected =
                review.screen == .playback
                ? app.buttons["Back to media"] : app.staticTexts["Media"].firstMatch
            XCTAssertTrue(expected.waitForExistence(timeout: 10))
            if name == "media-selection" {
                XCTAssertTrue(app.staticTexts[Self.clip(1)].waitForExistence(timeout: 10))
                mediaClipCenter(Self.clip(1)).press(
                    forDuration: 0.4, thenDragTo: mediaClipCenter(Self.clip(3)), withVelocity: .slow,
                    thenHoldForDuration: 0)
                XCTAssertTrue(app.staticTexts["3 selected"].waitForExistence(timeout: 5))
            }
            capture(name + "-portrait")
            rotate(.landscapeLeft)
            capture(name + "-landscape")
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
    }

    func testMediaDragSelectionEntersFromHoldAndDeselectsFromSelectedClip() {
        for layout in [MonitorMediaLayout.grid, .list] {
            launch(ReviewLaunch(screen: .media, layout: layout, mediaCount: 12))
            XCTAssertTrue(app.staticTexts[Self.clip(1)].waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["Select \(Self.clip(1))"].exists)
            let first = mediaClipCenter(Self.clip(1))
            let fourth = mediaClipCenter(Self.clip(4))
            first.press(
                forDuration: 0.4, thenDragTo: fourth, withVelocity: .slow, thenHoldForDuration: 0)
            XCTAssertTrue(app.staticTexts["4 selected"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Deselect \(Self.clip(1))"].exists)
            capture("media-drag-selected")
            first.press(
                forDuration: 0.4, thenDragTo: fourth, withVelocity: .slow, thenHoldForDuration: 0)
            XCTAssertTrue(app.staticTexts["0 selected"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Clear selection"].exists)
            XCTAssertFalse(app.buttons["Back to media"].exists)
            app.buttons["Clear selection"].tap()
            XCTAssertFalse(app.buttons["Select \(Self.clip(1))"].exists)
            app.terminate()
        }
    }

    func testMediaDragSelectionAutoScrollsAtBothEdgesAndStopsOnRelease() {
        launch(ReviewLaunch(screen: .media, mediaCount: 12))
        XCTAssertTrue(app.staticTexts[Self.clip(1)].waitForExistence(timeout: 10))
        app.buttons["Large thumbnails"].tap()
        let gallery = app.scrollViews["monitor.media.gallery"]
        let first = app.staticTexts[Self.clip(1)].coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: -2))
        let bottom = gallery.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1)).withOffset(
            CGVector(dx: 0, dy: -10))
        first.press(
            forDuration: 0.4, thenDragTo: bottom, withVelocity: .fast, thenHoldForDuration: 6)
        XCTAssertTrue(app.buttons["Deselect \(Self.clip(12))"].isHittable)
        XCTAssertTrue(app.staticTexts["12 selected"].exists)
        let last = app.buttons["Deselect \(Self.clip(12))"]
        let stoppedFrame = last.frame
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(last.frame.minY, stoppedFrame.minY, accuracy: 1)
        let top = gallery.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(
            CGVector(dx: 0, dy: 5))
        mediaClipCenter(Self.clip(12)).press(
            forDuration: 0.4, thenDragTo: top, withVelocity: .fast, thenHoldForDuration: 6)
        XCTAssertTrue(app.staticTexts["0 selected"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Select \(Self.clip(1))"].isHittable)
        capture("media-drag-returned-to-top")
    }

    func testMediaDragSelectionPreservesNativeScrollingAndSidewaysRange() {
        for layout in [MonitorMediaLayout.grid, .list] {
            launch(ReviewLaunch(screen: .media, layout: layout, mediaCount: 12))
            XCTAssertTrue(app.staticTexts[Self.clip(1)].waitForExistence(timeout: 10))
            let gallery = app.scrollViews["monitor.media.gallery"]
            XCTAssertTrue(gallery.waitForExistence(timeout: 5))
            mediaClipCenter(Self.clip(1)).press(
                forDuration: 0.4, thenDragTo: mediaClipCenter(Self.clip(2)),
                withVelocity: .slow,
                thenHoldForDuration: 0)
            XCTAssertTrue(app.staticTexts["2 selected"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Clear selection"].exists)

            if layout == .list {
                mediaClipCenter(Self.clip(3)).press(
                    forDuration: 0.05,
                    thenDragTo: mediaClipCenter(Self.clip(3)).withOffset(
                        CGVector(dx: 80, dy: 4)),
                    withVelocity: .slow, thenHoldForDuration: 0)
                XCTAssertTrue(app.staticTexts["3 selected"].waitForExistence(timeout: 5))
            } else {
                mediaClipCenter(Self.clip(3)).press(
                    forDuration: 0.05, thenDragTo: mediaClipCenter(Self.clip(4)),
                    withVelocity: .slow, thenHoldForDuration: 0)
                XCTAssertTrue(app.staticTexts["4 selected"].waitForExistence(timeout: 5))
            }
            let selected = layout == .list ? "3 selected" : "4 selected"
            let before = visibleReviewClips()
            gallery.swipeUp(velocity: .fast)
            var after = visibleReviewClips()
            if after == before {
                gallery.swipeUp(velocity: .fast)
                after = visibleReviewClips()
            }
            XCTAssertTrue(app.staticTexts[selected].exists)
            XCTAssertTrue(app.buttons["Clear selection"].exists)
            XCTAssertFalse(app.buttons["Back to media"].exists)
            XCTAssertNotEqual(
                before, after, "\(layout) must scroll natively while selection stays active")
            gallery.swipeDown(velocity: .fast)
            XCTAssertTrue(app.staticTexts[Self.clip(1)].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts[selected].exists)

            let origin = mediaClipCenter(Self.clip(1))
            origin.press(
                forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: 4, dy: 220)),
                withVelocity: .fast, thenHoldForDuration: 0)
            XCTAssertTrue(app.staticTexts[selected].exists)
            XCTAssertFalse(app.buttons["Back to media"].exists)

            origin.press(
                forDuration: 0.4, thenDragTo: mediaClipCenter(Self.clip(4)),
                withVelocity: .slow,
                thenHoldForDuration: 0)
            XCTAssertTrue(app.staticTexts["0 selected"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Clear selection"].exists)
            app.buttons["Clear selection"].tap()
            XCTAssertFalse(app.buttons["Select \(Self.clip(1))"].exists)
            app.terminate()
        }
    }

    func testHomePairAndOperatorPages() {
        let expected: [(ReviewLaunch.Screen, String)] = [
            (.cameras, "Your cameras"), (.pair, "Find your camera"), (.settings, "Operator Setup"),
            (.media, "Media"),
        ]
        for (screen, title) in expected {
            launch(ReviewLaunch(screen: screen))
            XCTAssertTrue(app.staticTexts[title].firstMatch.waitForExistence(timeout: 10))
            if screen == .pair {
                XCTAssertTrue(
                    // Insta's own pre-check (StartupChrome), on main too; the DJI line was Pocket's.
                    app.staticTexts["Before pairing, force quit the Insta360 app."].firstMatch.exists)
            }
            capture(screen.rawValue + "-portrait")
            rotate(.landscapeLeft)
            capture(screen.rawValue + "-landscape")
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
    }

    func testAllOperatorTabsRetainSelectionAcrossRotation() {
        app.launchEnvironment.merge(ReviewLaunch(screen: .settings).environment) { $1 }
        app.launch()
        let tabs = app.scrollViews["monitor.settings.tabs"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        let sections = [
            ("Link", "Connection state and link behavior."),
            ("Sharing", "Share this feed with OpenInstaCine devices on the same camera Wi-Fi."),
            ("View Assist", "Behavior for live-view tools."),
            ("Controls", "Touch behavior and safety."),
            ("Display", "Live view buttons and chrome."),
            ("Storage", "Local cache and integrations."),
            ("System", "App-level behavior."),
        ]
        for (title, subtitle) in sections {
            let tab = app.buttons["monitor.settings.tab.\(title)"]
            reveal(tab, in: tabs, portrait: true)
            XCTAssertTrue(tab.isHittable, "\(title) must be reachable in the scrolling tab rail")
            tab.tap()
            XCTAssertTrue(app.staticTexts[subtitle].waitForExistence(timeout: 5))
            capture(
                "settings-\(title.lowercased().replacingOccurrences(of: " ", with: "-"))-portrait")
        }
        rotate(.landscapeLeft)
        XCTAssertTrue(app.staticTexts["App-level behavior."].exists)
        for (title, subtitle) in sections {
            let tab = app.buttons["monitor.settings.tab.\(title)"]
            reveal(tab, in: tabs, portrait: false)
            XCTAssertTrue(tab.isHittable)
            tab.tap()
            XCTAssertTrue(app.staticTexts[subtitle].waitForExistence(timeout: 5))
            capture(
                "settings-\(title.lowercased().replacingOccurrences(of: " ", with: "-"))-landscape")
        }
    }

    func testCommonDisplayControlsKeepLiveAndCleanIndependentAfterRelaunch() throws {
        app.launchEnvironment.merge(ReviewLaunch(screen: .settings).environment) { $1 }
        app.launch()
        func openDisplay() {
            let tabs = app.scrollViews["monitor.settings.tabs"]
            XCTAssertTrue(tabs.waitForExistence(timeout: 10))
            let tab = app.buttons["monitor.settings.tab.Display"]
            reveal(tab, in: tabs, portrait: true)
            tab.tap()
        }
        func control(_ mode: String) -> XCUIElement {
            let button = app.buttons["monitor.settings.display.toggle.\(mode).Status Bar"]
            for _ in 0..<12 where !button.isHittable { app.swipeUp() }
            XCTAssertTrue(button.isHittable, "The actual common visibility switch must be reachable: \(app.debugDescription)")
            return button
        }
        openDisplay()
        let live = control("live")
        let originalLive = try XCTUnwrap(live.value as? String)
        XCTAssertTrue(["On", "Off"].contains(originalLive))
        live.tap()
        let changedLive = originalLive == "On" ? "Off" : "On"
        XCTAssertEqual(live.value as? String, changedLive)
        let clean = control("clean")
        let originalClean = try XCTUnwrap(clean.value as? String)
        XCTAssertTrue(["On", "Off"].contains(originalClean))
        clean.tap()
        let changedClean = originalClean == "On" ? "Off" : "On"
        XCTAssertEqual(clean.value as? String, changedClean)
        // main offers every clean view pin, AUDIO included, whatever the camera declares.
        let audioPin = app.buttons["monitor.settings.display.toggle.clean.pin.AUDIO"]
        for _ in 0..<12 where !audioPin.isHittable { app.swipeUp() }
        XCTAssertTrue(audioPin.isHittable, "Clean view offers the AUDIO pin")
        capture("SIMULATED-common-display-clean-controls")
        app.terminate()
        app.launch()
        openDisplay()
        let restoredLive = control("live")
        XCTAssertEqual(restoredLive.value as? String, changedLive)
        restoredLive.tap()
        XCTAssertEqual(restoredLive.value as? String, originalLive)
        let restoredClean = control("clean")
        XCTAssertEqual(restoredClean.value as? String, changedClean,
            "Restoring Live must preserve the independent Clean layout")
        restoredClean.tap()
        XCTAssertEqual(restoredClean.value as? String, originalClean)
        rotate(.landscapeLeft)
        capture("SIMULATED-common-display-restored-landscape")
    }

    func testCommonSharingChoicesPersistWithoutStartingTheRelay() throws {
        app.launchEnvironment.merge(ReviewLaunch(screen: .settings).environment) { $1 }
        app.launch()
        func openSharing() {
            let tabs = app.scrollViews["monitor.settings.tabs"]
            XCTAssertTrue(tabs.waitForExistence(timeout: 10))
            let tab = app.buttons["monitor.settings.tab.Sharing"]
            reveal(tab, in: tabs, portrait: true)
            tab.tap()
        }
        func revealChoice(_ button: XCUIElement) {
            for _ in 0..<8 where !button.isHittable { app.swipeUp() }
            XCTAssertTrue(button.isHittable)
        }
        openSharing()
        let requests = app.buttons["Control requests"]
        revealChoice(requests)
        let originalRequests = try XCTUnwrap(requests.value as? String)
        XCTAssertTrue(["On", "Off"].contains(originalRequests))
        requests.tap()
        let changedRequests = originalRequests == "On" ? "Off" : "On"
        XCTAssertEqual(requests.value as? String, changedRequests)
        let priorities = ["Quality", "High", "Medium", "Steady"]
        revealChoice(app.buttons["Steady"])
        let originalPriority = try XCTUnwrap(priorities.first { app.buttons[$0].isSelected })
        let changedPriority = originalPriority == "Steady" ? "Quality" : "Steady"
        app.buttons[changedPriority].tap()
        XCTAssertTrue(app.buttons[changedPriority].isSelected)
        capture("SIMULATED-common-sharing-choices")
        app.terminate()
        app.launch()
        openSharing()
        let restoredRequests = app.buttons["Control requests"]
        revealChoice(restoredRequests)
        XCTAssertEqual(restoredRequests.value as? String, changedRequests)
        restoredRequests.tap()
        XCTAssertEqual(restoredRequests.value as? String, originalRequests)
        revealChoice(app.buttons["Steady"])
        XCTAssertTrue(app.buttons[changedPriority].isSelected)
        app.buttons[originalPriority].tap()
        XCTAssertTrue(app.buttons[originalPriority].isSelected)
    }

    func testCommonCachePreferenceSurvivesRelaunchAndClearCanBeCancelled() throws {
        app.launchEnvironment.merge(ReviewLaunch(screen: .settings).environment) { $1 }
        app.launch()
        func openStorage() {
            let tabs = app.scrollViews["monitor.settings.tabs"]
            XCTAssertTrue(tabs.waitForExistence(timeout: 10))
            let storage = app.buttons["monitor.settings.tab.Storage"]
            reveal(storage, in: tabs, portrait: true)
            storage.tap()
        }
        openStorage()
        let cache = app.buttons["Full Resolution Caching"]
        XCTAssertTrue(cache.waitForExistence(timeout: 5))
        let initial = try XCTUnwrap(cache.value as? String)
        XCTAssertTrue(["On", "Off"].contains(initial))
        cache.tap()
        let changed = initial == "On" ? "Off" : "On"
        XCTAssertEqual(cache.value as? String, changed)
        app.terminate()
        app.launch()
        openStorage()
        XCTAssertEqual(cache.value as? String, changed)
        app.buttons["Clear"].tap()
        XCTAssertTrue(app.sheets["Clear cache?"].waitForExistence(timeout: 5))
        if app.buttons["Cancel"].exists {
            app.buttons["Cancel"].tap()
        } else {
            // The adaptive popover offers dismissal outside its bounds.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).tap()
        }
        XCTAssertFalse(app.sheets["Clear cache?"].exists)
        XCTAssertEqual(cache.value as? String, changed)
        cache.tap()
        XCTAssertEqual(cache.value as? String, initial)
        capture("SIMULATED-settings-cache-reload-and-cancel")
    }

    func testPlaybackInfoLoopAndShareReturnToTheSamePlayer() {
        app.launchEnvironment.merge(ReviewLaunch(screen: .playback).environment) { $1 }
        app.launch()
        let info = app.buttons["Clip information"]
        XCTAssertTrue(info.waitForExistence(timeout: 10))
        info.tap()
        let closeInfo = app.buttons["Close clip information"]
        XCTAssertTrue(closeInfo.waitForExistence(timeout: 5))
        capture("playback-info-portrait")
        rotate(.landscapeLeft)
        XCTAssertTrue(closeInfo.isHittable)
        capture("playback-info-landscape")
        closeInfo.tap()
        let loop = app.buttons["Loop playback"]
        XCTAssertEqual(loop.value as? String, "Off")
        loop.tap()
        XCTAssertEqual(loop.value as? String, "On")
        app.buttons["Share clip"].tap()
        XCTAssertTrue(app.staticTexts["Frame.io"].firstMatch.waitForExistence(timeout: 5))
        capture("playback-share-landscape")
        app.buttons["Close"].firstMatch.tap()
        XCTAssertEqual(loop.value as? String, "On", "Dismissing Share must preserve player state")
        app.buttons["Hide playback controls"].tap()
        let restore = app.buttons["Show playback controls"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        restore.tap()
        XCTAssertTrue(info.isHittable)
        XCTAssertEqual(loop.value as? String, "On")
    }

    func testPlaybackChromeAndCameraHomeSafeAreas() {
        app.launchEnvironment.merge(ReviewLaunch(screen: .cameras).environment) { $1 }
        app.launch()
        for orientation in [UIDeviceOrientation.landscapeLeft, .landscapeRight] {
            rotate(orientation)
            let pair = app.buttons["cameras.pair"]
            XCTAssertTrue(pair.waitForExistence(timeout: 10))
            XCTAssertEqual(pair.frame.midX, app.frame.midX, accuracy: 2)
            capture("centered-cameras-\(orientation.rawValue)")
        }
        app.terminate()
        // Delete from the camera is offered for a connected camera clip, as Pocket checks it.
        app.launchEnvironment.merge(ReviewLaunch(screen: .playback, source: .camera, connected: true).environment) { $1 }
        app.launch()
        for orientation in [UIDeviceOrientation.landscapeLeft, .landscapeRight, .portrait] {
            rotate(orientation)
            let back = app.buttons["Back to media"]
            XCTAssertTrue(back.waitForExistence(timeout: 10))
            XCTAssertTrue(back.isHittable)
            // One system button size on phone and tablet (48 pt since #447).
            XCTAssertEqual(back.frame.width, MonitorSystemButtonMetrics.side(tablet: UIDevice.current.userInterfaceIdiom == .pad), accuracy: 1)
            for title in [
                "Favorite clip", "Clip information", "Share clip", "Delete clip from camera",
            ] {
                let button = app.buttons[title]
                XCTAssertTrue(button.isHittable, title)
                XCTAssertLessThanOrEqual(button.frame.maxX, app.frame.maxX - 12, title)
                XCTAssertGreaterThanOrEqual(button.frame.minX, 12, title)
            }
            capture("polished-playback-\(orientation.rawValue)")
        }
        rotate(.landscapeLeft)
        app.buttons["monitor.assists.expand"].tap()
        app.buttons["monitor.assist.LUT"].press(forDuration: 0.6)
        let inspector = app.otherElements["monitor.inspector"]
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        let lut = inspector.buttons["LUT"].firstMatch
        XCTAssertTrue(lut.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(lut.frame.minX, 55)
        capture("playback-assist-cutout-clearance")
        app.buttons["Close LUT"].tap()
        app.buttons["Share clip"].tap()
        let scroll = app.scrollViews["monitor.share.optionsScroll"]
        for name in [
            "Google Drive", "Dropbox", "NAS (SMB)", "LucidLink", "Backblaze B2", "Vimeo Review",
        ] {
            let row = app.descendants(matching: .any)["monitor.share.upcoming.\(name)"].firstMatch
            for _ in 0..<5 where !row.isHittable { scroll.swipeUp() }
            XCTAssertTrue(row.exists, name)
        }
        capture("share-upcoming-destinations")
    }

    /// #406: saved cameras show their setups. Luna joins only its own access point, so the
    /// camera page offers no Add setup (OsmoCameraPageAdapter sets canAddSetup false).
    func testSavedCameraSetupChipsAndAddSetupFlow() {
        app.launchEnvironment.merge(ReviewLaunch(screen: .cameras).environment) { $1 }
        app.launch()
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            rotate(orientation)
            let wifi = app.buttons["cameras.setup.wifi"]
            XCTAssertTrue(wifi.waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["cameras.setup.phoneHotspot"].exists)
            XCTAssertEqual(app.buttons.matching(identifier: "cameras.setup.cameraWiFi").count, 2)
            XCTAssertGreaterThanOrEqual(wifi.frame.height, 43.5)
            XCTAssertEqual(app.buttons.matching(identifier: "cameras.addSetup").count, 0)
            capture("camera-setup-chips-\(orientation.rawValue)")
        }
    }

    /// One camera, no multicam budget: the cameras page offers no Multiview, on main and on the
    /// integration. (The Pocket station-wizard test this replaced cannot run here.)
    func testCamerasPageOffersNoMultiview() {
        app.launchEnvironment.merge(ReviewLaunch(screen: .cameras).environment) { $1 }
        app.launch()
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            rotate(orientation)
            XCTAssertTrue(app.staticTexts["Your cameras"].firstMatch.waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["cameras.multiview"].exists)
            XCTAssertFalse(app.descendants(matching: .any)["multiview.setup.wifi"].exists)
        }
    }

    /// Luna joins only the camera's own Wi-Fi. A saved camera carrying a legacy hotspot setup
    /// connects from that chip without a Personal Hotspot ask: main asked only for this review
    /// data (no Insta camera could add a hotspot) and then joined the camera Wi-Fi anyway.
    func testLegacyHotspotSetupConnectsWithoutAHotspotAsk() {
        app.launchEnvironment.merge(ReviewLaunch(screen: .cameras).environment) { $1 }
        app.launch()
        rotate(.portrait)
        let hotspot = app.buttons["cameras.setup.phoneHotspot"]
        XCTAssertTrue(hotspot.waitForExistence(timeout: 10))
        hotspot.tap()
        let cancel = app.buttons["Cancel connecting to Studio camera"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["CONNECTING"].exists)
        XCTAssertFalse(app.alerts["Turn on Personal Hotspot"].exists)
        capture("hotspot-legacy-connect")
        cancel.tap()
        XCTAssertTrue(app.staticTexts["CONNECTING"].waitForNonExistence(timeout: 5))
    }

    func testConnectingCardShowsOneProgressLine() {
        app.launchEnvironment.merge(ReviewLaunch(screen: .cameras, state: "connecting").environment) { $1 }
        app.launch()
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            rotate(orientation)
            // The Luna connect's camera Wi-Fi step. Main's review fixture alone went through the DJI
            // adapter ("Moving the camera to Studio-5G"); a real Luna connect never did (e9d7dc8).
            // Lines of text: the progress bar above the line carries the same label.
            let lines = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Joining camera Wi-Fi'"))
            XCTAssertTrue(lines.firstMatch.waitForExistence(timeout: 10))
            XCTAssertEqual(lines.count, 1, "One progress line")
            XCTAssertTrue(app.buttons["Cancel connecting to Studio camera"].exists)
            capture("connecting-progress-\(orientation.rawValue)")
        }
    }

    /// A nearby Luna reads as main showed it, and Pair connects it at once on the four Luna pages.
    func testNearbyPairStartsTheLunaWizard() {
        app.launchEnvironment.merge(ReviewLaunch(screen: .cameras, state: "saved-nearby").environment) { $1 }
        app.launch()
        rotate(.portrait)
        let pair = app.buttons["Pair Luna Ultra 4D5E6F"]
        XCTAssertTrue(pair.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Insta360 · nearby"].exists)
        XCTAssertTrue(app.staticTexts["Needs approval on the camera"].exists)
        capture("nearby-card")
        pair.tap()
        XCTAssertTrue(
            app.staticTexts[
                "If the camera asks to allow this iPhone, tap Allow on its screen. First-time pairing can wait up to 90 seconds."
            ].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Look for the connection request"].exists)
        XCTAssertTrue(app.staticTexts["Connecting (Bluetooth)…"].exists, "the live line is the connect's phase")
        // Main's rail: step 2 is the approve page, not the connect plan's Bluetooth step.
        XCTAssertTrue(app.descendants(matching: .any)["Step 2: Approve on the camera, current"].exists)
        capture("pair-approve-from-nearby")
    }

    /// The wizard's Wi-Fi page and a Bluetooth permission failure, as main showed them.
    func testPairWizardWiFiPageAndBluetoothFailure() {
        let pages: [(String, [String])] = [
            (
                "pair-join",
                [
                    "We read the camera's Wi-Fi over Bluetooth, then join it for you.",
                    "Tap Join when iOS asks to join the camera network", "Bluetooth link", "Camera Wi-Fi",
                ]
            ),
            (
                "pair-bluetooth",
                [
                    "OpenInstaCine needs Bluetooth access to find the camera. Open Settings, turn on Bluetooth for OpenInstaCine, then try again.",
                    "Open Settings",
                ]
            ),
        ]
        for (state, texts) in pages {
            app.launchEnvironment.merge(ReviewLaunch(screen: .pair, state: state).environment) { $1 }
            app.launch()
            rotate(.portrait)
            XCTAssertTrue(app.staticTexts[texts[0]].waitForExistence(timeout: 10), state)
            for text in texts.dropFirst() {
                XCTAssertTrue(app.staticTexts[text].firstMatch.exists || app.buttons[text].exists, "\(state): \(text)")
            }
            capture(state)
            app.terminate()
        }
    }

    /// A2-32 product ruling 2026-10-16: the remote shutter row sits in Controls with Z's wording and
    /// its choice survives a relaunch.
    func testRemoteShutterSettingAppearsAndPersistsAfterRelaunch() throws {
        app.launchEnvironment.merge(ReviewLaunch(screen: .settings).environment) { $1 }
        app.launch()
        func remoteShutter() -> XCUIElement {
            let tabs = app.scrollViews["monitor.settings.tabs"]
            XCTAssertTrue(tabs.waitForExistence(timeout: 10))
            let tab = app.buttons["monitor.settings.tab.Controls"]
            reveal(tab, in: tabs, portrait: true)
            tab.tap()
            let row = app.buttons["Bluetooth Remote Shutter"]
            for _ in 0..<12 where !row.isHittable { app.swipeUp() }
            XCTAssertTrue(row.isHittable, "The remote shutter row is in Controls: \(app.debugDescription)")
            return row
        }
        let row = remoteShutter()
        let original = try XCTUnwrap(row.value as? String)
        XCTAssertTrue(["On", "Off"].contains(original))
        row.tap()
        let changed = original == "On" ? "Off" : "On"
        XCTAssertEqual(row.value as? String, changed)
        capture("SIMULATED-remote-shutter-setting")
        app.terminate()
        app.launch()
        let restored = remoteShutter()
        XCTAssertEqual(restored.value as? String, changed, "The remote shutter choice persists")
        restored.tap()
        XCTAssertEqual(restored.value as? String, original)
    }

    private func reveal(_ tab: XCUIElement, in rail: XCUIElement, portrait: Bool) {
        for _ in 0..<6 where !tab.isHittable {
            if portrait {
                if tab.frame.minX < rail.frame.minX { rail.swipeRight() } else { rail.swipeLeft() }
            } else {
                if tab.frame.minY < rail.frame.minY { rail.swipeDown() } else { rail.swipeUp() }
            }
        }
    }

    /// The clip at a gallery position (1 is the newest) of a twelve-clip review, named as the
    /// app's review stages them: one a minute from 2026-09-12 12:00 UTC.
    private static func clip(_ position: Int) -> String {
        let number = 13 - position
        return String(format: "VID_20260912_12%02d00_00_%03d.MP4", number - 1, number)
    }

    private func mediaClipCenter(_ filename: String) -> XCUICoordinate {
        // Asset identities are opaque: the clip is the gallery cell named by its filename.
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'monitor.media.clip.' AND label == %@", filename)
        ).firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    }

    private func visibleReviewClips() -> [String] {
        (1...12).map(Self.clip).filter { name in
            let clip = app.staticTexts[name]
            return clip.exists && clip.isHittable
        }
    }
}
