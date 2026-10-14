# AINCRAD theme format

A theme is one JSON file in `~/Library/Application Support/AINCRAD/themes/`. Its file name
(without `.json`) is its id. Settings › Themes edits every value below with live preview, undo
and redo, and can duplicate, import, export and delete themes. Choose the active theme there, or
from the menu bar menu › Theme.

You can leave out any key; missing values come from Classic. A colour typo renders **magenta**
so it's easy to spot. To share a theme, send its file, or ship it inside an extension.

Built-in presets:

* `aincrad-classic`: the anime's Aincrad menu. Frosted white panels, grey glyph badges, orange selection.
* `aincrad-dark`: the same layout on dark panels.

Under macOS **Increase contrast** (Accessibility › Display), panels are drawn opaque with solid
borders, whatever the theme says.

## Colours

`"#RRGGBB"` or `"#RRGGBBAA"` (alpha last).

| Key | Used for |
|---|---|
| `accent`, `accentText` | selected row or button, focus ring, pointers, glow. Can be overridden per display (settings › `displayAccents`) and per item |
| `panel`, `panelText`, `panelBorder` | rows at rest; also the info panel and widget panels |
| `hover` | fill under the mouse or keyboard focus |
| `iconBadge`, `iconGlyph` | the round badge behind symbol icons, and the glyph in it |
| `circle`, `circleIcon`, `circleBorder` | root buttons at rest |
| `infoFooter`, `infoIcon` | info panel footer background, and its large symbol icon |
| `caption`, `captionShadow` | the name beside the focused root button (when the info panel is off) |
| `shadow` | drop-shadow colour |
| `backdrop` | full-screen tint while the launcher is open (keep the alpha very low) |

## Font

| Key | Default | |
|---|---|---|
| `family` | `"DIN Condensed"` | any installed font family, including ones you install yourself |
| `size` | `19` | row text |
| `captionSize` | `22` | info panel title and caption |

## Geometry (points)

| Key | Default |
|---|---|
| `circleDiameter`, `circleSpacing` | 54, 16 |
| `itemWidth`, `itemHeight`, `itemSpacing` | 212, 38, 5 |
| `columnGap` | 20 |
| `cornerRadius` | 3 |
| `visibleRows` | 6 (rows above and below the focused row before they fade out) |
| `screenMargin` | 40 |
| `infoPanelWidth`, `infoPanelHeight`, `infoPanelGap` | 230, 340, 26 |
| `bubbleRadius` | 9 (info bubble corners) |
| `cursorOffsetX`, `cursorOffsetY` | 72, 0 (the menu opens this far from the pointer; it flips left near the right edge) |

## Effects

| Key | Default | |
|---|---|---|
| `showInfoPanel` | `true` | the description bubble. It appears when you choose a root button, growing out of it, and hides again when you go back to the root |
| `gradient` | 0.07 | top-to-bottom shading of panels and buttons (0 = flat) |
| `shine` | 0.7 | opacity of the thin highlight along the top edge of each panel |
| `borderWidth` | 1 | |
| `shadowRadius`, `shadowOpacity` | 10, 0.35 | |
| `selectedRingWidth` | 2 | ring around the selected root button |
| `selectedGlow`, `glowOpacity` | 12, 0.65 | accent glow on the selection; 0 turns it off |
| `tilt` | 0 | degrees the columns and info panel turn away in perspective |

## Animation

```json
"animation": { "preset": "snappy", "speed": 1.2 }
```

`preset` is `classic`, `snappy`, `gentle` or `minimal`. It sets every value below, and any value
you write explicitly overrides it. `speed` multiplies all durations: 2.0 is twice as fast.

| Key | Classic | |
|---|---|---|
| `open` | 0.30 s | root buttons dropping in |
| `stagger` | 0.045 s | delay between buttons |
| `column` | 0.22 s | a submenu sliding in |
| `rowStagger` | 0.018 s | delay between rows |
| `move` | 0.20 s | columns re-aligning, selection |
| `highlight` | 0.10 s | hover |
| `close` | 0.14 s | fade out |
| `dropDistance`, `slideDistance` | 30, 18 pt | how far things travel as they appear (0 = fade only) |

With Reduce Motion on, nothing slides, and every duration is capped at 0.08 s.

## Sounds

```json
"sounds": { "volume": 0.35, "open": "builtin:open", "hover": "", "select": "~/Sounds/blip.aiff" }
```

Events: `open`, `select`, `back`, `close`, `hover`, `error`. Each takes `builtin:<name>` (one of
the six bundled sounds), a path to your own audio file, or `""` for silence. Hover is silent by
default. The bundled sounds are original, synthesised by `scripts/make_sounds.swift`. Sounds play
through System Sound Services, so they also scale with the alert volume in System Settings › Sound.

`schemaVersion` is 1. Later versions will read older files and fill new keys with defaults.
