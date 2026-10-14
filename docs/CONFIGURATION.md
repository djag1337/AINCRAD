# AINCRAD configuration

Everything can be changed in **Settings** (menu bar icon → Settings…, or ⌘, while AINCRAD is
frontmost). Underneath, all configuration is human-readable JSON in
`~/Library/Application Support/AINCRAD/`:

```
AINCRAD/
  settings.json        general settings
  menu.json            the launcher menu tree
  widgets.json         desktop widgets (see WIDGETS.md)
  themes/              one file per theme (see THEMES.md)
  layouts/             named widget layouts
  Extensions/          extension folders (see EXTENSIONS.md)
  recents.json         recently used apps (for the Recent menu)
  backups/             previous versions, written before every save from Settings (newest 15 kept)
  logs/aincrad.log     activity, timings, errors (reset past 1 MB)
```

AINCRAD writes these files the first time it runs, and **never overwrites a file you edited by
hand**. If a file can't be parsed, AINCRAD carries on with defaults and shows the error under ⚠︎
in the menu bar menu, including where in the file it is. Fix the file, then choose **Reload
Configuration** (⌘R in that menu). You can leave out any key; missing keys use their defaults.

## settings.json

| Key | Default | Meaning |
|---|---|---|
| `hotKey` | `{"key": "`", "modifiers": ["option"]}` | Keys: `a`–`z`, `0`–`9`, `space`, `return`, `tab`, `escape`, `` ` ``, `f1`–`f12`. Modifiers: `control`, `option`, `shift`, `command` |
| `gesture.enabled` | `false` | hold both mouse buttons and slide (needs Accessibility, see below) |
| `gesture.slide` | `"down"` | `down`, `up`, `left`, `right`, `any`, or `none` (open on the two-button press alone) |
| `gesture.distance` | `40` | how far to slide, in points |
| `gesture.chordWindowMs` | `90` | how long a right press waits for the left button before being delivered as a normal right-click |
| `gesture.maxSlideMs` | `1200` | a slide slower than this doesn't count |
| `gesture.activationDelayMs` | `0` | wait after the gesture before opening |
| `gesture.disableInFullScreen` | `true` | ignore the gesture while a full-screen app or game is in front |
| `gesture.excludedApps` | `[]` | bundle ids where the gesture is ignored |
| `placement` | `"cursor"` | `cursor`, `gestureStart`, or `center` (centre of the display) |
| `theme` | `"aincrad-classic"` | theme file name in `themes/` |
| `reducedMotion` | `"system"` | `system`, `on`, `off` |
| `soundsEnabled` | `true` | |
| `activationPaused` | `false` | turns off the shortcut, item shortcuts and the gesture |
| `allowShellCommands` | `false` | must be on before `shell` menu actions run |
| `launchAtLogin` | `false` | set from Settings › General (uses macOS Login Items) |
| `widgetsEnabled` | `true` | show the desktop widgets |
| `displayAccents` | `{}` | accent colour per display, e.g. `{"Sceptre F22": "#3FA9F5", "Q27B13": "#E0303A"}` |
| `extensions` | `{}` | which extensions you've enabled, and the permissions you approved |

### The mouse gesture and permissions

The keyboard shortcut needs no permissions. The gesture needs **Accessibility** access
(System Settings › Privacy & Security › Accessibility). Without it AINCRAD can't hold back a
right-click while it waits to see whether a gesture is starting. Turning the gesture on shows
the macOS prompt, and the gesture starts as soon as you grant access.

How it treats your clicks:

* Left clicks are never delayed or changed.
* A right press waits up to `chordWindowMs` (90 ms by default) for the left button. If the left
  button doesn't come, the right-click is delivered unchanged, just that much later.
* Press right then left, or left then right in quick succession, and slide. Neither press
  reaches the app underneath, except a left press that came first: the app already received it,
  so it also gets the release.
* While the launcher is open, in excluded apps, and (by default) in full-screen apps and games,
  the gesture stands aside completely.

## menu.json

