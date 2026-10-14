# AINCRAD

A native macOS launcher in the style of Sword Art Online's floating system menu, with the
customisation depth of SAO Utils 2: Progressive: a cascading SAO menu, desktop widgets with a
visual editor, a theme engine, declarative extensions, and a local productivity command center. Built in Swift with AppKit and Core
Animation (SwiftUI for the settings window only). No web views and no third-party dependencies.

Unofficial fan project, not affiliated with the Sword Art Online rights holders. The bundled
sounds, icon and font choice are original or system-provided.

## Build & install

Requirements: macOS 14+, Xcode 16, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
./scripts/build.sh               # Release build → /Applications/AINCRAD.app
./scripts/test.sh                # 68 unit tests
./scripts/measure_idle.sh 300    # sample the running app's idle CPU/memory for 5 min
swift scripts/make_sounds.swift AINCRAD/Resources/Sounds   # regenerate the sounds
swift scripts/make_icon.swift AINCRAD/Assets.xcassets      # regenerate the app icon
```

`project.yml` is the source of truth for targets and build settings. `xcodegen generate`
recreates `AINCRAD.xcodeproj` from it, and the scripts do this for you. Source files can be
edited freely in Xcode, and new files dropped into `AINCRAD/` are picked up on the next generate.

Build output goes to `~/Library/Caches/AINCRAD-build`, **not** the project folder. `~/Documents`
is in iCloud Drive here, and iCloud's file attributes make `codesign` fail (it would also upload
the build products).

**Signing.** The project signs with the local *Apple Development* certificate (team
`UWC6NUWUHW`), so the app's identity stays stable across rebuilds. macOS ties the Accessibility
grant (needed for the mouse gesture) to that identity; an ad-hoc signed app would lose the grant
on every rebuild. The app runs on this Mac but isn't notarised for distribution. To build on
another Mac, change `DEVELOPMENT_TEAM` in `project.yml`, or use `CODE_SIGN_IDENTITY: "-"`.

## Use

Open `/Applications/AINCRAD.app` (opening it again shows Settings). A ◎ icon appears in the
menu bar; there's no Dock icon.

* **⌥`** opens the menu at the pointer. With the gesture on, so does holding both mouse buttons
  and sliding down.
* Menu bar icon → **Settings…** configures everything: shortcut, gesture, menu, themes,
  widgets, extensions, per-display accents, login item.

Docs: [configuration & menu](docs/CONFIGURATION.md) · [themes](docs/THEMES.md) ·
[widgets](docs/WIDGETS.md) · [extensions](docs/EXTENSIONS.md) · [performance](PERFORMANCE.md)

## Project layout

```
AINCRAD/App          main, AppDelegate (menu bar, activation, URL scheme), LaunchGuard (safe mode)
AINCRAD/Config       settings/menu/theme models, tolerant JSON, MenuTree edits, store, recents
AINCRAD/Input        Carbon hotkeys, item shortcuts, GestureRecognizer (pure) + GestureMonitor (event tap)
AINCRAD/Launcher     panel, MenuView (layers + input), InfoPanel, Motion (animation system),
                     MenuLayout (pure geometry), IconCache, ActionRunner, controller
AINCRAD/Widgets      model, DataHub (system readings), renderers, window/editor, manager
AINCRAD/Extensions   manifest, validation, permissions, contributions
AINCRAD/Scripts      block language (Blocks), interpreter (ScriptEngine), events (ScriptRuntime), ScriptTree edits, message pop-up
AINCRAD/Studio       Extension Studio window and block views
AINCRAD/Settings     SwiftUI settings: General, Menu, Themes, Widgets, Extensions, Browse, About
AINCRAD/Support      logging, colours, sounds, frame probe
AINCRADTests         68 unit tests
```

Design rules: rendering reads every visual value from `Theme` (the SAO look is just the default
data). Animation timing is decided only in `Motion`. Nothing runs on a timer unless something
visible needs it.

## Feature checklist

