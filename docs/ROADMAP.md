# Roadmap: AINCRAD as a full shell

AINCRAD started as a launcher. The long-term goal is bigger: a complete **shell replacement**
for macOS, where everything you'd normally do through the menu bar, Control Center, System
Settings, the Dock, Spotlight and a handful of small apps happens through SAO-style quick menus
instead.

This is a plan, not a promise. Nothing below is built yet unless it says so. Each area has a
note on how it could work. macOS draws hard lines around some of this, and the plan tries to
be honest about where they are.

**Legend:**
- 🟢 Public API, straightforward.
- 🟡 Possible, with caveats: needs a permission, uses AppleScript or Shortcuts, or behaves differently between macOS versions.
- 🔴 No supported way; private API or not possible.

---

## Principles

- **One gesture away.** Every quick menu opens from the launcher, the top bar or a hotkey, and
  closes as soon as it's used.
- **Native first.** Use Apple's frameworks where they exist. Fall back to Shortcuts or
  AppleScript, and only then to private APIs, and say which one a feature uses.
- **Nothing is taken away.** Apple's own UI stays one click away (Open in System Settings…), and
  turning AINCRAD off puts every system setting back the way it was.
- **Permissions on demand.** A feature asks for access the first time it's used, never at launch.
- **Themeable all the way down.** Every new panel reads the theme like the launcher does.

---

## 1. System quick menus (Control Center replacement)

A **System** circle with compact SAO panels for the things people change most.

| Control | Notes | |
|---|---|---|
| Volume, mute, output device | CoreAudio | 🟢 |
| Input device and level | CoreAudio | 🟢 |
| Display brightness | Built-in displays via a private DisplayServices call; external monitors over DDC | 🟡 |
| Dark / Light appearance | AppleScript to System Events, or a Shortcut | 🟡 |
| Night Shift, True Tone | Only private CoreBrightness; otherwise Shortcuts | 🔴/🟡 |
| Wi-Fi on/off, network list, join | CoreWLAN; joining may ask for the password through macOS | 🟢/🟡 |
| Bluetooth on/off, connect devices | IOBluetooth for devices; the power toggle is private | 🟡 |
| Focus modes | No public API for setting Focus; doable through Shortcuts ("Set Focus") | 🟡 |
| Battery and power source | IOKit power sources | 🟢 |
| Low Power Mode | `pmset` needs admin; Shortcuts on recent macOS | 🟡 |
| Keyboard brightness | Private | 🔴 |
| AirDrop, Screen Mirroring | Open the system panel; no API to drive them | 🔴 |
| Caffeinate / keep awake | IOKit power assertions | 🟢 |
| Lock, sleep, restart, shut down, log out | Already partly built (lock); the rest via AppleScript to System Events | 🟢/🟡 |

## 2. Settings, the AINCRAD way

A searchable **Settings** menu where common options are changed in place, and everything else
deep-links to the right System Settings page.

- **Direct toggles** for settings that are plain preferences: Dock and menu bar auto-hide (built),
  key repeat, natural scrolling, tap to click, hot corners, show file extensions, screenshot
  location and format. 🟡 These are `defaults` keys; some need a relaunch of the app they belong to.
- **Deep links** to every System Settings pane and many sub-sections (`x-apple.systempreferences:`
  URLs). 🟢 Started: the *Settings Panes* extension.
- **Profiles**: save a set of settings (Gaming, Work, Presenting) and switch in one click.
  It would combine Focus (via Shortcuts), Dock/menu bar, audio output, wallpaper and which
  widgets show. 🟡
- **Wallpaper**: set per display from a menu, including AINCRAD-themed ones. 🟢 (NSWorkspace)

## 3. Productivity

| Feature | Notes | |
|---|---|---|
| **New reminder** from the launcher (type, pick list and due time) | EventKit, same access as the quest log | 🟢 |
| **Complete / snooze reminders** from the quest log | EventKit | 🟢 |
| **New calendar event** ("lunch tomorrow 1pm") with natural-language dates | EventKit + NSDataDetector | 🟢 |
| **Quick notes**: an SAO notepad panel, saved as Markdown in a folder you choose | Own storage | 🟢 |
| Send a quick note to Apple Notes | AppleScript to Notes | 🟡 |
| Timers, stopwatch, alarms | Own implementation; a timer exists | 🟢 |
| Clipboard history | Built (Command Center) | 🟢 |
| Snippets / text expansion | Needs Accessibility to type into other apps | 🟡 |
| Translate / define selected text | Dictionary services; Translation framework on recent macOS | 🟡 |

## 4. Files

- **Recent files**, **Downloads** and **Desktop** as live submenus. 🟢 (Spotlight queries)
- **File actions** from the right-click menu: compress, move to a folder, rename, Quick Look. 🟢
- **Search** across files: built (Spotlight); add filters (kind, date, folder). 🟢
- **Trash**: show size, empty with confirmation. 🟡 (Finder AppleScript)
- **Mounted drives** with eject. 🟢

## 5. Windows and Spaces

- **Window switcher**: every window of every app, with titles, in an SAO list. 🟡 Accessibility
  (window lists already work in the dock).
- **Tiling layouts**: halves, thirds and grids, plus saved layouts per display. 🟡 Accessibility
  (basic left/right/max is built).
- **Workspaces**: built (apps + window positions).
- **Spaces**: list and switch. 🔴 No public API; switching works by sending Mission Control's
  shortcuts, and creating or removing Spaces isn't possible.

## 6. Apps

- **App switcher** replacement for ⌘-Tab. 🟡 Needs Accessibility, and a global key-event tap
  to take over ⌘-Tab.
- **Quit / force quit** manager with memory and CPU per app. 🟢 Party-panel idea.
- **App menus** from the top bar: built.
- **Login items**: list and toggle. 🟡 Only AINCRAD's own via SMAppService; others through
  System Settings.

## 7. Notifications

- **SAO notification bubbles**: built (needs Accessibility to mirror banners).
- **Notification log**: a history panel of everything that came in. 🟡 It can only record what
  it mirrors while running.
- **Do Not Disturb toggle**: see Focus above. 🟡

## 8. Media

- **Now playing** with controls for Music and Spotify. 🟡 AppleScript per app. A universal
  now-playing view needs the private MediaRemote framework, which recent macOS restricts. 🔴
- **AirPlay output** switch. 🟡 Through CoreAudio devices where they show up.

## 9. Power user

- **Run Shortcuts** from any menu: built.
- **Terminal commands** as menu items: built (off by default).
- **Script blocks** that can call any of the above, so extensions can build their own quick menus.

---

## Phases

1. **System panel**: audio, Wi-Fi, battery, caffeinate, appearance, power actions.
   Mostly 🟢, and it's the biggest daily-use win.
2. **Productivity**: new reminder and event, complete or snooze from the quest log, the quick
   notes panel.
3. **Settings menu**: direct toggles, deep links and profiles.
4. **Windows**: switcher and layouts.
5. **Files and media**.
6. **Replacing ⌘-Tab and Spotlight's hotkey**: optional, opt-in, and only once everything above
   feels solid.

Ideas and votes are welcome as [feature requests](../.github/ISSUE_TEMPLATE/feature_request.md).
