// World Clock for the Mac: a small floating panel that shows the web app's compact view.
// One file, no dependencies, no Xcode project. Build it with `bash mac/build.sh`.
//
// A panel floats above every other window on every Space, holding a web view that loads
// https://www.estebangz.com/world-clock/?mini=1. A clock in the menu bar shows and hides it (left
// click) or opens its menu (right click). Frame and state survive relaunch, it can launch at login,
// and its browser storage is its own, so the city list persists and nothing is shared with Safari.
//
// Three states, smallest last:
//   panel   the full compact page: cities, projector, typed time
//   strip   one row, 40 points tall: a chevron in, home plus the top two cities as flag and time,
//           a chevron down
//   single  a chevron out, one flag and time; scroll over it to step through the other cities
// The yellow button or a title-bar double-click collapses the panel to the strip. On the strip,
// the down chevron opens the panel and the inward chevron (or the times) goes to the single time;
// on the single time the outward chevron (or a click) goes back to the strip. Strip and single
// tuck against the nearer side of their screen. They are drawn by a script this app injects into
// the page, so index.html stays exactly the web version.

import Cocoa
import WebKit
import ServiceManagement

enum Mode: Int { case panel, strip, single }

let frameName = "WorldClockPanel"
let liveURL = "https://www.estebangz.com/world-clock/?mini=1"
// To point the panel somewhere else (a local server while developing), set a default and relaunch:
//   defaults write com.estebangz.worldclock url "http://localhost:8766/?mini=1"
//   defaults delete com.estebangz.worldclock url      # back to the live site
let pageURL = URL(string: UserDefaults.standard.string(forKey: "url") ?? liveURL)!
let panelSize = NSSize(width: 340, height: 560)
let sizes: [Mode: NSSize] = [.strip: NSSize(width: 344, height: 40), .single: NSSize(width: 148, height: 40)]

// Runs inside the page once it has loaded. Draws the strip and the single time from the page's own
// data (home, cities and fmtHMS are globals in index.html), redrawing every second.
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
    #wc-strip b{font-weight:400;font-size:16px;line-height:1}
    #wc-strip .wc-go{color:var(--mu);flex:none}`;
  document.head.appendChild(css);
  const strip = document.createElement('div');
  strip.id = 'wc-strip';
  document.body.appendChild(strip);
  // Three chevrons, one drawing: inward (collapse the strip to one time), outward (one time back
  // to the strip), down (open the panel). The native overlay turns the clicks into state changes.
  const chevron = pts => '<svg class="wc-go" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" '
    + `stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><polyline points="${pts}"/></svg>`;
  const inward = chevron('9 6 15 12 9 18'), outward = chevron('15 6 9 12 15 18'), down = chevron('6 9 12 15 18 9');
  let mode = 0, index = 0;
  const draw = () => {
    document.body.classList.toggle('wc-compact', mode > 0);
    if (!mode) return;
    const all = [{f: home.flag, t: home.tz}].concat(cities.map(c => ({f: c.f, t: c.t})));
    const shown = mode === 1 ? all.slice(0, 3) : [all[((index % all.length) + all.length) % all.length]];
    const now = new Date();
    strip.innerHTML = (mode === 1 ? inward : outward)
      + shown.map(i => `<span><b>${i.f}</b>${fmtHMS(now, i.t).slice(0, 5)}</span>`).join('')
      + (mode === 1 ? down : '');
  };
  setInterval(draw, 1000);
  window.wcState = (m, i) => { mode = m; index = i; draw(); };
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

