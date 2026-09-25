import XCTest

/// Opt-in Simulator walkthrough against a real Luna reached over the Mac's Wi-Fi.
/// Needs `OIC_WALKTHROUGH_DIR` (host folder for screenshots) and `LUNA_IDENTITY`
/// passed as TEST_RUNNER_ env. Drives the app's DEBUG remote on 127.0.0.1:18780.
final class LunaLiveWalkthroughTests: XCTestCase {
    private var app: XCUIApplication!
    private var outDir: String { ProcessInfo.processInfo.environment["OIC_WALKTHROUGH_DIR"] ?? "" }

    override func setUpWithError() throws {
        guard !outDir.isEmpty else { throw XCTSkip("Set TEST_RUNNER_OIC_WALKTHROUGH_DIR") }
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchEnvironment["LUNA_IDENTITY"] = ProcessInfo.processInfo.environment["LUNA_IDENTITY"] ?? ""
        XCUIDevice.shared.orientation = .portrait
        if name.contains("Attached") {
            app.activate()  // keep the running session (e.g. a recovery card on screen)
            return
        }
        app.launch()
        let decline = app.buttons["reliability.consent.decline"]
        if decline.waitForExistence(timeout: 6) { decline.tap() }
        Thread.sleep(forTimeInterval: 4)
        remote(["action": "connectFirst", "pause": 8])
        XCTAssertTrue(app.buttons["monitor.system.settings"].waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 2)
    }

    @discardableResult
    func remote(_ body: [String: Any]) -> [String: Any] {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:18780/action")!)
        request.httpMethod = "POST"
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120
        let done = expectation(description: "remote")
        var result: [String: Any] = [:]
        URLSession.shared.dataTask(with: request) { data, _, _ in
            result = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 130)
        return result
    }

