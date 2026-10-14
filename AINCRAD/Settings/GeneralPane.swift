import AppKit
import ServiceManagement
import SwiftUI

struct GeneralPane: View {
    @EnvironmentObject var model: SettingsModel
    @State private var hasAccess = false
    @State private var loginStatus = SMAppService.mainApp.status

    private func bind<V>(_ path: WritableKeyPath<AppSettings, V>) -> Binding<V> {
        Binding(get: { model.settings[keyPath: path] }, set: { v in model.update { $0[keyPath: path] = v } })
    }

    var body: some View {
        Form {
            Section("Activation") {
                LabeledContent("Launcher shortcut") {
                    ShortcutRecorder(spec: Binding(get: { model.settings.hotKey },
                                                   set: { if let s = $0 { model.update { $0.hotKey = s } } }),
                                     allowsClear: false)
                }
                Picker("Open the launcher", selection: bind(\.placement)) {
                    Text("At the pointer").tag("cursor")
                    Text("Where the mouse gesture started").tag("gestureStart")
                    Text("In the centre of the display").tag("center")
                }
                Toggle("Pause all activation", isOn: bind(\.activationPaused))
                TextField("Player name (HUD)", text: bind(\.playerName), prompt: Text(NSFullUserName().split(separator: " ").first.map(String.init) ?? "Player"))
            }

            Section {
                Toggle("Swipe fingers on the Magic Mouse to open", isOn: bind(\.gesture.touch))
                if model.settings.gesture.touch {
                    Picker("Fingers", selection: bind(\.gesture.touchFingers)) {
                        Text("Two fingers").tag(2)
                        Text("Three fingers").tag(3)
                    }
                    SliderRow(title: "Swipe length (% of surface)", value: Binding(
                        get: { model.settings.gesture.touchDistance * 100 },
                        set: { v in model.update { $0.gesture.touchDistance = v / 100 } }), range: 8...60)
                    Picker("Surfaces", selection: bind(\.gesture.touchDevices)) {
                        Text("Magic Mouse only").tag("mouse")
                        Text("Magic Mouse and trackpads").tag("all")
                    }
                }
            } header: {
                Text("Touch gesture")
            } footer: {
                Text("Swipe in the direction chosen below (down by default, like SAO). Needs no permissions. It reads touches through a private macOS framework, so a future macOS could break it; AINCRAD then just turns it off. On trackpads two-finger swipes also scroll, so “Magic Mouse only” is the default.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Hide Apple's Dock completely", isOn: bind(\.hideAppleDock))
                Toggle("Hide Apple's menu bar completely", isOn: bind(\.hideAppleMenuBar))
                Toggle("Show the SAO top bar and dock with the launcher", isOn: bind(\.shellModeEnabled))
                Toggle("Keep the SAO bar and dock up all the time (replaces Apple's menu bar)", isOn: bind(\.shellReplaceSystem))
                    .disabled(!model.settings.shellModeEnabled)
                Toggle("Show app menus when the pointer reaches the top edge", isOn: bind(\.shellRevealMenus))
                    .disabled(!model.settings.shellModeEnabled || !model.settings.shellReplaceSystem)
                Text("“Hide … completely” keeps Apple's Dock and menu bar away in every app and Space, even at the screen edge, while AINCRAD runs. App menus are then on the SAO dock: open the launcher and click the first dock button (the app you were in). The SAO top bar and dock appear only with the launcher unless “all the time” is on: they stay up the whole time AINCRAD runs, on every display, and Apple's menu bar and Dock never show — on the desktop, in apps, or in full screen. Apple's menu bar stays in place under the SAO bar so windows still stop below it; over full-screen apps the SAO bar and dock hide and slide in at the screen edge instead. The dock lists your Dock's apps in order, then other running apps.")
            } header: {
                Text("AINCRAD Shell")
            } footer: {
                Text("Your original menu bar and Dock settings are saved first and come back when you turn Replace off or quit AINCRAD. If AINCRAD crashes they stay replaced until you relaunch and quit it, or start it in Safe Mode (hold ⌥), which always shows Apple's.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Picker("Buttons", selection: bind(\.gesture.buttons)) {
                    Text("Hold both buttons, then slide").tag("both")
                    Text("Hold the right button, then slide (any mouse)").tag("right")
                }
                Toggle("Open with a mouse-button gesture", isOn: Binding(
                    get: { model.settings.gesture.enabled },
                    set: { on in
                        model.update { $0.gesture.enabled = on }
                        if on && !hasAccess { model.actions.requestAccessibility() }
                    }))
                if model.settings.gesture.enabled && !hasAccess {
                    HStack {
                        Label("Needs Accessibility access to tell a gesture from a normal right-click.",
                              systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Spacer()
                        Button("Open Privacy Settings") {
                            model.actions.requestAccessibility()
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
                Picker("Slide direction", selection: bind(\.gesture.slide)) {
                    Text("Down (SAO)").tag("down")
                    Text("Up").tag("up")
                    Text("Left").tag("left")
                    Text("Right").tag("right")
                    Text("Any direction").tag("any")
                    Text("No slide: open on the chord").tag("none")
                }
                SliderRow(title: "Slide distance (pt)", value: bind(\.gesture.distance), range: 15...200)
                SliderRow(title: "Right-click wait (ms)", value: bind(\.gesture.chordWindowMs), range: 40...250, step: 5)
                SliderRow(title: "Activation delay (ms)", value: bind(\.gesture.activationDelayMs), range: 0...500, step: 10)
                Toggle("Ignore the gesture in full-screen apps and games", isOn: bind(\.gesture.disableInFullScreen))
                ExcludedAppsList(ids: bind(\.gesture.excludedApps))
            } header: {
                Text("Mouse-button gesture")
            } footer: {
                Text(model.settings.gesture.buttons == "right"
                     ? "Right-clicks arrive when you release (or after a short hold) so a slide can be recognised; left clicks are never delayed."
                     : "Right-clicks arrive after the wait above so a gesture can be recognised; left clicks are never delayed. A Magic Mouse can't press both buttons at once: use the right-button or touch gesture.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                ForEach(NSScreen.screens, id: \.self) { screen in
                    DisplayAccentRow(name: screen.localizedName, accents: bind(\.displayAccents))
                }
            } header: {
                Text("Per-display accent")
            } footer: {
                Text("Overrides the theme's highlight colour on one display, e.g. blue and red to match two wallpapers. Widgets on that display follow it too.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show notifications as SAO bubbles", isOn: Binding(
                    get: { model.settings.notificationBubbles },
                    set: { on in
                        model.update { $0.notificationBubbles = on }
                        if on && !hasAccess { model.actions.requestAccessibility() }
                    }))
                Toggle("Close the macOS banner once the bubble shows it", isOn: bind(\.notificationsHideOriginal))
                SliderRow(title: "Bubble time (s)", value: bind(\.notificationSeconds), range: 3...15)
                HStack {
                    if model.settings.notificationBubbles && !hasAccess {
                        Label("Needs Accessibility access.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    Spacer()
                    Button("Test Bubble") { model.actions.testBubble() }
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("macOS has no public way to read other apps' notifications, so AINCRAD reads Notification Center's banners with the Accessibility permission. It only looks at banners as they appear, and never stores them.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Feedback") {
                Toggle("Sound effects", isOn: bind(\.soundsEnabled))
                Picker("Reduce motion", selection: bind(\.reducedMotion)) {
                    Text("Follow System Settings").tag("system")
                    Text("On").tag("on")
                    Text("Off").tag("off")
                }
            }

            Section {
                Toggle("Enable Command Center, clipboard history, captures and workspaces", isOn: bind(\.productivityEnabled))
                Toggle("Show the floating AINCRAD button", isOn: bind(\.commandDeckEnabled))
                LabeledContent("Clipboard history size") {
                    Picker("", selection: bind(\.clipboardHistoryLimit)) {
                        Text("50 items").tag(50)
                        Text("100 items").tag(100)
                        Text("250 items").tag(250)
                    }.labelsHidden().frame(width: 130)
                }
                Text("Clipboard contents, captures, workspaces and usage counts stay in ~/Library/Application Support/AINCRAD/productivity.json. Copies from common password managers and Keychain Access are ignored.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Command Center")
            } footer: {
                Text("Search commands include “timer 25”, “note …”, “paste …”, “workspace …”, and “window left”. Selection-aware actions and automatic paste need Accessibility access.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Startup") {
                Toggle("Open AINCRAD at login", isOn: Binding(
                    get: { loginStatus == .enabled },
                    set: { on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            model.message = "Could not change the login item: \(error.localizedDescription)"
                        }
                        loginStatus = SMAppService.mainApp.status
                        model.update { $0.launchAtLogin = loginStatus == .enabled }
                    }))
                if loginStatus == .requiresApproval {
                    Text("Approve AINCRAD in System Settings › General › Login Items.").font(.caption).foregroundStyle(.orange)
                }
            }

            Section {
                Toggle("Allow shell-command menu items", isOn: bind(\.allowShellCommands))
            } header: {
                Text("Safety")
            } footer: {
                Text("Off by default so a menu file from someone else can't run commands. Shortcuts-app actions are always allowed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            hasAccess = model.actions.hasAccessibility()
            loginStatus = SMAppService.mainApp.status
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            // Only while this pane is visible: picks up a permission granted in System Settings.
            hasAccess = model.actions.hasAccessibility()
        }
    }
}

struct ExcludedAppsList: View {
    @Binding var ids: [String]

    var body: some View {
        LabeledContent("Never in these apps") {
            VStack(alignment: .trailing, spacing: 4) {
                ForEach(ids, id: \.self) { id in
                    HStack {
                        Text(NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { AppScanner.displayName($0.path) } ?? id)
                        Text(id).font(.caption).foregroundStyle(.secondary)
                        Button { ids.removeAll { $0 == id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    }
                }
                Button("Add App…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.application]
                    panel.directoryURL = URL(fileURLWithPath: "/Applications")
                    panel.allowsMultipleSelection = true
                    guard panel.runModal() == .OK else { return }
                    let new = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }.filter { !ids.contains($0) }
                    ids += new
                }
            }
        }
    }
}

struct DisplayAccentRow: View {
    let name: String
    @Binding var accents: [String: String]
    private static let swatches = [("Blue", "#3FA9F5"), ("Red", "#E0303A"), ("Orange", "#F2A516"), ("Green", "#5FD068"), ("Purple", "#A66BFF")]

    var body: some View {
        LabeledContent(name) {
            HStack {
                if let hex = accents[name] {
                    ColorPicker("", selection: hexColor(Binding(get: { hex }, set: { accents[name] = $0 }))).labelsHidden()
                }
                Menu(accents[name] == nil ? "Theme colour" : "Change") {
                    ForEach(Self.swatches, id: \.0) { title, hex in Button(title) { accents[name] = hex } }
                    Divider()
                    Button("Use theme colour") { accents[name] = nil }
                }
                .fixedSize()
            }
        }
    }
}
