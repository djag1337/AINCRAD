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
        window.setContentSize(NSSize(width: 940, height: 640))
        window.minSize = NSSize(width: 820, height: 520)
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
    enum Tab: String, Hashable { case general, menu, themes, widgets, extensions, browse, about }
    @EnvironmentObject var model: SettingsModel

    var body: some View {
        TabView(selection: $model.tab) {
            GeneralPane().tabItem { Label("General", systemImage: "gearshape") }.tag(Tab.general)
            MenuEditorPane().tabItem { Label("Menu", systemImage: "list.bullet.indent") }.tag(Tab.menu)
            ThemesPane().tabItem { Label("Themes", systemImage: "paintpalette") }.tag(Tab.themes)
            WidgetsPane(widgets: model.widgets).tabItem { Label("Widgets", systemImage: "square.grid.2x2") }.tag(Tab.widgets)
            ExtensionsPane(extensions: model.extensions).tabItem { Label("Extensions", systemImage: "puzzlepiece.extension") }.tag(Tab.extensions)
            BrowsePane(catalog: model.catalog).tabItem { Label("Browse", systemImage: "shippingbox") }.tag(Tab.browse)
            AboutPane().tabItem { Label("About", systemImage: "info.circle") }.tag(Tab.about)
        }
        .padding(12)
        .alert(model.message ?? "", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK", role: .cancel) {}
        }
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
