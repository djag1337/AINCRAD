# AINCRAD performance findings

Machine: Mac mini 2018, Intel i5-8500B (6 cores), 8 GB RAM, Intel UHD 630, macOS 15.7.8.
Displays: Sceptre F22 1920×1080 @ 75 Hz (main) + Q27B13 1920×1080 @ 100 Hz.
Conditions: Wallspace animated wallpapers on both screens, plus Alcove, boringNotch, Claude and
ChatGPT running. WindowServer used 45–65 % CPU before AINCRAD started, and it varies a lot with
what's on screen, so treat any single WindowServer number as ±5 points.
Build: Release, measured 2026-10-13.

## Idle (launcher hidden, no widgets)

`scripts/measure_idle.sh` (`top` samples at 5 s intervals).

| Build | CPU average / max | Memory (phys_footprint) |
|---|---|---|
| Milestone 1, 5 min | 0.03 % / 0.6 % | 12 MB |
| Final, without the Settings window | not measured cleanly: the 5-minute run overlapped with you using the app (2.2 % average while the menu and Settings were in use) | 11–12 MB after 10 opens |
| With the Settings window open | n/a | 56 MB (SwiftUI). The fix releases it on close; built and tested but not installed yet, since you were using the app |

Nothing polls while hidden. Hotkeys are event-driven; data timers exist only for visible widgets;
the display-link probe runs for 0.6 s after an animation starts; the Accessibility check runs only
while Settings › General is open, or for up to 10 minutes after you request permission.

## Launcher activation

Time from the shortcut firing to the menu being built and committed (log: `open on … built+committed in`).

| Case | Result |
|---|---|
| M1, first open, before warm-up | 234–252 ms |
| M1, first open after the launch warm-up | 22.5 ms |
| M1, warm, 10 real key presses | 5.3–12.4 ms (median 5.8) |
| Final (info panel, sounds, glow), warm, 10 real ⌥` presses | 10.0–24.8 ms (median 12.3) |
| └ breakdown | building the layers 0.4–2.0 ms · ordering the window in 6.7–19.3 ms · Core Animation commit 0.9–11.9 ms |
| Phase 2 regression found and fixed | NSSound.play cost 10–20 ms on the main thread per sound, which pushed opens to 20–27 ms. Switched to System Sound Services with pre-scaled cached files; playback now costs ~0 ms |

## Animation frame pacing

A display link sampled for 0.6 s after each animation starts. It measures main-thread vsync
callbacks, so it catches stalls in AINCRAD, not dropped frames inside WindowServer. Target at
75 Hz: 13.3 ms.

| Animation | Result |
|---|---|
| Open, final build, 10 opens | 8 of 10 with 0 late frames (worst 13.5–14.7 ms). The first open after launch and one other had a single 70–80 ms hitch |
| Submenu column | mean 13.3–13.4 ms, 0 late |

## Widgets

| Measurement | Result |
|---|---|
| AINCRAD process with 7 live widgets (clock with seconds, HP bars, CPU ring, memory, network, app, launcher button) | 0.17 % CPU average, 13 MB |
| Data sources | only the ones visible widgets use. The log showed 5 of 6 running for that set, and none without widgets |
| WindowServer, 7 live widgets vs hidden (two A/B runs) | +10 to +11 points |
| Same, with bar animations removed | still about +11, so animation wasn't the cause |
| 7 widgets that never redraw | no measurable difference |
| A single clock: seconds / minutes | +2.7 / +0.5 points |

**Conclusion:** on this machine, with animated wallpapers, the compositor cost comes from
widgets **updating**, not from widgets existing. Each redraw of a window that sits over a moving
wallpaper costs WindowServer time. That's why clocks default to minutes, bars update instantly
rather than animating, sampling uses the slowest useful intervals with timer tolerance, and
covered widgets stop updating. If WindowServer headroom matters (games), keep few frequently
updating widgets on screen, or hide them from the menu bar menu.

## Other costs

| Item | Result |
|---|---|
| Scan of 159 apps for the Applications menu | 112–150 ms, on a background thread at launch, refreshed in the background when older than 2 min |
| App bundle | 5.9 MB (universal x86_64 + arm64; includes SwiftUI settings, icon set, 6 sounds) |
| Launch warm-up (invisible) | 58–95 ms, once, 1 s after launch |

## Design choices made for this hardware

* The launcher window exists only while open. All motion is Core Animation, so the main thread
  is idle between frames.
* Row shadows use explicit `shadowPath`s, which avoids an offscreen pass per row.
* Icons are rasterised once per size and tint, then cached. Only rows within the visible window load icons.
* No live behind-window blur, since it would recomposite on every wallpaper frame. It's not built;
  if added, it would be a measured, opt-in theme option.
* Mouse gesture tap on its own thread, so a busy UI can never delay the system's mouse events.