✅ working, tested as described · 🟡 built, partly tested or untested · ⬜ not built

**Launcher**
- ✅ Menu bar utility; Pause / Quit / Settings / Theme / Reduce Motion / Sounds / Widgets in its menu
- ✅ Global shortcut (no permissions; real key presses tested), recorder in Settings, conflicts reported
- ✅ SAO cascading menu: root buttons, columns aligned to the selection, info panel, pointers, glow
- ✅ Mouse hover, click, scroll, right-click back; keyboard arrows, Return, Esc (real input tested)
- 🟡 Type-ahead letters (built, not exercised)
- ✅ Opens on the display under the pointer, clamped on-screen, shifts left when columns overflow (both displays tested)
- ✅ Launching apps (tested). 🟡 files/folders, URLs, Shortcuts, shell, builtins (built; parsing unit-tested)
- ✅ Dynamic lists: all applications, recent apps, extension menus (unit-tested)
- 🟡 Visibility conditions, per-item accent, per-item global shortcuts (built; not exercised live)
- 🟡 Doesn't steal focus; shows over full-screen apps and on all Spaces (full-screen not tried)

**Mouse gesture**
- ✅ Gesture state machine: 9 unit tests (chords in both orders, replayed right-clicks, directions, timing)
- 🟡 Live event tap: built, but **not run**. It needs you to grant Accessibility (see Known limitations)

**Look & motion**
- ✅ Classic (white/orange) and Dark themes; tilt, glow, per-display accent (screenshots)
- 🟡 High-contrast adaptation (built, not tried with Increase contrast on)
- ✅ Animation system: 4 presets, speed, per-step durations, Reduce Motion
- ✅ Original sounds (6), per-event choice, volume, mute; app icon

**Customisation**
- ✅ Menu editor: add, duplicate, delete, move, indent, outdent, inspector, undo/redo, import/export, preview (core unit-tested; add + undo clicked live)
- ✅ Theme editor: every value, undo/redo, duplicate/import/export/delete (unit-tested), preview
- ✅ Backups before every save; broken files reported, never overwritten

**Widgets**
- ✅ Clock, stat (CPU/memory/disk/battery/network/uptime as bar/ring/text), SAO HP bars, text, image, app shortcut, launcher button (rendered on the desktop)
- ✅ Desktop editor: select, move, resize (tested live); rotate, nudge, delete, inspector, undo/redo, named layouts (built)
- ✅ Per-display layouts; sampling pauses when covered (logged)
- ✅ HUD widgets: any widget can live in the HUD (shown above the launcher on its display, sliding in from the edge); HUD opacity slider + per-widget opacity; starter set (clock, CPU/MEM/disk, network) (screenshots)
- 🟡 Quest log widget: today's calendar events + due reminders, next event as Floor Boss with a countdown bar (access + empty state seen; not yet seen with real events)
- 🟡 Display disconnect/reconnect, display sleep pause (code paths exist; not tested)

**Extension Studio & catalog**
- ✅ Scratch-style block language: 45 blocks in 7 categories, interpreter with step/time/loop limits and permission checks (16 unit tests)
- ✅ Studio window: palette, drag-and-drop canvas, nested reporters, ▶ test with console, undo/redo (drag/drop, nesting and test run done with real mouse input)
- ✅ Basics / Looks / Menus / Widgets / Publish sections; `.aincrad` export; double-click install with archive safety checks
- ✅ Browse tab: catalog with previews, SHA-256-verified one-click install (theme and extension installed from it; gauge widget fed live by a block script)
- ✅ Catalog published at github.com/djag1337/AINCRAD-catalog (local copy in `~/Documents/AINCRAD-catalog`): 6 themes, 5 block extensions, build tool; Browse uses it by default

