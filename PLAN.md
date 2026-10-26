# World Clock, the plan (October 2026)

A small tool I use every day and keep forgetting where it lives. This plan fixes that first,
then takes it to the three places I actually look: the browser, a small floating window next to
Teams and Outlook, and the Mac itself.

## How it gets used, day to day

1. **The link.** `estebangz.com/world-clock/` is the address. The site proxies this repo's GitHub
   Pages build, so this repo stays the single source of truth and every merge to `main` is live on
   both addresses with nothing to deploy on the site side.
2. **The floating window.** From the full page, "Float" opens a 340 by 560 always-on-top window
   (Chrome and Edge use the Document Picture-in-Picture window; anything else gets a plain popup).
   It shows home time, the time projector and the city list, nothing else. Type a time, read it
   everywhere, copy the share string. It follows the full page's setup through local storage, so
   adding a city in one updates the other.
3. **The Mac.** A native panel or widget that shows the same `?mini=1` view without a browser tab.
   Sprint 3 below.

## Ground rules

- One `index.html`, vanilla JS, no build step, no framework, no backend, no accounts.
- `?mini=1` is the only mode switch. Everything else is CSS on `body.mini`.
- A change that only matters in the floating window must not change the full page.
- Keep the original at `archive/world-clock-v1-original.html` untouched.

## Sprint 1, done in this branch: type the time, float the window

- Tap the hour or minute digits to type a time. Accepts `3pm`, `15:30`, `1430`, `9`. Enter sets
  it, Escape cancels, arrow keys nudge 5 minutes (Shift for an hour). The projection updates while
  typing. The stepper arrows still work and now repeat when held.
- A "Float" button in the header opens the floating window. Hidden under 700 px, where a popup is
  just another tab.
- `?mini=1` compact mode: no weather, no location prompt, no weather calls (fonts still load),
  one-column city rows first, projector after.
- Windows stay in sync through the `storage` event.
- Stepper taps on touch now register (the old touchstart handler cancelled the tap's click).

Done when: typed time round-trips on desktop Chrome and Safari and on iPhone Safari; the floating
window opens from the full page and shows the same cities; no console errors; the full page at
390 and 1440 wide looks the same as before this sprint apart from the new header button.

## Sprint 2, done in branch `sprint-2-a11y-experience`: accessibility and the experience pass

Measured first (Lighthouse accessibility 93 on every run, 65 to 76 axe contrast nodes, no Escape,
no focus trap, no keyboard reorder), then fixed by family. After: Lighthouse 100 on dark and light,
desktop and mobile; axe zero violations; every control 24 px or more; the text tokens retoned once
(`--mu`, `--fa`, light `--ac`, new `--onAc`) rather than per use; picker, modal and dropdown are
dialogs with a focus trap, Escape and focus return; move up and down buttons in edit mode; a
first-run card; "Use my location" instead of a prompt on load; `sw.js` caches the shell for offline;
zones missing from `TZ_AB` now show their GMT offset instead of "Buenos_Aires". The share string is
byte-identical for every zone in `TZ_AB`. Numbers and screenshots are in the PR.

The original brief, kept for the record:

Measure first, then fix the families, not the instances.

**Baseline to capture before touching anything:** Lighthouse accessibility score, axe-core
findings, a VoiceOver walk of the core flow (pick a time, pick a city, copy), keyboard-only walk,
and screenshots at 390, 768 and 1440 in both themes.

**Accessibility targets (WCAG 2.2 AA):**
- Every control named. The city chips, flip button, stepper arrows and copy buttons need labels a
  screen reader can say out loud; icon-only buttons need `aria-label` plus a visible tooltip.
- Time changes announced once, through a polite live region, not on every keystroke.
- Target size 24 px minimum (2.5.8), hit areas on the stepper arrows and chip close buttons today
  are below that.
- Contrast: the `--fa` and `--mu` text tokens are likely under 4.5:1 on both themes. Measure, then
  re-tone the token rather than patching each use.
- Focus order follows reading order; the picker overlays trap focus while open and return it on
  close; Escape closes anything that opened.
- Drag to reorder gets a keyboard equivalent (move up and down in edit mode, 2.5.7).
- Reduced motion is already respected; add `prefers-contrast` and `forced-colors` checks.

**Experience pass (mobile and desktop):**
- Flatter, fewer layers. Remove a border or a background before softening one.
- Type scale and spacing on a real grid; headline on one line; no orphans or widows in copy.
- `text-wrap: balance` on headings, `dvh` for height, safe-area insets already in place.
- Offline: a small service worker (cache-first shell, no weather cache). The manifest already
  exists, so the installed app finally works on a plane.
- Geolocation becomes opt-in behind a "use my location" button.
- Empty state for first run that teaches the three moves in one screen.
- Keep external calls to fonts and weather only; both already fail soft.

Done when: Lighthouse accessibility 100, axe zero serious or critical, VoiceOver and keyboard walks
pass with notes, before and after screenshots side by side at all three widths, and the share
string output is byte-identical to before.

## Sprint 3: the Mac (own session)

Two routes, in the order to try them.

**Route A, recommended first: a floating native panel, no Xcode needed.** One Swift file compiled
with `swiftc` from the Command Line Tools already on this Mac. An `NSPanel` set to float above
other windows and never steal focus, holding a `WKWebView` that loads
`https://www.estebangz.com/world-clock/?mini=1`. A menu bar item toggles it, it remembers its
position and size, and it can launch at login. About 100 lines, installs by dragging to
Applications. This is the "widget" for daily use: it is always there, it is interactive, and it is
the same code as the web.

**Route B, later if wanted: a real WidgetKit desktop widget.** Needs Xcode (not installed here,
large download, may need IT approval on a managed Mac) and a host app to carry the extension.
Widgets render static snapshots on a timeline, so they can show the times but not take a typed
time; interaction is limited to buttons and toggles. Good for a glance, not for planning. Build it
only after Route A has proven what the glance view should show.

Done when: Route A runs on this Mac from a fresh clone with one command, survives a reboot, and a
screenshot shows it floating over Teams with the typed time working.

## Not doing

Accounts, a backend, analytics, a framework, a design system port. The tool is small on purpose.