/// Covers the web view while collapsed. Drag moves the panel; a click on the right end (the
/// chevron) opens the panel, a click elsewhere toggles strip and single; a scroll steps cities.
final class StripView: NSView {
    var onClick: (() -> Void)?, onChevron: (() -> Void)?, onStep: ((Int) -> Void)?
    var chevronWidth: CGFloat = 0
    private var dragged = false, stepped = false, travel: CGFloat = 0
    override func mouseDown(with event: NSEvent) { dragged = false }
    override func mouseDragged(with event: NSEvent) {
        if !dragged { dragged = true; window?.performDrag(with: event) }
    }
    override func mouseUp(with event: NSEvent) {
        guard !dragged else { return }
        if convert(event.locationInWindow, from: nil).x > bounds.width - chevronWidth { onChevron?() } else { onClick?() }
    }
    /// One step per trackpad gesture (after a little travel, momentum ignored) or per wheel notch.
    override func scrollWheel(with event: NSEvent) {
        if event.phase == .began { travel = 0; stepped = false }
        if event.momentumPhase != [] { return }
        travel += event.scrollingDeltaY
        let wheelNotch = event.phase == [] && event.momentumPhase == []
        if wheelNotch || (!stepped && abs(travel) > 24) {
            onStep?(travel < 0 ? 1 : -1)
            stepped = true
            travel = 0
        }
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func accessibilityPerformPress() -> Bool { onClick?(); return true }
}

@MainActor
final class App: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    let panel = ClockPanel(contentRect: NSRect(origin: .zero, size: panelSize),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable, .utilityWindow, .nonactivatingPanel],
                           backing: .buffered, defer: false)
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let strip = StripView()
    var webView: WKWebView!
    var mode = Mode.panel
    var cityIndex = 0

    func applicationDidFinishLaunching(_ note: Notification) {
        panel.title = "World Clock"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = NSColor(red: 0.047, green: 0.047, blue: 0.039, alpha: 1) // the page's dark paper
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.delegate = self
        panel.onMinimize = { [unowned self] in setMode(.strip) }
        if !panel.setFrameUsingName(frameName) { panel.center() }   // restore last frame, else centre
        _ = panel.setFrameAutosaveName(frameName)                   // keep saving it (this re-applies it too)
        let f = panel.frame   // a saved frame that is absurd for the panel (zoomed, or a strip's) starts over
        if f.width > 800 || f.height > 1200 || f.height < 380 { panel.setContentSize(panelSize) }

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
        strip.onClick = { [unowned self] in setMode(mode == .strip ? .single : .strip) }
        strip.onChevron = { [unowned self] in setMode(.panel) }
        strip.onStep = { [unowned self] d in cityIndex += d; syncPage() }
        strip.setAccessibilityElement(true)
        strip.setAccessibilityRole(.button)
        strip.setAccessibilityLabel("World Clock strip")
        panel.contentView!.addSubview(strip)

        let button = statusItem.button!
        button.image = NSImage(systemSymbolName: "clock", accessibilityDescription: "World Clock")
        button.target = self
        button.action = #selector(statusClicked)
        _ = button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        // Quit collapsed, come back collapsed. The panel keeps the frame restored above.
        if let m = Mode(rawValue: UserDefaults.standard.integer(forKey: "mode")), m != .panel { setMode(m, atLaunch: true) }
        panel.orderFrontRegardless()
    }

    // MARK: States

    func syncPage() { webView.evaluateJavaScript("window.wcState && wcState(\(mode.rawValue), \(cityIndex))") }

    func setMode(_ m: Mode, atLaunch: Bool = false) {
        // Read the geometry first; the style changes below can nudge the frame.
        let screen = panel.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? panel.frame
        let rightSide = panel.frame.midX > visible.midX   // which side of its screen the panel lives on
        let top = panel.frame.maxY
        if mode == .panel, m != .panel, !atLaunch { UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: "expandedFrame") }
        if m == .single, mode != .single { cityIndex = 0 }   // the single time starts on home
        mode = m
        UserDefaults.standard.set(m.rawValue, forKey: "mode")
        let full = m == .panel
        panel.titleVisibility = full ? .visible : .hidden
        panel.titlebarAppearsTransparent = !full
        if full { panel.styleMask.remove(.fullSizeContentView) } else { panel.styleMask.insert(.fullSizeContentView) }
        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton] { panel.standardWindowButton(kind)?.isHidden = !full }
        strip.isHidden = full
        strip.chevronWidth = m == .strip ? 36 : 0
        var size = sizes[m] ?? panelSize
        if full {
            let saved = UserDefaults.standard.string(forKey: "expandedFrame").map(NSRectFromString)?.size ?? panelSize
            size = NSSize(width: min(max(saved.width, 280), 800), height: min(max(saved.height, 380), 1200))
        }
        panel.minSize = full ? NSSize(width: 280, height: 380) : size
        panel.maxSize = full ? NSSize(width: 4000, height: 4000) : NSSize(width: 600, height: size.height)
        syncPage()

        // Strip and single tuck against the nearer side of the screen, at the same height. The
        // panel opens back from that side, so a strip on the right expands leftwards.
        var frame = NSRect(x: 0, y: top - size.height, width: size.width, height: size.height)
        if full {
            frame.origin.x = rightSide ? panel.frame.maxX - size.width : panel.frame.minX
        } else {
            frame.origin.x = rightSide ? visible.maxX - size.width : visible.minX
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

    @objc func pickMode(_ sender: NSMenuItem) { setMode(Mode(rawValue: sender.tag)!); panel.makeKeyAndOrderFront(nil) }

    func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: panel.isVisible ? "Hide World Clock" : "Show World Clock", action: #selector(toggle), keyEquivalent: "")
        menu.addItem(.separator())
        for (title, m) in [("Full Panel", Mode.panel), ("Strip", .strip), ("One Time", .single)] {
            let item = menu.addItem(withTitle: title, action: #selector(pickMode), keyEquivalent: "")
            item.tag = m.rawValue
            item.state = m == mode ? .on : .off
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Reload", action: #selector(reload), keyEquivalent: "")
        menu.addItem(withTitle: "Open Full Page in Browser", action: #selector(openInBrowser), keyEquivalent: "")
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

    // MARK: Window and web view

    /// The close button only hides the panel; the menu bar clock brings it back. Quit is in the menu.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        panel.orderOut(nil)
        return false
    }

    /// After every load (first launch, Reload), put the page in whichever state the panel is in.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { syncPage() }

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
