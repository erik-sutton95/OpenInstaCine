// Standalone Mac window for the local camera recovery test service.
import AppKit
import WebKit

@MainActor final class RecoveryWindow: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let url: URL
    var window: NSWindow!
    var web: WKWebView!
    init(url: URL) { self.url = url }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu=NSMenu(); let group=NSMenuItem(); let submenu=NSMenu()
        submenu.addItem(withTitle:"Quit Recovery Test", action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        group.submenu=submenu; menu.addItem(group); NSApp.mainMenu=menu
        let area=NSScreen.main?.visibleFrame ?? NSRect(x:0,y:0,width:1440,height:1000)
        let width=min(1324,area.width-60), height=min(990,area.height-60)
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:width,height:height),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title="OpenInstaCine — Luna 720p · Camera Recovery Test"
        window.appearance=NSAppearance(named:.darkAqua);window.minSize=NSSize(width:850,height:700)
        window.isReleasedWhenClosed=false;window.delegate=self
        web=WKWebView(frame:.zero);web.load(URLRequest(url:url));window.contentView=web
        window.center();window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { true }
    func applicationWillTerminate(_ notification:Notification) {
        // The service also expires when the window no longer polls it.
        web.evaluateJavaScript("document.getElementById('disconnect').click()",completionHandler:nil)
    }
}
guard CommandLine.arguments.count==2,let url=URL(string:CommandLine.arguments[1]),url.host=="127.0.0.1",url.scheme=="http" else { exit(2) }
MainActor.assumeIsolated { let app=NSApplication.shared;app.setActivationPolicy(.regular);let delegate=RecoveryWindow(url:url);app.delegate=delegate;app.run() }
