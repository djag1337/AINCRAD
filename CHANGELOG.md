# Changelog

Notable changes to AINCRAD. Dates are when a change landed, not a formal release.

## Unreleased (0.2)

### Added
- **HUD widgets.** Any widget can live in the HUD, which slides in when the launcher opens.
  There's a HUD-wide opacity slider on top of each widget's own opacity, and a starter layout:
  clock, CPU/memory/disk, network and a quest log.
- **Quest log widget.** Today's calendar events and due reminders, with the next event as the
  *Floor Boss* and a countdown bar.
- **Shell top bar and dock.** An SAO bar over the menu bar, and a dock of your apps, shown with
  the launcher.
  - Click your name to get the current app's real menus.
  - Right-click the bar for your menu bar icons.
  - Right-click a dock app for its windows, Show in Finder, Hide and Quit.
- **Hide Apple's Dock and menu bar completely** while AINCRAD runs. Originals are saved and
  restored when you turn it off or quit.
- **16 preinstalled extensions**, also in the community catalog. Enabled extensions' menus
  appear under Command Center › Extensions.
- **AINCRAD Settings** button under the ⚙ circle.
- Separate title and text fonts in themes (Orbitron and Rajdhani by default, both bundled).

### Changed
- Opening an app from the dock or the launcher behaves like a Dock click: it unhides the app
  and restores a minimized window.
- The top bar names the app you were actually in, not a background helper.

### Fixed
- Right-click menus over tilted columns: the first row was half hidden and stray lines showed.
- Root captions like "Command Center" no longer get cut off.

## 0.1 (2026-10-13)

First working version.
- The cascading SAO launcher and its HUD frame.
- The theme engine and editor.
- Desktop widgets.
- The Extension Studio (blocks) and the community catalog.
- Spotlight-style search, context actions, the game shelf, notification bubbles, the Magic
  Mouse gesture and safe mode.
