# Changelog

Notable changes to AINCRAD. Dates are when a change landed, not a formal release.

## Unreleased (0.2)

### Added
- **System menu (roadmap phase 1).** A new launcher circle with Sound, Wi-Fi, Bluetooth,
  Display, Power and Battery quick menus, using Apple's own frameworks.
  - Wi-Fi network names, Bluetooth and appearance each ask macOS permission only when first used.
  - Restart, shut down and log out go through macOS's own confirmation.
- **Editable SAO dock.**
  - Its own list, edited in the dock itself: right-click to keep, remove or move; drag to
    reorder or off to remove; drop from Finder; Add to Dock from the launcher.
  - Folders open as SAO stacks with subfolder submenus and icons.
  - Theme-coloured folder icons.
- HUD widgets fade back while a menu column is over them.
- **HUD widgets.** Any widget can live in the HUD, which slides in when the launcher opens.
  There's a HUD-wide opacity slider on top of each widget's own opacity, and a starter layout:
  clock, CPU/memory/disk, network and a quest log.
- **Four more HUD widgets.**
  - **EXP bar:** levels earned by using the launcher and by active minutes.
  - **Party:** your busiest apps, with HP = CPU they leave free.
  - **Status effects:** Wi-Fi, battery, mute, keep-awake, load and disk.
  - **Battle log:** apps joining and leaving, launcher choices and bubbles.
- Desktop widgets fade while the launcher is open (can be turned off), and HUD widgets show a
  "HUD" tag in edit mode.
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
- **Opening the launcher is about 4× faster** than earlier today: 7.5–13 ms (median 8.4), down
  from 37–39 ms. The animation is smoother too. See docs/PERFORMANCE.md.
- Opening an app from the dock or the launcher behaves like a Dock click: it unhides the app
  and restores a minimized window.
- The top bar names the app you were actually in, not a background helper.

### Fixed
- Clicking outside an open dock or top-bar menu closed the whole launcher.
- The menu-bar icon list took about 1 s to appear. It's now read ahead and shows instantly.
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
