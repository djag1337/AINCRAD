import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    let model: SettingsModel
    /// Lets the owner drop this controller on close, so the SwiftUI views (~40 MB) don't stay resident.
    var onClose: (() -> Void)?

    init(model: SettingsModel) {
        self.model = model
        let host = NSHostingController(rootView: SettingsView().environmentObject(model))
        let window = NSWindow(contentViewController: host)
        window.title = "AINCRAD Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1040, height: 680))
        window.minSize = NSSize(width: 900, height: 560)
        window.setFrameAutosaveName("AINCRADSettings")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(tab: SettingsView.Tab? = nil) {
        if let tab { model.tab = tab }
        NSApp.activate(ignoringOtherApps: true)
        window?.ensureOnScreen()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { self.onClose?() }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if model.widgets.editing { model.widgets.setEditing(false) }
        if model.widgets.dirty { model.widgets.save() }
        guard model.menuDirty || model.themeDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes before closing?"
        alert.informativeText = "The " + [model.menuDirty ? "menu" : nil, model.themeDirty ? "theme" : nil]
            .compactMap { $0 }.joined(separator: " and ") + " have unsaved edits."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if model.menuDirty { model.saveMenu() }
            if model.themeDirty { model.saveTheme() }
            return true
        case .alertSecondButtonReturn:
            model.revertMenu()
            model.revertTheme()
            return true
        default:
            return false
        }
    }
}

struct SettingsView: View {
    enum Tab: String, Hashable, CaseIterable {
        case general, menu, themes, widgets, extensions, browse, commands, browser, about

        var title: String {
            switch self {
            case .general: "General"; case .menu: "Menu"; case .themes: "Themes"; case .widgets: "Widgets"
            case .extensions: "Extensions"; case .browse: "Browse"; case .commands: "Quick Commands"
            case .browser: "Browser"; case .about: "About"
            }
        }
        var icon: String {
            switch self {
            case .general: "gearshape.fill"; case .menu: "list.bullet.indent"; case .themes: "paintpalette.fill"
            case .widgets: "square.grid.2x2.fill"; case .extensions: "puzzlepiece.extension.fill"; case .browse: "shippingbox.fill"
            case .commands: "command"; case .browser: "globe"; case .about: "info.circle.fill"
            }
        }
        var tint: Color {
            switch self {
            case .general: .gray; case .menu: .blue; case .themes: .pink; case .widgets: .orange
            case .extensions: .purple; case .browse: .brown; case .commands: .indigo; case .browser: .teal; case .about: .gray
            }
        }
    }

    @EnvironmentObject var model: SettingsModel
    private let groups: [(String, [Tab])] = [
        ("Launcher", [.general, .menu, .themes, .widgets]),
        ("Extend", [.extensions, .browse, .commands]),
        ("Ecosystem", [.browser]),
        ("", [.about]),
    ]

