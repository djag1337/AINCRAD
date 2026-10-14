# AINCRAD desktop widgets

Widgets are optional. Each one is its own small window just above the desktop icons: below every
app, on every Space, kept in place by Mission Control and left out of ⌘-Tab. Clicks pass straight through to the
desktop, except on app-shortcut and launcher-button widgets.

## Editing

Settings › **Widgets**:

* **Library**: click an entry to add that widget near the middle of the display under the pointer.
* **Edit on desktop**: every widget gets an outline. Drag to move (⇧ snaps to 10 pt), drag the
  corner square to resize, drag the knob above to rotate (⇧ snaps to 15°). Arrow keys nudge
  (⇧ moves 10 pt), and ⌫ deletes. You can also start this from the menu bar menu › Edit Widgets….
* **Inspector**: display, exact position and size, rotation, opacity, layer order, lock, hide,
  font, colours, panel and shadow, plus each type's own settings.
* **Undo / Redo**, **Save / Revert**. Changes show immediately; Save writes `widgets.json`.
* **Layouts**: save the current arrangement under a name, and load or delete saved ones (`layouts/`).

## Types

| type | Shows | props |
|---|---|---|
| `clock` | time, accent line, date | `format` (e.g. `HH:mm`, `h:mm a`, `HH:mm:ss`), `date` (e.g. `EEEE, MMMM d`, empty hides it) |
| `stat` | one reading as a bar, ring or text | `source`: `cpu`, `memory`, `disk`, `battery`, `network`, `uptime`, or an extension source `ext:<id>/<source>`. `show`: `bar`/`ring`/`text`. `label` |
| `hpbar` | SAO health bars: names, slanted bars going green → yellow → red, readout, LV badge | `rows`: `"Kirito:cpu, Asuna:memory, Silica:disk"` (cpu, memory, disk, battery). `level`: `uptime` (hours since start-up) or a number |
| `text` | text | `text`, `align` (`left`/`center`/`right`) |
| `image` | a picture | `path`, `fit` (`fit`/`fill`) |
| `app` | app icon + name; click opens it | `target` (path or bundle id), `label` (`true`/`false`) |
| `launcher` | SAO round button; click opens the launcher there | `label`, `icon` (`sf:<symbol>`) |

HP bars show what's left: free CPU, free memory, free disk space, or battery charge.

## widgets.json

```json
{
  "widgets": [
    { "type": "clock", "display": "", "x": 60, "y": 60, "width": 260, "height": 110,
      "props": { "format": "HH:mm", "date": "EEEE, MMMM d" } },
    { "type": "hpbar", "display": "Q27B13", "x": 1500, "y": 80, "width": 380, "height": 150,
      "style": { "background": "#1E222ACC", "textColor": "#FFFFFF" },
      "props": { "rows": "Kirito:cpu, Asuna:memory, Silica:disk" } }
  ]
}
```

Only `type` is required. Common fields: `display` (display name; `""` = main display), `x`, `y`
(points from that display's top-left), `width`, `height`, `rotation` (degrees clockwise),
`opacity`, `z` (higher = in front), `locked`, `hidden`, and `style`:

| style key | default |
|---|---|
| `font` | theme font |
| `fontSize` | 18 |
| `textColor` | theme panel text (white with a shadow when there's no panel) |
| `accent` | the display's accent (settings › `displayAccents`), else the theme accent |
| `background` | theme panel colour |
| `showPanel`, `shadow` | `true`, `true` |

## Multiple displays

Each widget belongs to one display by name, so the two monitors keep separate layouts. When a
display is disconnected, its widgets are hidden (Settings lists them as "display off"), and they
come back when it's reconnected. Nothing is deleted or moved. To move a widget to another
display, use the Display picker.

## Cost

* A widget's readings run only while its window is at least partly visible. Covered widgets, a
  sleeping display, and turned-off widgets sample nothing. Sources are shared: three CPU widgets
  make one CPU reading.
* Sampling intervals: CPU and network every 2 s, memory 5 s, battery 30 s, disk and uptime 60 s.
  Clocks wake on the minute (or on the second if the format shows seconds).
* Values update without animation. Measured: animating each bar kept WindowServer busy.
* On this Mac, with an animated wallpaper, widgets that never redraw cost the compositor nothing
  measurable. Each widget that updates costs a little WindowServer time on every update. A clock
  showing seconds measured about +2.7 percentage points of WindowServer CPU. See [PERFORMANCE.md](PERFORMANCE.md).
