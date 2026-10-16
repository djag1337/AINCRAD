# Changelog

Notable changes to AINCRAD. Dates are when a change landed, not a formal release.

## Unreleased (0.2)

### Added
- The launcher's **Web** circle is now AINCRAD Browser's home: New Tab, Open Tabs, Bookmark Current Page, Bookmarks, History and New Private Window sit above your own links (it used to be under Files).
- **Settings redesigned** as a native-style window: a vertical sidebar of icons (General, Menu, Themes, Widgets, Extensions, Browse, Quick Commands, Browser, About) and a clip-art AINCRAD logo, in your theme's accent, at the top right.
- **Settings › Browser**: opt in to AINCRAD Browser (installs from its GitHub release after you approve), the link switches, and the browser's whole settings page (search engine, ad/tracker blocking, https upgrades, reader mode, dark pages, custom CSS, start page…).
- **AINCRAD Browser link**: the Web circle lists the browser's open tabs (click to switch),
  bookmarks and history; web links open in it; its downloads become SAO bubbles; theme changes
  reach it instantly. Two switches in Settings › General. No permissions; private windows never shared.
- **Quick commands** in the launcher search: `remind`, `event`, `note`, `applenote`, `contact`,
  `message`, `mail`, `facetime`, `play`/`next`, `volume`, `dark`/`light`, `define`.
  - **Each has a switch** in the new Settings › Quick Commands tab.
  - **Every one needing a permission is off by default.**
  - Messages and mail open as drafts, never sent for you.
  - A new `docs/PERMISSIONS.md` lists every permission AINCRAD can ask for.
- **Opt-in system shortcuts (roadmap phase 6).**
  - ⌘-Tab opens an SAO app switcher, using an event tap like other app switchers do.
  - ⌘-Space opens the launcher.
  - Both are off until you turn them on in Settings › General.
- **Files and media (roadmap phase 5).** A new Files circle:
  - Recent Files, Downloads, Drives (with Eject) and Trash.
  - Now Playing for Music and Spotify.
  - Found files get Quick Look, Compress and Move to Trash on right-click.
- **Windows (roadmap phase 4).** Command Center › Windows has three parts:
  - **Switch To:** any window in any app.
  - **Arrange Window:** 18 layouts for the window you were using; also typed as `window left`
    and so on in the launcher.
  - **Workspaces.**
- **Mac settings in the launcher (roadmap phase 3).**
  - System › Mac Settings changes 33 macOS settings in place: Dock, Finder, Mission Control,
    hot corners, keyboard and trackpad, screenshots, accent colour. Ones AINCRAD manages show a lock.
  - System › Profiles saves your setup under a name and switches it in one click.
  - System › All Settings Pages links to 39 System Settings pages.
- **Productivity (roadmap phase 2).**
  - **Reminders and events from plain words:** type `remind call mom tomorrow 5pm` or
    `event lunch friday 1pm` in the launcher, or use Command Center › Quests (an SAO input box
    that previews the date it understood).
  - **Quest actions:** click a quest in the quest log to complete it, snooze it, or open it.
    Completing one earns EXP.
  - **Quick notes:** an SAO notepad from Command Center › Notes, saved as Markdown in
    `~/AINCRAD Notes`.
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
- **Notification bubbles cleared your notifications everywhere.** "Hide the original" pressed the
  macOS banner's Close button, which dismisses the notification itself: it left Notification Center
  and, for synced apps, your iPhone. AINCRAD now never closes or clears a notification.
  - The option is now **Cover the macOS banner**: the bubble is drawn over the banner instead.
  - It's off by default.
- Tiling from the launcher arranged nothing: it targeted AINCRAD itself (frontmost while the
  launcher is open) and always the main display. It now arranges the window you came from, on
  its own display.
- HUD widgets showed stale content (the quest log, the EXP bar) after the speed-up that keeps
  their windows between opens. They now redraw whenever they appear.
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
