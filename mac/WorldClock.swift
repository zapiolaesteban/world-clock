// World Clock for the Mac: a small floating panel that shows the web app's compact view.
// One file, no dependencies, no Xcode project. Build it with `bash mac/build.sh`.
//
// What it does: a panel that floats above every other window on every Space, holding a web view
// that loads https://www.estebangz.com/world-clock/?mini=1. A clock in the menu bar shows and hides
// it (left click) or opens its menu (right click). It remembers its position and size, can launch
// at login, and keeps its own browser storage, so the city list survives a restart and nothing is
// shared with Safari.
//
// Two states. Expanded is the full compact page: cities, projector, typed time. The yellow button
// collapses it to a strip, 40 points tall, with the home time and the top two cities as flag and
// time. Click the strip to expand again; drag it to move it. The strip is drawn by a script this
// app injects into the page, so index.html stays exactly the web version.

import Cocoa
import WebKit
import ServiceManagement

let frameName = "WorldClockPanel"
let liveURL = "https://www.estebangz.com/world-clock/?mini=1"
// To point the panel somewhere else (a local server while developing), set a default and relaunch:
//   defaults write com.estebangz.worldclock url "http://localhost:8766/?mini=1"
//   defaults delete com.estebangz.worldclock url      # back to the live site
let pageURL = URL(string: UserDefaults.standard.string(forKey: "url") ?? liveURL)!
let expandedSize = NSSize(width: 340, height: 560)
let stripSize = NSSize(width: 320, height: 40)

// Runs inside the page once it has loaded. Builds the strip from the page's own data (home, cities,
// fmtHMS are globals in index.html) and redraws it every second while the compact class is on.
let stripScript = """
(() => {
  const css = document.createElement('style');
  css.textContent = `
    #wc-strip{display:none}
    body.wc-compact{margin:0;overflow:hidden}
    body.wc-compact > :not(#wc-strip){display:none !important}
    body.wc-compact #wc-strip{display:flex;align-items:center;justify-content:space-evenly;height:100vh;padding:0 6px;
      font-family:'DM Mono',ui-monospace,monospace;font-size:14px;font-weight:500;letter-spacing:.01em;color:var(--tx);
      background:var(--bg);white-space:nowrap;-webkit-user-select:none}
    #wc-strip span{display:flex;align-items:center;gap:6px}
    #wc-strip b{font-weight:400;font-size:16px;line-height:1}`;
  document.head.appendChild(css);
  const strip = document.createElement('div');
  strip.id = 'wc-strip';
  document.body.appendChild(strip);
  const draw = () => {
    if (!document.body.classList.contains('wc-compact')) return;
    const now = new Date();
    const items = [{f: home.flag, t: home.tz}].concat(cities.slice(0, 2).map(c => ({f: c.f, t: c.t})));
    strip.innerHTML = items.map(i => `<span><b>${i.f}</b>${fmtHMS(now, i.t).slice(0, 5)}</span>`).join('');
  };
  setInterval(draw, 1000);
  window.wcCompact = on => { document.body.classList.toggle('wc-compact', on); draw(); };
})();
"""

/// A panel that can take keyboard focus (so a time can be typed into it) without activating the
/// app, so the window being worked in keeps its menu bar and its own focus.
final class ClockPanel: NSPanel {
    var onMinimize: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    // The yellow button, and a double-click on the title bar, collapse to the strip. Nothing ever
    // minimises to the Dock or zooms to fill the screen.
    override func performMiniaturize(_ sender: Any?) { onMinimize?() }
    override func miniaturize(_ sender: Any?) { onMinimize?() }
    override func performZoom(_ sender: Any?) { onMinimize?() }
    override func zoom(_ sender: Any?) { onMinimize?() }
}

/// Covers the web view while collapsed: a drag moves the panel, a plain click expands it.
final class StripView: NSView {
    var onClick: (() -> Void)?
    private var dragged = false
    override func mouseDown(with event: NSEvent) { dragged = false }
    override func mouseDragged(with event: NSEvent) {
        if !dragged { dragged = true; window?.performDrag(with: event) }
    }
    override func mouseUp(with event: NSEvent) { if !dragged { onClick?() } }
    override func accessibilityPerformPress() -> Bool { onClick?(); return true }   // VoiceOver: one button
}

