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

> **Built (Oct 15):** a **System** circle in the launcher with Sound (volume, mute, output and
> input devices), Wi-Fi (on/off, networks, join known networks), Bluetooth (paired devices,
> connect/disconnect), Display (light/dark), Power (keep awake, lock, sleep, log out/restart/shut
> down through macOS's own confirmation) and Battery (when present). Brightness for external
> displays (DDC), Night Shift, Focus and Low Power Mode aren't in it yet.

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

> **Built (Oct 15):** System › Mac Settings changes 33 settings in place (Dock & Menu Bar,
> Finder & Desktop, Mission Control, Hot Corners, Keyboard & Trackpad, Screenshots, plus accent
> colour and scroll bars under Display), using the same preference keys System Settings writes.
> System › Profiles saves and switches named setups. System › All Settings Pages links to 39
> System Settings pages for the rest.

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

> **Built (Oct 15):** reminders and events from plain words. Type `remind …` / `event …` in the
> launcher, or use Command Center › Quests › New Reminder… / New Event…, an SAO input box that
> previews the date it understood. Click a quest in the quest log (or use Command Center › Quests)
> to complete it, snooze it an hour or until tomorrow, or open it. Quick notes: Command Center ›
> Notes opens an SAO notepad that saves Markdown to `~/AINCRAD Notes`.

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

> **Built (Oct 15):** a Files circle with Recent Files, Downloads (both from Spotlight, no
> folder-access prompts), Drives (free space, Eject) and Trash (open, empty with a confirmation).
> Right-click a found file for Quick Look, Compress and Move to Trash.

- **Recent files**, **Downloads** and **Desktop** as live submenus. 🟢 (Spotlight queries)
- **File actions** from the right-click menu: compress, move to a folder, rename, Quick Look. 🟢
- **Search** across files: built (Spotlight); add filters (kind, date, folder). 🟢
- **Trash**: show size, empty with confirmation. 🟡 (Finder AppleScript)
- **Mounted drives** with eject. 🟢

## 5. Windows and Spaces

> **Built (Oct 15):** Command Center › Windows has three parts.
> - **Switch To:** every window in every app, minimized ones included.
> - **Arrange Window:** 18 layouts (halves, thirds, two-thirds, quarters, maximize, almost
>   maximize, center, next display, restore) for the window you were using.
> - **Workspaces.**
>
> You can also type `window left`, `window top right` and so on in the launcher. Spaces stay 🔴.

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

> **Built (Oct 15):** Files › Now Playing for Music and Spotify: the current track, Play/Pause,
> Next and Previous. It only talks to a player that's already running, and asks macOS once per app.

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