```json
{
  "root": [
    { "name": "Favorites", "icon": "sf:star.fill", "children": [
        { "name": "Safari", "action": { "type": "app", "target": "com.apple.Safari" }, "shortcut": "option+shift+s" },
        { "name": "Projects", "action": { "type": "open", "target": "~/Documents/Projects" },
          "description": "Everything I'm working on" }
    ]},
    { "name": "Applications", "icon": "sf:square.grid.3x3.fill", "provider": "applications" },
    { "name": "Steam", "action": { "type": "app", "target": "com.valvesoftware.steam" },
      "visibleWhen": { "appInstalled": "com.valvesoftware.steam", "display": "Q27B13" } }
  ]
}
```

Root items are the round buttons; deeper levels are columns of panels. Settings › Menu edits all
of this with undo/redo, import/export, and a Preview button.

### Item fields

| Field | Meaning |
|---|---|
| `name` | label (required) |
| `icon` | `sf:<SF Symbol>`, `app:<path>`, `file:<path>`, `image:<png/jpg/icns path>`. Omitted: apps and files show their Finder icon |
| `action` | what choosing it does (below) |
| `children` | a submenu |
| `provider` | a list filled when it opens: `applications`, `recentApps`, or `ext:<extension id>/<menu id>` |
| `description` | text for the info panel; otherwise it describes the action |
| `shortcut` | global shortcut that runs the item without opening the launcher, e.g. `"option+shift+1"`, or `"f6"` on its own |
| `accent` | per-item highlight colour, e.g. `"#3FA9F5"` |
| `hidden` | `true` hides it without deleting |
| `visibleWhen` | conditions, all of which must hold: `display` (display name), `appRunning`, `appNotRunning`, `appInstalled` (bundle ids) |
| `id` | stable identifier, generated if omitted |

### Actions

| `type` | `target` | Effect |
|---|---|---|
| `app` | `.app` path or bundle id | launch, or bring to the front |
| `open` | file or folder (`~` allowed) | open with its default app |
| `url` | any URL (`https://`, `mailto:`, app schemes) | open it |
| `shortcut` | name of a shortcut in the Shortcuts app | run it |
| `shell` | a zsh command line | runs **only** with `allowShellCommands` on. Output is discarded, and the exit status is logged |
| `builtin` | `settings`, `reload`, `openConfig`, `openLog`, `pause`, `quit` | AINCRAD commands |

`shell` is off by default, so a menu file from someone else can't run commands on your Mac.

## Controls

| Input | Effect |
|---|---|
| ⌥` (default, configurable) | open / close at the pointer, on that display |
| hold both buttons + slide down | open (when the gesture is on) |
| click | open a submenu, or run an item |
| hover | highlight and describe (lists never move under the mouse) |
| scroll wheel over a column | move through it |
| ↑ ↓ / → Return Space / ← | move / open or run / back |
| ⌫ or right-click | back; at the root, close |
| type letters | jump to a matching item |
| Esc, click outside, switch apps | close |

## Automation URL scheme

```
aincrad://open   aincrad://close   aincrad://toggle   aincrad://reload
aincrad://settings[/general|menu|themes|widgets|extensions|about]
aincrad://widgets/edit | done | save | show | hide
aincrad://key/up|down|left|right|enter|back|escape
```

Works from Shortcuts, scripts (`open -g "aincrad://toggle"`) and other launchers.

## Getting out of trouble

* Menu bar icon → **Pause Activation** turns off every shortcut and the gesture. **Quit AINCRAD** is there too.
* If Ice hides the icon: `osascript -e 'quit app "AINCRAD"'`, or use Activity Monitor.
* **Safe mode:** hold **⌥** while launching AINCRAD. It starts with only the main shortcut:
  no gesture, widgets, item shortcuts or extensions. It also starts this way automatically
  after it quits unexpectedly twice in a row within a minute of launch. The menu bar menu shows
  why, and **Restart Normally** gets you out.
* Every save from Settings first copies the previous file into `backups/`.
