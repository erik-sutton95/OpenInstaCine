import Foundation
import Network
import ObjectiveC
import XCTest

/// Live preview never goes idle. No-op the iOS 26 quiescence selectors.
private func lunaDisableQuiescence() {
    let noop1: @convention(block) (AnyObject, Bool) -> Void = { _, _ in }
    let noop2: @convention(block) (AnyObject, Bool, Bool) -> Void = { _, _, _ in }
    if let processClass = NSClassFromString("XCUIApplicationProcess") {
        _ = class_replaceMethod(
            processClass,
            NSSelectorFromString("waitForQuiescenceIncludingAnimationsIdle:isPreEvent:"),
            imp_implementationWithBlock(noop2),
            "v@:BB")
        _ = class_replaceMethod(
            processClass,
            NSSelectorFromString("waitForQuiescenceIncludingAnimationsIdle:usingActivity:isPreEvent:"),
            imp_implementationWithBlock({ _, _, _, _ in } as @convention(block) (AnyObject, Bool, AnyObject?, Bool) -> Void),
            "v@:B@B")
        _ = class_replaceMethod(
            processClass,
            NSSelectorFromString("_initiateQuiescenceChecksIncludingAnimationsIdle:"),
            imp_implementationWithBlock(noop1),
            "v@:B")
    }
    if let appClass = NSClassFromString("XCUIApplication") {
        _ = class_replaceMethod(
            appClass,
            NSSelectorFromString("_waitForQuiescenceAsPreEvent:"),
            imp_implementationWithBlock(noop1),
            "v@:B")
        _ = class_replaceMethod(
            appClass,
            NSSelectorFromString("_waitForQuiescence"),
            imp_implementationWithBlock({ _ in } as @convention(block) (AnyObject) -> Void),
            "v@:")
    }
}

/// Lab-only XC driver for the official Insta360 iOS app.
/// Does not launch OpenInstaCine. Listens on TCP 18777 for JSON commands.
final class InteractiveDriver: XCTestCase {
    fileprivate static let bundleID = "com.insta360.oner"
    private static let port: UInt16 = 18_777

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
        executionTimeAllowance = 6 * 60 * 60
        lunaDisableQuiescence()
    }

    func testDriveOfficialInsta360() throws {
        let app = XCUIApplication(bundleIdentifier: Self.bundleID)
        app.setValue(false, forKey: "idleAnimationWaitEnabled")
        if app.state == .notRunning || app.state == .unknown {
            app.activate()
            if app.state == .notRunning {
                app.launch()
            }
        } else {
            app.activate()
        }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "Insta360 did not reach foreground")

        let server = CommandServer(app: app, port: Self.port)
        try server.start()
        addTeardownBlock { server.stop() }

        let deadline = Date().addingTimeInterval(6 * 60 * 60)
        while Date() < deadline && !server.shouldStop {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }
}

private final class CommandServer {
    private var app: XCUIApplication
    private let port: UInt16
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private let queue = DispatchQueue(label: "luna.official.xc")
    private(set) var shouldStop = false

