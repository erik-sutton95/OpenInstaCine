// Offline macOS comparison of captured phone and detachable-screen previews.
// Usage: LunaCaptureCompare phone.mp4 screen.mp4 screen-clean.mp4 "phone caption" "screen caption"
// No camera connections, networking, or LUTs. Build: swiftc ... -o <binary>
import AppKit
import AVKit

@MainActor
final class CaptureComparison: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var phone: AVPlayer!
    private var screen: AVPlayer!
    private var screenView: AVPlayerView!
    private let paths: [String]
    private let captions: [String]

    init(paths: [String], captions: [String]) { self.paths = paths; self.captions = captions }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Capture Comparison", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let item = NSMenuItem(); item.submenu = appMenu; menu.addItem(item)
        NSApp.mainMenu = menu

        phone = AVPlayer(url: URL(fileURLWithPath: paths[0]))
        screen = AVPlayer(url: URL(fileURLWithPath: paths[1]))
        phone.isMuted = true; screen.isMuted = true
        let area = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: min(1500, area.width - 60), height: min(800, area.height - 60)), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "OpenInstaCine — Captured Feed Comparison"
        window.appearance = NSAppearance(named: .darkAqua)
        window.minSize = NSSize(width: 940, height: 500)
        window.isReleasedWhenClosed = false

        let root = NSStackView(); root.orientation = .vertical; root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        root.translatesAutoresizingMaskIntoConstraints = false
        let title = label("PHONE + DETACHABLE SCREEN", size: 21, bold: true)
        title.textColor = NSColor(calibratedRed: 1, green: 0.83, blue: 0.05, alpha: 1)
        root.addArrangedSubview(title)
        root.addArrangedSubview(label("CAPTURE REPLAY · Different recording times · No added LUT", size: 13))

        let columns = NSStackView(); columns.orientation = .horizontal
        columns.distribution = .fillEqually; columns.spacing = 18
        let left = panel(title: "PHONE PREVIEW", detail: captions[0], player: phone)
        let right = panel(title: "DETACHABLE SCREEN", detail: captions[1], player: screen)
        screenView = right.1
        columns.addArrangedSubview(left.0); columns.addArrangedSubview(right.0)
        root.addArrangedSubview(columns)

        let controls = NSStackView(); controls.spacing = 12
        controls.addArrangedSubview(NSButton(title: "Play both", target: self, action: #selector(playBoth)))
        controls.addArrangedSubview(NSButton(title: "Pause both", target: self, action: #selector(pauseBoth)))
        controls.addArrangedSubview(NSButton(title: "Restart both", target: self, action: #selector(restartBoth)))
        let choice = NSSegmentedControl(labels: ["Screen: full capture", "Clean startup only"], trackingMode: .selectOne, target: self, action: #selector(selectScreen(_:)))
        choice.selectedSegment = 0; controls.addArrangedSubview(choice)
        root.addArrangedSubview(controls)
        root.addArrangedSubview(label("Screen capture has missing packets: later frames may show artifacts. Clean startup shows only the intact opening sequence.", size: 12))
        root.addArrangedSubview(label("Appearance comparison only. These captures do not establish a pre-LUT feed or simultaneous live operation.", size: 12))

        let content = NSView(); content.addSubview(root); window.contentView = content
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor), root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor), root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            columns.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -40), columns.heightAnchor.constraint(greaterThanOrEqualToConstant: 260)
        ])
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        playBoth()
    }

    private func label(_ text: String, size: CGFloat, bold: Bool = false) -> NSTextField {
        let result = NSTextField(wrappingLabelWithString: text)
        result.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
        result.alignment = .center
        result.setContentCompressionResistancePriority(.required, for: .vertical)
        return result
    }

    private func panel(title: String, detail: String, player: AVPlayer) -> (NSStackView, AVPlayerView) {
        let stack = NSStackView(); stack.orientation = .vertical; stack.spacing = 8
        stack.addArrangedSubview(label(title, size: 17, bold: true))
        stack.addArrangedSubview(label(detail, size: 12))
        let view = AVPlayerView(); view.player = player; view.controlsStyle = .inline; view.videoGravity = .resizeAspect
        view.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        view.heightAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        return (stack, view)
    }

    @objc private func playBoth() { phone.play(); screen.play() }
    @objc private func pauseBoth() { phone.pause(); screen.pause() }
    @objc private func restartBoth() {
        phone.seek(to: .zero); screen.seek(to: .zero); playBoth()
    }
    @objc private func selectScreen(_ sender: NSSegmentedControl) {
        screen.pause()
        screen.replaceCurrentItem(with: AVPlayerItem(url: URL(fileURLWithPath: paths[sender.selectedSegment == 0 ? 1 : 2])))
        screen.play()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let arguments = Array(CommandLine.arguments.dropFirst())
let paths = Array(arguments.prefix(3))
guard arguments.count == 5, paths.allSatisfy({ FileManager.default.fileExists(atPath: $0) }) else {
    fputs("Usage: LunaCaptureCompare phone.mp4 screen.mp4 screen-clean.mp4 'phone caption' 'screen caption'\n", stderr)
    exit(2)
}
MainActor.assumeIsolated {
    let application = NSApplication.shared
    application.setActivationPolicy(.regular)
    let controller = CaptureComparison(paths: paths, captions: Array(arguments.suffix(2)))
    application.delegate = controller
    application.run()
}