    var body: some View {
        HStack(spacing: 0) {
            List(selection: Binding(get: { Optional(model.tab) }, set: { if let t = $0 { model.tab = t } })) {
                ForEach(groups, id: \.0) { name, tabs in
                    Section(name) {
                        ForEach(tabs, id: \.self) { tab in
                            Label {
                                Text(tab.title)
                            } icon: {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 24, height: 24)
                                    .background(tab.tint.gradient, in: RoundedRectangle(cornerRadius: 6))
                            }
                            .tag(tab)
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(width: 214)

            Divider()

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: model.tab.icon).font(.title2).foregroundStyle(model.tab.tint)
                    Text(model.tab.title).font(.title2.weight(.semibold))
                    Spacer()
                    AINCRADLogo(accent: Color(hex: model.store.theme.colors.accent))
                        .frame(width: 84, height: 44)
                }
                .padding(.horizontal, 22).padding(.vertical, 10)
                Divider()
                pane.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .alert(model.message ?? "", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    @ViewBuilder private var pane: some View {
        switch model.tab {
        case .general: GeneralPane()
        case .menu: MenuEditorPane()
        case .themes: ThemesPane()
        case .widgets: WidgetsPane(widgets: model.widgets)
        case .extensions: ExtensionsPane(extensions: model.extensions)
        case .browse: BrowsePane(catalog: model.catalog)
        case .commands: QuickCommandsPane()
        case .browser: BrowserPane()
        case .about: AboutPane()
        }
    }
}

/// A flat, clip-art version of the app icon: the star circle and the highlighted menu row, in the theme's accent.
struct AINCRADLogo: View {
    let accent: Color

    var body: some View {
        HStack(spacing: 2) {
            ZStack {
                Circle().strokeBorder(accent, lineWidth: 2.5)
                Circle().fill(Color(white: 0.35)).padding(3.5)
                Circle().fill(accent).padding(5)
                Image(systemName: "star.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)
            .shadow(color: accent.opacity(0.55), radius: 5)
            Image(systemName: "arrowtriangle.left.fill").font(.system(size: 7)).foregroundStyle(accent)
            VStack(spacing: 3) {
                bar(.init(white: 0.78, opacity: 1), dot: Color(white: 0.4))
                bar(accent, dot: .white).shadow(color: accent.opacity(0.5), radius: 3)
                bar(.init(white: 0.78, opacity: 1), dot: Color(white: 0.4))
            }
        }
    }

    private func bar(_ fill: Color, dot: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(dot).frame(width: 5, height: 5)
            Capsule().fill(dot.opacity(0.7)).frame(height: 2)
        }
        .padding(.horizontal, 4).frame(width: 36, height: 9)
        .background(fill, in: RoundedRectangle(cornerRadius: 2))
    }
}

extension Color {
    /// "#RRGGBB" (an optional trailing alpha is ignored); falls back to the classic orange.
    init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        let v = UInt64(h.prefix(6), radix: 16) ?? 0xF5A623
        self.init(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

/// Captures the next key combination. Global hotkeys are suspended while recording so the
/// current shortcut can be pressed again to keep it.
struct ShortcutRecorder: View {
    @Binding var spec: HotKeySpec?
    var allowsClear = true
    @EnvironmentObject var model: SettingsModel
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(recording ? "Press a shortcut…  (Esc cancels)" : (spec.map(HotKey.display) ?? "None")) {
                recording ? stop() : start()
            }
            .frame(minWidth: 150)
            if allowsClear, spec != nil, !recording {
                Button { spec = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .help("Remove shortcut")
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        model.actions.suspendHotKeys(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == 53 { stop(); return nil }
            guard let key = HotKey.keyName(forKeyCode: Int(e.keyCode)) else { NSSound.beep(); return nil }
            var mods: [String] = []
            let f = e.modifierFlags
            if f.contains(.control) { mods.append("control") }
            if f.contains(.option) { mods.append("option") }
            if f.contains(.shift) { mods.append("shift") }
            if f.contains(.command) { mods.append("command") }
            let isFunctionKey = key.count > 1 && key.hasPrefix("f")
            guard !mods.isEmpty || isFunctionKey else { NSSound.beep(); return nil }
            spec = HotKeySpec(key: key, modifiers: mods)
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { model.actions.suspendHotKeys(false) }
        recording = false
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var format = "%.0f"

    var body: some View {
        LabeledContent(title) {
            HStack {
                // Rounded here instead of Slider(step:), which draws a tick mark per step.
                Slider(value: Binding(get: { value }, set: { value = ($0 / step).rounded() * step }), in: range)
                Text(String(format: format, value)).monospacedDigit().frame(width: 64, alignment: .trailing)
            }
        }
    }
}

extension NSWindow {
    /// A saved frame can point at a display that's gone or been rearranged; bring the window
    /// back to the display under the pointer unless at least half of it is visible somewhere.
    func ensureOnScreen() {
        let area = frame.width * frame.height
        let visible = NSScreen.screens.map { s -> CGFloat in
            let r = s.visibleFrame.intersection(frame)
            return r.isNull ? 0 : r.width * r.height
        }.max() ?? 0
        guard area > 0, visible < area * 0.5 else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let vf = screen?.visibleFrame else { return center() }
        setFrameOrigin(NSPoint(x: vf.midX - frame.width / 2, y: vf.midY - frame.height / 2))
    }
}