    init(app: XCUIApplication, port: UInt16) {
        self.app = app
        self.port = port
    }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        shouldStop = true
        listener?.cancel()
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
    }

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.drop(id) }
            if case .cancelled = state { self?.drop(id) }
        }
        connection.start(queue: queue)
        readRequest(connection)
    }

    private func drop(_ id: ObjectIdentifier) {
        connections[id]?.cancel()
        connections[id] = nil
    }

    private func readRequest(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.handle(data, on: connection)
            }
            if isComplete || error != nil {
                connection.cancel()
                return
            }
            self.readRequest(connection)
        }
    }

    private func handle(_ data: Data, on connection: NWConnection) {
        guard let text = String(data: data, encoding: .utf8) else {
            reply(connection, status: 400, body: #"{"ok":false,"error":"not utf8"}"#)
            return
        }
        let parts = text.split(separator: "\r\n\r\n", maxSplits: 1, omittingEmptySubsequences: false)
        let header = String(parts.first ?? "")
        let body = parts.count > 1 ? String(parts[1]) : ""
        let first = header.split(separator: "\r\n", maxSplits: 1).first.map(String.init) ?? ""
        let tokens = first.split(separator: " ")
        let method = tokens.first.map(String.init) ?? ""
        let path = tokens.dropFirst().first.map(String.init) ?? "/"
        DispatchQueue.main.sync {
            self.dispatch(method: method, path: path, body: body, connection: connection)
        }
    }

    private func dispatch(method: String, path: String, body: String, connection: NWConnection) {
        do {
            if method == "GET" && (path == "/health" || path.hasPrefix("/health?")) {
                replyJSON(connection, ["ok": true, "bundle": InteractiveDriver.bundleID, "state": stateName()])
                return
            }
            if method == "GET" && (path == "/tree" || path.hasPrefix("/tree?")) {
                var shot = snapshot()
                if path.contains("full=1") {
                    shot["tree"] = app.debugDescription
                }
                replyJSON(connection, shot)
                return
            }
            if method == "POST" && path == "/command" {
                let cmd = try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any] ?? [:]
                replyJSON(connection, perform(cmd))
                return
            }
            if method == "GET" && (path == "/screenshot" || path.hasPrefix("/screenshot?")) {
                let png = XCUIScreen.main.screenshot().pngRepresentation
                replyJSON(connection, ["ok": true, "png": png.base64EncodedString()])
                return
            }
            if method == "POST" && path == "/stop" {
                shouldStop = true
                replyJSON(connection, ["ok": true, "stopped": true])
                return
            }
            reply(connection, status: 404, body: #"{"ok":false,"error":"not found"}"#)
        } catch {
            replyJSON(connection, ["ok": false, "error": String(describing: error)])
        }
    }

    private func perform(_ cmd: [String: Any]) -> [String: Any] {
        let action = (cmd["action"] as? String) ?? ""
        switch action {
        case "activate":
            app.activate()
        case "launch":
            app.launch()
        case "home":
            XCUIDevice.shared.press(.home)
        case "target":
            // Drive another app (Settings, SpringBoard alerts, OpenInstaCine).
            let bundle = (cmd["bundle"] as? String) ?? InteractiveDriver.bundleID
            app = XCUIApplication(bundleIdentifier: bundle)
            if (cmd["activate"] as? Bool) ?? true { app.activate() }
        case "terminate":
            app.terminate()
        case "tapAt":
            // Absolute screen points, independent of the target app's frame.
            if let x = number(cmd["x"]), let y = number(cmd["y"]) {
                app.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: x, dy: y)).tap()
            }
        case "tap":
            tap(cmd)
        case "press":
            press(cmd)
        case "swipe":
            swipe(cmd)
        case "type":
            let text = (cmd["text"] as? String) ?? ""
            app.typeText(text)
        case "wait":
            let seconds = (cmd["seconds"] as? Double) ?? 1
            Thread.sleep(forTimeInterval: seconds)
        case "find":
            let needle = (cmd["text"] as? String) ?? ""
            let tree = app.debugDescription
            let matches = tree.split(separator: "\n")
                .map(String.init)
                .filter { $0.localizedCaseInsensitiveContains(needle) }
            return [
                "ok": true,
                "action": action,
                "state": stateName(),
                "matches": Array(matches.prefix(40)),
            ]
        default:
            return ["ok": false, "error": "unknown action \(action)"]
        }
        let pause = (cmd["pause"] as? Double) ?? 0.25
        if pause > 0 { Thread.sleep(forTimeInterval: pause) }
        return ["ok": true, "action": action, "state": stateName()]
    }

    private func tap(_ cmd: [String: Any]) {
        if let x = number(cmd["x"]), let y = number(cmd["y"]) {
            app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
            return
        }
        if let label = cmd["label"] as? String, !label.isEmpty {
            let target = element(label: label, type: cmd["type"] as? String).firstMatch
            if target.exists {
                target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
        }
    }

    private func press(_ cmd: [String: Any]) {
        let duration = (cmd["duration"] as? Double) ?? 0.8
        if let label = cmd["label"] as? String, !label.isEmpty {
            element(label: label, type: cmd["type"] as? String).firstMatch.press(forDuration: duration)
            return
        }
        if let x = number(cmd["x"]), let y = number(cmd["y"]) {
            app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).press(forDuration: duration)
        }
    }

    private func swipe(_ cmd: [String: Any]) {
        let direction = (cmd["direction"] as? String) ?? "up"
        if let x1 = number(cmd["x1"]), let y1 = number(cmd["y1"]),
           let x2 = number(cmd["x2"]), let y2 = number(cmd["y2"]) {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: x1, dy: y1))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: x2, dy: y2))
            start.press(forDuration: 0.05, thenDragTo: end)
            return
        }
        switch direction {
        case "down": app.swipeDown()
        case "left": app.swipeLeft()
        case "right": app.swipeRight()
        default: app.swipeUp()
        }
    }

    private func element(label: String, type: String?) -> XCUIElement {
        switch type {
        case "text": return app.staticTexts[label]
        case "cell": return app.cells[label]
        case "image": return app.images[label]
        case "switch": return app.switches[label]
        case "any": return app.descendants(matching: .any)[label]
        default: return app.buttons[label]
        }
    }

    private func snapshot() -> [String: Any] {
        [
            "state": stateName(),
            "label": app.label,
            "buttons": labels(app.buttons),
            "texts": labels(app.staticTexts),
            "cells": labels(app.cells),
            "images": labels(app.images),
            "switches": labels(app.switches),
        ]
    }

    private func labels(_ query: XCUIElementQuery) -> [String] {
        let count = min(query.count, 80)
        return (0..<count).compactMap { index -> String? in
            let el = query.element(boundBy: index)
            let name = el.label.isEmpty ? el.identifier : el.label
            return name.isEmpty ? nil : name
        }
    }

    private func stateName() -> String {
        switch app.state {
        case .runningForeground: return "foreground"
        case .runningBackground: return "background"
        case .runningBackgroundSuspended: return "suspended"
        case .notRunning: return "notRunning"
        default: return "unknown"
        }
    }

    private func number(_ value: Any?) -> Double? {
        if let n = value as? Double { return n }
        if let n = value as? Int { return Double(n) }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }

    private func replyJSON(_ connection: NWConnection, _ object: [String: Any]) {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted])) ?? Data("{}".utf8)
        reply(connection, status: 200, body: String(data: data, encoding: .utf8) ?? "{}")
    }

    private func reply(_ connection: NWConnection, status: Int, body: String) {
        let payload = Data(body.utf8)
        let header = "HTTP/1.1 \(status) OK\r\nContent-Type: application/json\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
        var data = Data(header.utf8)
        data.append(payload)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