@MainActor
final class App: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    let panel = ClockPanel(contentRect: NSRect(origin: .zero, size: expandedSize),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable, .utilityWindow, .nonactivatingPanel],
                           backing: .buffered, defer: false)
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let strip = StripView()
    var webView: WKWebView!
    var compact = false

    func applicationDidFinishLaunching(_ note: Notification) {
        panel.title = "World Clock"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = NSColor(red: 0.047, green: 0.047, blue: 0.039, alpha: 1) // the page's dark paper
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.delegate = self
        panel.onMinimize = { [unowned self] in setCompact(true) }
        if !panel.setFrameUsingName(frameName) { panel.center() }   // restore last frame, else centre
        _ = panel.setFrameAutosaveName(frameName)                   // keep saving it (this re-applies it too)
        if panel.frame.width > 800 || panel.frame.height > 1200 { panel.setContentSize(expandedSize) }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()   // this app's own storage, persistent, separate from Safari
        config.userContentController.addUserScript(
            WKUserScript(source: stripScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        webView = WKWebView(frame: panel.contentView!.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.load(URLRequest(url: pageURL))
        panel.contentView!.addSubview(webView)

        strip.frame = panel.contentView!.bounds
        strip.autoresizingMask = [.width, .height]
        strip.onClick = { [unowned self] in setCompact(false) }
        strip.setAccessibilityElement(true)
        strip.setAccessibilityRole(.button)
        strip.setAccessibilityLabel("Expand World Clock")
        panel.contentView!.addSubview(strip)

        let button = statusItem.button!
        button.image = NSImage(systemSymbolName: "clock", accessibilityDescription: "World Clock")
        button.target = self
        button.action = #selector(statusClicked)
        _ = button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        // Quit while collapsed, come back collapsed. Expanded keeps the frame restored above.
        if UserDefaults.standard.bool(forKey: "compact") { setCompact(true, atLaunch: true) }
        panel.orderFrontRegardless()
    }

    // MARK: Expanded and collapsed

    func setCompact(_ on: Bool, atLaunch: Bool = false) {
        // Read the geometry first; the style changes below can nudge the frame.
        let screen = panel.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? panel.frame
        let rightSide = panel.frame.midX > visible.midX   // which side of its screen the panel lives on
        let top = panel.frame.maxY
        if on, !compact, !atLaunch { UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: "expandedFrame") }
        compact = on
        UserDefaults.standard.set(on, forKey: "compact")
        panel.titleVisibility = on ? .hidden : .visible
        panel.titlebarAppearsTransparent = on
        if on { panel.styleMask.insert(.fullSizeContentView) } else { panel.styleMask.remove(.fullSizeContentView) }
        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton] { panel.standardWindowButton(kind)?.isHidden = on }
        panel.minSize = on ? NSSize(width: 240, height: stripSize.height) : NSSize(width: 280, height: 380)
        panel.maxSize = on ? NSSize(width: 600, height: stripSize.height) : NSSize(width: 4000, height: 4000)
        strip.isHidden = !on
        webView.evaluateJavaScript("window.wcCompact && wcCompact(\(on))")

        // The strip tucks against the nearer side of the screen it is on, at the same height. The
        // panel opens back from that side, so a strip on the right expands leftwards.
        var size = stripSize
        if !on {
            let saved = UserDefaults.standard.string(forKey: "expandedFrame").map(NSRectFromString)?.size ?? expandedSize
            size = NSSize(width: min(max(saved.width, 280), 800), height: min(max(saved.height, 380), 1200))
        }
        var frame = NSRect(x: 0, y: top - size.height, width: size.width, height: size.height)
        if on {
            frame.origin.x = rightSide ? visible.maxX - size.width : visible.minX
        } else {
            frame.origin.x = rightSide ? panel.frame.maxX - size.width : panel.frame.minX
        }
        if let screen { frame = panel.constrainFrameRect(frame, to: screen) }
        panel.setFrame(frame, display: true, animate: !atLaunch)
    }

    // MARK: Menu bar

    /// Left click shows or hides the panel. Right click opens the menu.
    @objc func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu() } else { toggle() }
    }

    @objc func toggle() {
        if panel.isVisible { panel.orderOut(nil) } else { panel.makeKeyAndOrderFront(nil) }
    }

    @objc func toggleCompact() { setCompact(!compact); panel.makeKeyAndOrderFront(nil) }

    func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: panel.isVisible ? "Hide World Clock" : "Show World Clock", action: #selector(toggle), keyEquivalent: "")
        menu.addItem(withTitle: compact ? "Expand" : "Collapse to Strip", action: #selector(toggleCompact), keyEquivalent: "")
        menu.addItem(withTitle: "Reload", action: #selector(reload), keyEquivalent: "")
        menu.addItem(withTitle: "Open Full Page in Browser", action: #selector(openInBrowser), keyEquivalent: "")
        menu.addItem(.separator())
        let login = menu.addItem(withTitle: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit World Clock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        // Show the menu for this click only; a permanent menu would swallow the left-click toggle.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc func reload() { webView.load(URLRequest(url: pageURL)) }

    @objc func openInBrowser() {
        var parts = URLComponents(url: pageURL, resolvingAgainstBaseURL: false)!
        parts.query = nil   // the full page, not the compact one
        NSWorkspace.shared.open(parts.url!)
    }

    @objc func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    // MARK: Window

    /// The close button only hides the panel; the menu bar clock brings it back. Quit is in the menu.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        panel.orderOut(nil)
        return false
    }

    // MARK: Web view

    /// After every load (first launch, Reload), put the page in whichever state the panel is in.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("window.wcCompact && wcCompact(\(compact))")
    }

    /// Clicked links (the arrow to the full page, anything external) open in the default browser;
    /// the panel itself only ever shows the World Clock.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if action.navigationType == .linkActivated, let url = action.request.url {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }

    /// Links that ask for a new window (target="_blank", window.open) also go to the browser.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url { NSWorkspace.shared.open(url) }
        return nil
    }

    /// Offline or the site unreachable: say so in the panel instead of showing a blank view.
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let html = """
        <body style="margin:0;height:100vh;display:grid;place-items:center;background:#0c0c0a;color:#a8a89c;
        font:15px/1.5 -apple-system,sans-serif;text-align:center;padding:24px;box-sizing:border-box">
        <div><b style="color:#e8e8e0">World Clock can't be reached.</b><br>Check the connection, then choose
        Reload from the clock in the menu&nbsp;bar.</div></body>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = App()                  // lives as long as run() does, which is the whole session
    app.delegate = delegate
    app.setActivationPolicy(.accessory)   // no Dock icon, no app menu; the menu bar clock is the whole UI
    app.run()
}
