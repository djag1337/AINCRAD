# AINCRAD extensions (API version 1)

**The easy way:** menu bar → **Extension Studio…** (or Settings › Extensions › New Extension…).
Build scripts by snapping together Scratch-style blocks, add themes, menus and widget presets
from forms, press ▶ to test, then **Publish › Export .aincrad File…** to share. Everything below
is what the Studio writes for you.

## Blocks

Scripts start with an event block (yellow) and run the blocks stacked under it, top to bottom.

| Category | Blocks |
|---|---|
| Events | when extension starts · when the launcher opens · when menu item … is chosen · every N seconds · when app … opens / quits |
| Control | wait N seconds · if … then · if … then … else · repeat N times · stop this script |
| Actions | open app · open website · open file or folder · run Shortcut · open the launcher |
| Looks | show message (SAO pop-up) · set gauge … to … level … % · switch theme · show/hide desktop widgets |
| Sensing | CPU/memory/disk/battery % · uptime hours · current time/date · app … is running · fetch URL 🔒 · read file · item … of JSON |
| Operators | + − × ÷ · round · pick random · join · < > = · and / or / not |
| Variables | set · change by · value · log (to the Studio console) |

* **Gauges connect scripts to widgets.** `set gauge "HP" to … level …` publishes a value as
  `script:<extension id>/HP`. Any stat widget can show it. Add a widget preset in the Studio's
  Widgets section, or pick the gauge as a stat widget's source.
* **Limits keep scripts harmless:** at most 20,000 steps and 45 s per run, waits of up to 30 s,
  loops of up to 1,000, and `every` timers of at least 2 s. Scripts of one extension run one at a
  time, and a run that is still going isn't started again. Variables persist between runs while
  AINCRAD is open.
* 🔒 `fetch` needs the `network` permission, and `read file` outside the extension folder needs
  `files`. The Studio works these out from the blocks you use. Manifests whose scripts use a
  block without its permission, or an unknown block, are refused.
* No scripts run in safe mode.

## Sharing: .aincrad files and catalogs

* An **.aincrad** file is the extension folder, zipped. Double-click it to install: AINCRAD
  checks the archive (no `..`, absolute paths or symlinks), validates the manifest, shows what it
  asks for, and installs it switched off.
* **Settings › Browse** lists a catalog: themes and extensions with preview images and one-click
  install. Every download is checked against the SHA-256 in the catalog before it's used. The
  default catalog is github.com/djag1337/AINCRAD-catalog; any path or `https://` URL works (Browse › Catalog field). See that
  repo for the format, the build tool and how to submit.

An extension is a folder in `~/Library/Application Support/AINCRAD/Extensions/` containing an
`extension.json` manifest. It can add:

* **themes**: theme files you can install into your theme list
* **menus**: lists you can use as a dynamic submenu (`provider: "ext:<id>/<menu id>"`)
* **data sources**: readings for stat widgets (`source: "ext:<id>/<source id>"`)
* **widget presets**: ready-made widgets in the Widgets library

## Safety model

* **No native code runs.** An extension is data: JSON, plus files it points to inside its own
  folder. Its scripts are block trees that AINCRAD's own interpreter runs, so they can only do
  what a block allows. There are no plug-in bundles and no shell commands. Menu items from an extension
  can use `shell` actions only if you separately turn on "Allow shell-command menu items".
* **Nothing is on by default.** New extensions are listed in Settings › Extensions but contribute
  nothing until you enable them.
* **Explicit permissions.** If an extension needs something outside its own folder, it must
  declare it, and you approve it when enabling:
  * `network`: its data sources may fetch `http(s)` URLs (at most once a minute each).
  * `files`: its data sources may read files elsewhere on your Mac (absolute or `~` paths).
* If an updated extension asks for more permissions than you approved, it stays off until you
  approve again.
* Paths inside an extension can't escape its folder (`../` is refused).
* Manifests are validated on load. Problems are listed in Settings › Extensions and the log,
  and the extension is skipped.

## Manifest

```json
{
  "id": "com.example.weather",
  "name": "Weather",
  "version": "1.0",
  "apiVersion": 1,
  "description": "Current temperature for a stat widget.",
  "author": "Example",
  "permissions": ["network"],
  "provides": {
    "themes": ["themes/stormy.json"],
    "menus": [
      { "id": "links", "name": "Weather sites", "items": [
        { "name": "Forecast", "icon": "sf:cloud.sun.fill", "action": { "type": "url", "target": "https://example.com" } }
      ]}
    ],
    "dataSources": [
      { "id": "temp", "name": "Temperature", "url": "https://api.example.com/now.json",
        "interval": 900, "value": "current.temperature", "text": "{value}°C", "max": 40 }
    ],
    "widgets": [
      { "name": "Temperature bar", "widget": { "type": "stat", "width": 240, "height": 70,
        "props": { "source": "ext:com.example.weather/temp", "show": "bar" } } }
    ],
    "scripts": [
      { "trigger": { "op": "app.launched", "inputs": { "app": { "op": "literal", "fields": { "value": "Steam" } } } },
        "steps": [ { "op": "looks.message", "inputs": { "text": { "op": "literal", "fields": { "value": "Link start!" } } } } ] }
    ]
  }
}
```

| Field | Notes |
|---|---|
| `id` | letters, numbers, dots, dashes. Must be unique |
| `apiVersion` | `1`. AINCRAD refuses manifests that need a newer version |
| `permissions` | any of `network`, `files` |
| `menus[].items` | the same item format as `menu.json` (see CONFIGURATION.md) |
| `dataSources[]` | exactly one of `url` / `file`. `file` is relative to the extension folder unless `files` is approved. `interval` is in seconds (default 300; minimum 60 for URLs, 5 for files). `value` is a dot path into the JSON (`a.b.0.c`), or leave it empty to use the whole document; plain-text files work too. `text` is a template where `{value}` is replaced. With `max`, bars fill to value ÷ max |
| `widgets[]` | a name and a widget in the `widgets.json` format |

Data sources are sampled only while a visible widget uses them, the same as built-in sources.

## Trying it

Settings › Extensions › **Create Example** writes `Extensions/aincrad-example/`. It uses every
feature, with no permissions: an Alfheim (green) theme, a links menu, a file-based "Floor" reading,
and a widget preset for it. Enable it, then:

* Themes: **Install Themes**, then choose `aincrad-example-alfheim`.
* Menu editor: add an item, set Type › Dynamic list › "AINCRAD Example: Example Links".
* Widgets: the library now has "Aincrad floor progress". Edit `progress.json` to change it.

## Compatibility

SAO Utils (Windows) plug-ins aren't supported; they're Windows code. The block language is the
supported way to add behaviour.
