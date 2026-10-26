# World Clock for the Mac

A small floating panel that keeps the World Clock on top of whatever you are working in. It is the
web app's compact view (`?mini=1`) inside a native window, so it is always the same code as the
site: the city list, the time projector and the typed time all work exactly as they do in the
browser, and the city list is kept inside the app between launches.

Three states, smallest last:

- **Panel.** The full compact page, 340 by 560 by default, resizable.
- **Strip.** One row, 40 points tall: your home time and the top two cities, flag and time, with
  a chevron at each end. It tucks against the nearer side of whichever screen it is on.
- **One time.** A single flag and time, your home city to start, with one chevron. Scroll over
  it (trackpad or mouse wheel) to step through your other cities, one per swipe or notch.

Moving between them: the yellow button (or a double-click on the title bar) collapses the panel to
the strip. On the strip, the down chevron at the right opens the panel; the inward chevron at the
left, or a click on the times, goes to the one time. On the one time, its chevron, or a click,
goes back to the strip. Drag either to move it. The red button
hides the panel; the clock in the menu bar brings it back, and its right-click menu can jump to
any of the three states. Quit is in that menu too.

## Build

Needs macOS 13 or newer and the Xcode Command Line Tools, which you get once with:

```bash
xcode-select --install
```

Then, from the repo root:

```bash
bash mac/build.sh
```

That compiles `mac/WorldClock.swift` with `swiftc`, builds the icon from `mac/icon.svg` and writes
`mac/World Clock.app`. No Xcode, no package manager, no network. About ten seconds.

## Install

Drag `mac/World Clock.app` into `/Applications` and open it. A clock appears in the menu bar and
the panel opens. From then on:

| You want | Do |
|---|---|
| Show or hide the panel | Left-click the menu bar clock |
| Collapse to the strip | Yellow button, or double-click the title bar |
| Expand the strip | Click it |
| Move the strip | Drag it |
| Start it with your Mac | Right-click the menu bar clock, **Launch at Login** |
| The full page with weather | Right-click the clock, **Open Full Page in Browser** |
| Quit | Right-click the clock, **Quit World Clock** |

## It is unsigned: opening it the first time

The app is not signed with an Apple developer identity and not notarised. What that means in
practice:

- **Built on your own Mac** with `build.sh`: it opens with a double-click. macOS only quarantines
  files that arrived from elsewhere.
- **Received from someone else** (a zip, AirDrop, a download): macOS will refuse to open it.
  Right-click the app, choose **Open**, and if macOS still refuses, go to **System Settings >
  Privacy & Security** and click **Open Anyway** next to the message about World Clock. The
  command-line equivalent is:

  ```bash
  xattr -dr com.apple.quarantine "/Applications/World Clock.app"
  ```

Nothing in the app phones home. It loads one URL, `https://www.estebangz.com/world-clock/?mini=1`,
and opens any link you click in your default browser.

## Where it keeps things

- Position, size and expanded-or-strip state: `defaults` under `com.estebangz.worldclock`.
- The page's own storage (cities, theme, settings): the app's WebKit container in
  `~/Library/WebKit/com.estebangz.worldclock`, separate from Safari.

## Developing

Point the panel at a local copy instead of the live site:

```bash
python3 -m http.server 8766 --bind 127.0.0.1
```

```bash
defaults write com.estebangz.worldclock url "http://127.0.0.1:8766/?mini=1"
```

Relaunch the app. `defaults delete com.estebangz.worldclock url` returns it to the live site.

The strip is drawn by a short script the app injects into the page (see `stripScript` in
`WorldClock.swift`). It reads the page's own `home`, `cities` and `fmtHMS`, so `index.html` needs
no Mac-specific code. If those names ever change in `index.html`, update the script.

## Route B: a real desktop widget, and what it would cost

This panel is "Route A" from `PLAN.md`. Route B is a WidgetKit widget: the kind that sits on the
desktop or in Notification Centre, with no window at all.

What it would add: a glanceable set of times on the desktop and in Notification Centre, sized by
the system, surviving Stage Manager and Mission Control without being a window.

What it would cost:

- **Xcode.** WidgetKit extensions cannot be built with the Command Line Tools. Xcode is a large
  download and, on a managed Mac, may need IT approval.
- **A host app.** A widget is an extension; it has to ship inside an app, so there would be an
  Xcode project with two targets to maintain next to this single file.
- **Signing.** Widgets only load reliably when the host app is signed. A free Apple ID gives a
  signature that expires after seven days; a lasting install needs a paid developer account.
- **Less interaction, by design.** Widgets render snapshots on a timeline. They can show the
  times, and buttons can step a value, but there is no typing a time and no text input. The
  projector would stay in this panel or in the browser.

Rough size: one to two days once Xcode is installed, most of it the timeline and the signing.
Worth doing only once the strip here has shown what a glance view should contain.
