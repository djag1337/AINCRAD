# Developing AINCRAD

Everything you need to build, test and find your way around the code.

## Build and install

Requirements: macOS 14+, Xcode 16, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
./scripts/build.sh               # Release build → /Applications/AINCRAD.app
./scripts/test.sh                # all unit tests
./scripts/measure_idle.sh 300    # sample the running app's idle CPU/memory for 5 min
swift scripts/make_sounds.swift AINCRAD/Resources/Sounds   # regenerate the sounds
swift scripts/make_icon.swift AINCRAD/Assets.xcassets      # regenerate the app icon
```

`project.yml` is the source of truth for targets and build settings. `xcodegen generate`
recreates `AINCRAD.xcodeproj` from it, and the scripts do this for you. Source files can be
edited freely in Xcode, and new files dropped into `AINCRAD/` are picked up on the next generate.

Build output goes to `~/Library/Caches/AINCRAD-build`, **not** the project folder. `~/Documents`
is in iCloud Drive here, and iCloud's file attributes make `codesign` fail (it would also upload
the build products).

**Signing.** The project signs with the local *Apple Development* certificate (team
`UWC6NUWUHW`), so the app's identity stays stable across rebuilds. macOS ties the Accessibility
grant (needed for the mouse gesture) to that identity; an ad-hoc signed app would lose the grant
on every rebuild. The app runs on this Mac but isn't notarised for distribution. To build on
another Mac, change `DEVELOPMENT_TEAM` in `project.yml`, or use `CODE_SIGN_IDENTITY: "-"`.

## Project layout

```
AINCRAD/App          main, AppDelegate (menu bar, activation, URL scheme), LaunchGuard (safe mode)
AINCRAD/Config       settings/menu/theme models, tolerant JSON, MenuTree edits, store, recents
AINCRAD/Input        Carbon hotkeys, item shortcuts, GestureRecognizer (pure) + GestureMonitor (event tap)
AINCRAD/Launcher     panel, MenuView (layers + input), InfoPanel, Motion (animation system),
                     MenuLayout (pure geometry), IconCache, ActionRunner, controller
AINCRAD/Widgets      model, DataHub (system readings), renderers, window/editor, manager
AINCRAD/Extensions   manifest, validation, permissions, contributions
AINCRAD/Scripts      block language (Blocks), interpreter (ScriptEngine), events (ScriptRuntime), ScriptTree edits, message pop-up
AINCRAD/Studio       Extension Studio window and block views
AINCRAD/Settings     SwiftUI settings: General, Menu, Themes, Widgets, Extensions, Browse, About
AINCRAD/Support      logging, colours, sounds, frame probe
AINCRADTests         unit tests
```

Design rules: rendering reads every visual value from `Theme` (the SAO look is just the default
data). Animation timing is decided only in `Motion`. Nothing runs on a timer unless something
visible needs it.