**Everyday features**
- ✅ Launcher Shell: full-width SAO top bar over the menu bar (player HP/LV, active app, CPU/MEM/BAT, clock; centre left clear for notch apps) and an SAO dock (glass circles, hover lift + name tag, running dots, pinned/running divider), each in its own non-key panel so clicks don't close the menu (screenshots; hover/click not yet exercised live)
- ✅ Hide Apple's Dock / menu bar completely while AINCRAD runs (originals saved and restored on quit); confirmed by user
- ✅ App menus in the SAO top bar: click the player block for the current app's real menus (Accessibility), submenus, shortcuts; commands run (confirmed by user)
- ✅ Independent session-only switches for auto-hiding the Apple menu bar and Dock while the launcher is open
- ✅ Command Center injected without changing the user's menu: context actions, local searchable clipboard history, Quick Capture inbox and workspace loadouts
- ✅ Typed commands in launcher search: `timer 25`, `note …`, `paste …`, `workspace …`, `window left/right/max`
- ✅ Text-selection actions through Accessibility: copy, capture, search, upper/lowercase; clipboard auto-paste returns to the previous app
- ✅ Workspace capture/restoration: running apps plus window positions and sizes when Accessibility is available
- ✅ Compact floating SAO target button on every Space; click to open AINCRAD, hover for active timer and clipboard status
- ✅ Window tiling, lock screen, volume controls, Sound and Bluetooth controls
- ✅ Local usage-ranked suggestions; productivity data stays in Application Support and common password managers are excluded from capture
- ✅ SAO HUD frame (corner brackets, player bar with HP/LV, clock) around the screen while the launcher is open (screenshots)
- ✅ Search: type in the launcher for apps, menu items, files (Spotlight), System Settings panes, math (Return copies) and web search (tested live)
- ✅ Context actions: right-click an item for Open, Show in Finder, Quit, Copy Path/Link, Add to/Remove from Favorites, Hide (SAO-styled, screenshot)
- ✅ Applications sorted into categories; tilt fixed for long lists
- ✅ Game shelf: Steam (every library), Heroic (GOG/Epic), Prism Launcher instances and game apps, as a Games menu and a cover-art widget (screenshots)
- ✅ Magic Mouse two-finger swipe (fired live, direction confirmed); hold right button and slide (unit-tested)
- 🟡 Notification bubbles: bubble UI tested; mirroring real banners needs Accessibility and a real notification (not yet seen live)
- ✅ Publish to catalog from the Studio and the theme editor (flow tested against a local git remote; not pushed for real)
- ✅ 16 preinstalled extensions (off until enabled; validated by a unit test), also in the catalog; enabled extensions' menus appear under Command Center › Extensions
- 🟡 Dock and launcher open apps like a Dock click (reopen event; un-minimizes via Accessibility if needed): built, not yet confirmed
- ✅ Install Font… in the theme editor; separate text and title fonts (default Rajdhani + Orbitron)

**Platform**
- ✅ Safe mode (⌥ at launch, or automatic after two quick crashes) and a clean quit on SIGTERM (tested)
- 🟡 Launch at login (toggle in Settings; not toggled in testing, since it changes your login items)
- 🟡 VoiceOver announcements (built; not tested with VoiceOver running)
- ✅ Extensions API v1: themes, menus, data sources, widget presets; validation, permissions and path-escape tests

## Known limitations

* **The mouse gesture hasn't been run live.** To try it: Settings › General › Mouse gesture →
  turn it on → approve AINCRAD in System Settings › Privacy & Security › Accessibility.
* While the gesture is on, right-clicks arrive about 90 ms late (adjustable); left clicks aren't affected.
* No shortcut works while a password field (secure input) is focused. This is a macOS rule.
* Your macOS desktop widgets (Notification Center) draw above AINCRAD widgets where they overlap.
* AINCRAD widgets that update cost the compositor a little CPU each time over an animated
  wallpaper. A clock with seconds measured about +2.7 points of WindowServer CPU; see PERFORMANCE.md.
* Long lists near the bottom of a screen extend below it (rows fade out); scroll or use the keys.
* Extensions are data-only by design. There's no built-in now-playing or weather widget; weather
  can come from an extension data source.