    func shot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: URL(fileURLWithPath: outDir).appendingPathComponent("\(name).png"))
    }

    func dumpTree(_ name: String) {
        try? app.debugDescription.write(
            toFile: (outDir as NSString).appendingPathComponent("\(name).txt"), atomically: true, encoding: .utf8)
    }

    func tapIf(_ id: String, _ timeout: TimeInterval = 3) -> Bool {
        let b = app.buttons[id]
        guard b.waitForExistence(timeout: timeout), b.isHittable else { return false }
        b.tap()
        return true
    }

    func feed(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
    }

    func testA_LiveControls() throws {
        // Record with confirmation.
        XCTAssertTrue(tapIf("monitor.system.record"))
        Thread.sleep(forTimeInterval: 1.2)
        shot("ui-01-record-confirm"); dumpTree("tree-record-confirm")
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.exists { cancel.tap() } else { feed(0.5, 0.3).tap() }
        Thread.sleep(forTimeInterval: 1)
        // Lock.
        XCTAssertTrue(tapIf("monitor.system.lock"))
        Thread.sleep(forTimeInterval: 1)
        shot("ui-02-locked"); dumpTree("tree-locked")
        _ = tapIf("monitor.capture.iso", 1)
        Thread.sleep(forTimeInterval: 1)
        shot("ui-02b-locked-iso-tap")
        let lock = app.buttons["monitor.system.lock"]
        if lock.exists { lock.press(forDuration: 1.2) }
        Thread.sleep(forTimeInterval: 1)
        shot("ui-02c-unlock-attempt")
        if app.buttons["monitor.capture.iso"].exists, !app.buttons["monitor.capture.iso"].isHittable {
            lock.tap(); Thread.sleep(forTimeInterval: 1)
        }
        // DISP cycle.
        XCTAssertTrue(tapIf("monitor.system.display"))
        Thread.sleep(forTimeInterval: 1.2)
        shot("ui-03-disp-clean"); dumpTree("tree-disp-clean")
        _ = tapIf("monitor.system.display")
        Thread.sleep(forTimeInterval: 1.2)
        shot("ui-03b-disp-back")
        // Zoom chip.
        XCTAssertTrue(tapIf("monitor.system.zoom"))
        Thread.sleep(forTimeInterval: 1.2)
        shot("ui-04-zoom-chip"); dumpTree("tree-zoom")
        feed(0.5, 0.2).tap()
        Thread.sleep(forTimeInterval: 1)
        // Gimbal sheet.
        XCTAssertTrue(tapIf("monitor.system.gimbalControls"))
        Thread.sleep(forTimeInterval: 1.5)
        shot("ui-05-gimbal-sheet"); dumpTree("tree-gimbal")
        app.swipeUp()
        Thread.sleep(forTimeInterval: 1)
        shot("ui-05b-gimbal-sheet-scrolled"); dumpTree("tree-gimbal-scrolled")
        if !tapIf("motion.close", 1) { feed(0.5, 0.15).tap() }
        Thread.sleep(forTimeInterval: 1)
        // Assists: expand and LUT options.
        XCTAssertTrue(tapIf("monitor.assists.expand"))
        Thread.sleep(forTimeInterval: 1.2)
        shot("ui-06-assists-expanded"); dumpTree("tree-assists")
        let lut = app.buttons["monitor.assist.LUT"]
        if lut.waitForExistence(timeout: 2) {
            lut.press(forDuration: 1.0)
            Thread.sleep(forTimeInterval: 1.5)
            shot("ui-07-lut-options"); dumpTree("tree-lut-options")
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            shot("ui-07b-lut-options-scrolled")
            feed(0.5, 0.12).tap()
            Thread.sleep(forTimeInterval: 1)
        }
        shot("ui-07c-after-lut")
        // Tap focus, then drag to track.
        feed(0.4, 0.45).tap()
        Thread.sleep(forTimeInterval: 1.5)
        shot("ui-08-tap-focus")
        feed(0.4, 0.42).press(forDuration: 0.3, thenDragTo: feed(0.6, 0.52))
        Thread.sleep(forTimeInterval: 2.5)
        shot("ui-09-drag-track"); dumpTree("tree-track")
        _ = tapIf("monitor.system.trackCancel", 1)
        remote(["action": "cancelTrack"])
    }

    func note(_ line: String) {
        let url = URL(fileURLWithPath: outDir).appendingPathComponent("notes.txt")
        let old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try? (old + line + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    func state() -> [String: Any] {
        let done = expectation(description: "state")
        var result: [String: Any] = [:]
        URLSession.shared.dataTask(with: URL(string: "http://127.0.0.1:18780/state")!) { data, _, _ in
            result = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 20)
        return result
    }

    func tapLabel(_ label: String) -> Bool {
        let b = app.buttons[label].firstMatch
        if b.waitForExistence(timeout: 2), b.isHittable { b.tap(); return true }
        let t = app.staticTexts[label].firstMatch
        if t.exists, t.isHittable { t.tap(); return true }
        note("missing: \(label)")
        return false
    }

    func testB_GimbalAssistsTrack() throws {
        remote(["action": "zoom", "value": 1])
        XCTAssertTrue(tapIf("monitor.system.gimbalControls"))
        Thread.sleep(forTimeInterval: 1.5)
        dumpTree("tree-gimbal-b")
        for tab in ["Speed", "Ramp", "Double-tap", "Mode"] {
            _ = tapLabel(tab)
            Thread.sleep(forTimeInterval: 1)
            shot("ui-10-gimbal-\(tab)")
        }
        _ = tapLabel("Motion Control")
        Thread.sleep(forTimeInterval: 1.5)
        shot("ui-11-motion-control"); dumpTree("tree-motion")
        app.swipeUp(); Thread.sleep(forTimeInterval: 1)
        shot("ui-11b-motion-control-scrolled")
        if !tapIf("motion.close", 1) { _ = tapLabel("Close") }
        Thread.sleep(forTimeInterval: 1)
        shot("ui-11c-after-motion")
        if app.buttons["Close"].exists { app.buttons["Close"].firstMatch.tap() }
        Thread.sleep(forTimeInterval: 1)
        shot("ui-11d-closed")
        // Assists.
        if tapIf("monitor.assists.expand") {
            Thread.sleep(forTimeInterval: 1.2)
            shot("ui-12-assists-expanded"); dumpTree("tree-assists-b")
            let lut = app.buttons["monitor.assist.LUT"]
            if lut.waitForExistence(timeout: 2) {
                lut.press(forDuration: 1.0)
                Thread.sleep(forTimeInterval: 1.5)
                shot("ui-13-lut-options"); dumpTree("tree-lut-options")
            } else { note("no LUT assist button") }
        } else { note("assists.expand not hittable") }
        // Drag to track.
        feed(0.5, 0.2).tap()
        Thread.sleep(forTimeInterval: 1)
        feed(0.35, 0.42).press(forDuration: 0.6, thenDragTo: feed(0.6, 0.55))
        Thread.sleep(forTimeInterval: 2)
        shot("ui-14-drag-track")
        note("after drag tracking=\(state()["tracking"] ?? "?") note=\(state()["controlNote"] ?? "")")
        _ = tapIf("monitor.system.trackCancel", 1)
    }

    func testC_AssistsLUT() throws {
        let expand = app.buttons["monitor.assists.expand"]
        XCTAssertTrue(expand.waitForExistence(timeout: 3))
        note("expand hittable=\(expand.isHittable) frame=\(expand.frame)")
        expand.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        Thread.sleep(forTimeInterval: 1.5)
        shot("ui-12-assists-expanded"); dumpTree("tree-assists-c")
        let lut = app.buttons["monitor.assist.LUT"]
        if lut.waitForExistence(timeout: 2) {
            lut.tap()
            Thread.sleep(forTimeInterval: 1.5)
            shot("ui-13a-lut-on")
            lut.press(forDuration: 1.2)
            Thread.sleep(forTimeInterval: 1.5)
            shot("ui-13-lut-options"); dumpTree("tree-lut-options")
            app.swipeUp(); Thread.sleep(forTimeInterval: 1)
            shot("ui-13b-lut-options-scrolled")
        } else { note("no LUT assist button after expand") }
    }

    func testD_Media() throws {
        XCTAssertTrue(tapIf("monitor.system.media"))
        Thread.sleep(forTimeInterval: 4)
        shot("ui-20-media-grid"); dumpTree("tree-media")
    }

    func testE_MediaFlows() throws {
        XCTAssertTrue(tapIf("monitor.system.media"))
        Thread.sleep(forTimeInterval: 4)
        _ = tapIf("monitor.media.layout.list")
        Thread.sleep(forTimeInterval: 1.5)
        shot("ui-21-media-list")
        _ = tapIf("monitor.media.layout.grid")
        Thread.sleep(forTimeInterval: 1)
        let mine = app.otherElements["monitor.media.clip./storage_internal/DCIM/Camera01/VID_20260925_022752_004.mp4"]
        XCTAssertTrue(mine.waitForExistence(timeout: 5))
        let fav = app.buttons.matching(NSPredicate(format: "label == 'Add favorite'")).element(boundBy: 0)
        if fav.exists { fav.tap() }
        Thread.sleep(forTimeInterval: 1)
        _ = tapLabel("Favorites, 1")
        Thread.sleep(forTimeInterval: 1.2)
        shot("ui-22-media-favorites")
        _ = tapLabel("All, 4")
        Thread.sleep(forTimeInterval: 1)
        let other = app.otherElements["monitor.media.clip./storage_internal/DCIM/Camera01/VID_20260917_182703_003.mp4"]
        if other.waitForExistence(timeout: 3) { other.tap() }
        Thread.sleep(forTimeInterval: 2)
        shot("ui-23-player-opening")
        Thread.sleep(forTimeInterval: 6)
        shot("ui-24-player-proxy"); dumpTree("tree-player")
    }

    func testF_DeleteOwnClip() throws {
        let target = ProcessInfo.processInfo.environment["OIC_DELETE_CLIP"] ?? ""
        guard !target.isEmpty else { throw XCTSkip("Set TEST_RUNNER_OIC_DELETE_CLIP to a clip you recorded") }
        XCTAssertTrue(tapIf("monitor.system.media"))
        Thread.sleep(forTimeInterval: 4)
        let mine = app.otherElements["monitor.media.clip./storage_internal/DCIM/Camera01/\(target)"]
        XCTAssertTrue(mine.waitForExistence(timeout: 5))
        mine.tap()
        Thread.sleep(forTimeInterval: 3)
        shot("ui-25-player-own-clip")
        let delete = app.buttons["Delete clip from camera"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        delete.tap()
        Thread.sleep(forTimeInterval: 1.2)
        shot("ui-26-delete-confirm"); dumpTree("tree-delete-confirm")
        let confirm = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Delete'"))
            .allElementsBoundByIndex.last { $0.isHittable && $0.label != "Delete clip from camera" }
        note("delete confirm button=\(confirm?.label ?? "none")")
        confirm?.tap()
        Thread.sleep(forTimeInterval: 4)
        shot("ui-27-after-delete")
        let files = remote(["action": "files"])["files"] as? [[String: Any]] ?? []
        note("after delete, files=\(files.compactMap { $0["name"] as? String })")
    }

    func testG_Landscape() throws {
        defer { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 3)
        shot("ui-30-landscape-live"); dumpTree("tree-landscape")
        if tapIf("monitor.capture.iso") {
            Thread.sleep(forTimeInterval: 1.2); shot("ui-31-landscape-iso")
            feed(0.5, 0.3).tap(); Thread.sleep(forTimeInterval: 1)
        }
        if tapIf("monitor.capture.format") {
            Thread.sleep(forTimeInterval: 1.2); shot("ui-32-landscape-format")
            feed(0.5, 0.8).tap(); Thread.sleep(forTimeInterval: 1)
        }
        if tapIf("monitor.system.gimbalControls") {
            Thread.sleep(forTimeInterval: 1.2); shot("ui-33-landscape-gimbal")
            feed(0.2, 0.5).tap(); Thread.sleep(forTimeInterval: 1)
        }
        if tapIf("monitor.system.settings") {
            Thread.sleep(forTimeInterval: 1.5); shot("ui-34-landscape-settings")
            _ = tapLabel("Back")
            Thread.sleep(forTimeInterval: 1)
        }
        if tapIf("monitor.system.media") {
            Thread.sleep(forTimeInterval: 3); shot("ui-35-landscape-media")
            _ = tapLabel("Back")
            Thread.sleep(forTimeInterval: 1)
        }
        shot("ui-36-landscape-end")
    }

    func testH_AttachedRetryRecovery() throws {
        shot("ui-40-recovery-card")
        XCTAssertTrue(tapLabel("Retry connection"))
        for i in 1...6 {
            Thread.sleep(forTimeInterval: 5)
            let s = state()
            note("retry +\(i * 5)s phase=\(s["phase"] ?? "?") recovery=\(s["recovery"] ?? "?") fps=\(s["liveFPS"] ?? "?")")
        }
        shot("ui-41-after-retry")
    }

    func testI_HoldISOInAuto() throws {
        let iso = app.buttons["monitor.capture.iso"]
        XCTAssertTrue(iso.waitForExistence(timeout: 5))
        iso.press(forDuration: 1.0)
        Thread.sleep(forTimeInterval: 0.3)
        shot("ui-50-hold-iso-auto")
        iso.tap()
        Thread.sleep(forTimeInterval: 1.2)
        shot("ui-51-iso-sheet-auto")
    }

    func testDumpLive() throws {
        shot("ui-00-live")
        dumpTree("tree-live")
    }
}
