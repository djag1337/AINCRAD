import AppKit
import SwiftUI

struct WidgetsPane: View {
    @State private var addToHUD = false
    @EnvironmentObject var model: SettingsModel
    @ObservedObject var widgets: WidgetManager

    var body: some View {
        VStack(spacing: 8) {
            toolbar
            HSplitView {
                sidebar.frame(minWidth: 230, idealWidth: 250, maxWidth: 300)
                Group {
                    if let w = widgets.selected {
                        WidgetInspector(widgets: widgets, widget: w)
                    } else {
                        VStack(spacing: 8) {
                            Text("Add a widget from the library, or select one.").foregroundStyle(.secondary)
                            Text("With “Edit on desktop” on, drag widgets to move them, the corner square to resize, and the knob above to rotate (⇧ snaps). Arrow keys nudge, ⌫ deletes.")
                                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 420)
            }
        }
        .onDisappear { if widgets.editing { widgets.setEditing(false) } }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            Toggle("Show widgets", isOn: Binding(get: { model.settings.widgetsEnabled }, set: { v in
                model.update { $0.widgetsEnabled = v }
                widgets.rebuildAll()
            }))
            Toggle(isOn: Binding(get: { widgets.editing }, set: { widgets.setEditing($0) })) {
                Label("Edit on desktop", systemImage: "hand.draw")
            }
            .toggleStyle(.button)
            Button { widgets.undoChange() } label: { Image(systemName: "arrow.uturn.backward") }.help("Undo")
                .disabled(!widgets.canUndo)
            Button { widgets.redoChange() } label: { Image(systemName: "arrow.uturn.forward") }.help("Redo")
                .disabled(!widgets.canRedo)
            Menu("Layouts") {
                Button("Save Current Layout As…") {
                    if let name = prompt("Layout name", placeholder: "Gaming setup") { widgets.saveLayout(named: name) }
                }
                if !widgets.layoutNames.isEmpty { Divider() }
                ForEach(widgets.layoutNames, id: \.self) { name in
                    Menu(name) {
                        Button("Load") { widgets.loadLayout(named: name) }
                        Button("Delete") { widgets.deleteLayout(named: name) }
                    }
                }
            }
            .fixedSize()
            Spacer()
            Button("Revert") { widgets.revert() }.disabled(!widgets.dirty)
            Button("Save") { widgets.save() }.disabled(!widgets.dirty).buttonStyle(.borderedProminent)
        }
        .buttonStyle(.bordered)
    }

    private var sidebar: some View {
        List(selection: Binding(get: { widgets.selectedID }, set: { widgets.selectedID = $0 })) {
            Section("Library") {
                Picker("Add to", selection: $addToHUD) {
                    Text("Desktop").tag(false)
                    Text("HUD").tag(true)
                }
                .pickerStyle(.segmented)
                .help("HUD widgets appear only while the launcher is open, above it, on that display.")
                ForEach(Array((WidgetCatalog.entries + widgets.extraEntries()).enumerated()), id: \.offset) { _, entry in
                    Button { widgets.add(entry, hud: addToHUD) } label: {
                        Label(entry.name, systemImage: entry.symbol)
                    }
                    .buttonStyle(.borderless)
                }
            }
            Section("HUD (with the launcher)") {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("HUD opacity")
                        Spacer()
                        Text("\(Int((model.settings.hudWidgetOpacity * 100).rounded()))%").foregroundStyle(.secondary).monospacedDigit()
                    }
                    Slider(value: Binding(get: { model.settings.hudWidgetOpacity }, set: { v in
                        model.update { $0.hudWidgetOpacity = v }
                        widgets.rebuildAll()
                    }), in: 0.1...1, step: 0.05)
                }
                ForEach(widgets.layout.widgets.filter(\.hud).sorted { $0.z > $1.z }) { w in row(w) }
            }
            Section("On your desktops") {
                ForEach(widgets.layout.widgets.filter { !$0.hud }.sorted { $0.z > $1.z }) { w in row(w) }
            }
        }
    }

    private func row(_ w: WidgetConfig) -> some View {
        HStack {
            Text(WidgetsPane.title(w))
            Spacer()
            if w.hidden { Image(systemName: "eye.slash").foregroundStyle(.secondary) }
            if w.locked { Image(systemName: "lock.fill").foregroundStyle(.secondary) }
            if WidgetManager.screen(for: w.display) == nil {
                Text("display off").font(.caption).foregroundStyle(.orange)
            }
        }
        .tag(Optional(w.id))
    }

    static func title(_ w: WidgetConfig) -> String {
        switch w.type {
        case "stat": return DataHub.shared.title(for: w.prop("source", "cpu"))
        case "hpbar": return "HP bars"
        case "quests": return "Quest log"
        case "party": return "Party"
        case "status": return "Status effects"
        case "battlelog": return "Battle log"
        case "exp": return "EXP bar"
        case "app": return "App: " + w.prop("target", "").components(separatedBy: "/").last!.replacingOccurrences(of: ".app", with: "")
        default: return WidgetCatalog.entries.first { $0.type == w.type }?.name ?? w.type
        }
    }

    private func prompt(_ title: String, placeholder: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = placeholder
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }
}

struct WidgetInspector: View {
    @ObservedObject var widgets: WidgetManager
    let widget: WidgetConfig
    private static let families = NSFontManager.shared.availableFontFamilies.sorted()

    private func bind<V>(_ path: WritableKeyPath<WidgetConfig, V>, _ key: String) -> Binding<V> {
        Binding(get: { widget[keyPath: path] }, set: { v in widgets.update(widget.id, key: key) { $0[keyPath: path] = v } })
    }

    private func prop(_ key: String, _ fallback: String = "") -> Binding<String> {
        Binding(get: { widget.props[key] ?? fallback }, set: { v in widgets.update(widget.id, key: "p." + key) { $0.props[key] = v } })
    }

    private func optionalColor(_ path: WritableKeyPath<WidgetConfig, String?>, _ key: String, title: String, fallback: String) -> some View {
        LabeledContent(title) {
            HStack {
                if widget[keyPath: path] != nil {
                    ColorPicker("", selection: hexColor(Binding(get: { widget[keyPath: path] ?? fallback },
                                                                set: { v in widgets.update(widget.id, key: key) { $0[keyPath: path] = v } })))
                        .labelsHidden()
                    Button("Theme") { widgets.update(widget.id) { $0[keyPath: path] = nil } }
                } else {
                    Text("from theme").foregroundStyle(.secondary)
                    Button("Custom…") { widgets.update(widget.id) { $0[keyPath: path] = fallback } }
                }
            }
        }
    }

    var body: some View {
        Form {
            Section(WidgetsPane.title(widget)) {
                Picker("Display", selection: bind(\.display, "display")) {
                    ForEach(NSScreen.screens, id: \.self) { s in
                        Text(s.localizedName + (s == NSScreen.screens.first ? " (main)" : "")).tag(WidgetManager.displayKey(s))
                    }
                    if WidgetManager.screen(for: widget.display) == nil { Text("\(widget.display) (disconnected)").tag(widget.display) }
                }
                HStack {
                    TextField("X", value: bind(\.x, "x"), format: .number)
                    TextField("Y", value: bind(\.y, "y"), format: .number)
                    TextField("Width", value: bind(\.width, "w"), format: .number)
                    TextField("Height", value: bind(\.height, "h"), format: .number)
                }
                SliderRow(title: "Rotation (°)", value: bind(\.rotation, "rot"), range: 0...359)
                Picker("Shows", selection: bind(\.hud, "hud")) {
                    Text("On the desktop").tag(false)
                    Text("In the HUD (with the launcher)").tag(true)
                }
                SliderRow(title: "Opacity", value: bind(\.opacity, "op"), range: 0.1...1, step: 0.05, format: "%.2f")
                HStack {
                    Toggle("Locked", isOn: bind(\.locked, "lock"))
                    Toggle("Hidden", isOn: bind(\.hidden, "hide"))
                    Spacer()
                    Button("Bring to Front") { widgets.update(widget.id) { $0.z = (widgets.layout.widgets.map(\.z).max() ?? 0) + 1 } }
                    Button("Send to Back") { widgets.update(widget.id) { $0.z = (widgets.layout.widgets.map(\.z).min() ?? 0) - 1 } }
                }
            }
            typeSection
            Section("Style") {
                Picker("Font", selection: Binding(get: { widget.style.font ?? "" }, set: { v in
                    widgets.update(widget.id, key: "font") { $0.style.font = v.isEmpty ? nil : v }
                })) {
                    Text("Theme font").tag("")
                    ForEach(Self.families, id: \.self) { Text($0).tag($0) }
                }
                SliderRow(title: "Text size", value: bind(\.style.fontSize, "fs"), range: 9...48)
                optionalColor(\.style.textColor, "tc", title: "Text colour", fallback: "#FFFFFF")
                optionalColor(\.style.accent, "ac", title: "Accent", fallback: "#3FA9F5")
                Toggle("Panel background", isOn: bind(\.style.showPanel, "panel"))
                if widget.style.showPanel {
                    optionalColor(\.style.background, "bg", title: "Panel colour", fallback: "#20242CCC")
                }
                Toggle("Shadow", isOn: bind(\.style.shadow, "shadow"))
            }
            Section {
                HStack {
                    Button("Duplicate") { widgets.duplicate(widget.id) }
                    Spacer()
                    Button("Remove", role: .destructive) { widgets.remove(widget.id) }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var typeSection: some View {
        switch widget.type {
        case "clock":
            Section("Clock") {
                TextField("Time format", text: prop("format", "HH:mm"))
                TextField("Date format (empty hides)", text: prop("date"))
                Text("Unicode patterns: HH:mm, h:mm a, HH:mm:ss (seconds update every second), EEEE, MMMM d.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case "stat":
            Section("Reading") {
                Picker("Source", selection: prop("source", "cpu")) {
                    ForEach(StatSource.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                    let ext = DataHub.shared.external.keys.sorted()
                    if !ext.isEmpty { Divider() }
                    ForEach(ext, id: \.self) { Text(DataHub.shared.title(for: $0) + " (extension)").tag($0) }
                }
                Picker("Show as", selection: prop("show", "bar")) {
                    Text("Bar").tag("bar")
                    Text("Ring").tag("ring")
                    Text("Text only").tag("text")
                }
                TextField("Label (empty = source name)", text: prop("label"))
            }
        case "hpbar":
            Section("HP bars") {
                TextField("Rows (Name:source, …)", text: prop("rows", "Player:cpu"))
                Text("Sources: cpu, memory, disk, battery. The bar shows what's left, like HP.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Level (\"uptime\" = hours awake, or a number)", text: prop("level", "uptime"))
            }
        case "text":
            Section("Text") {
                TextField("Text", text: prop("text"), axis: .vertical).lineLimit(2...6)
                Picker("Alignment", selection: prop("align", "center")) {
                    Text("Left").tag("left")
                    Text("Centre").tag("center")
                    Text("Right").tag("right")
                }
            }
        case "image":
            Section("Image") {
                HStack {
                    TextField("Path", text: prop("path"))
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.image]
                        if panel.runModal() == .OK, let url = panel.url { prop("path").wrappedValue = url.path }
                    }
                }
                Picker("Fit", selection: prop("fit", "fit")) {
                    Text("Fit").tag("fit")
                    Text("Fill").tag("fill")
                }
            }
        case "app":
            Section("App") {
                HStack {
                    TextField("App path or bundle id", text: prop("target"))
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.application]
                        panel.directoryURL = URL(fileURLWithPath: "/Applications")
                        if panel.runModal() == .OK, let url = panel.url { prop("target").wrappedValue = url.path }
                    }
                }
                Toggle("Show name", isOn: Binding(get: { widget.flag("label", true) }, set: { v in prop("label").wrappedValue = v ? "true" : "false" }))
            }
        case "party":
            Section("Party") {
                Stepper("Members: \(widget.prop("count", "3"))", value: Binding(get: { Int(widget.prop("count", "3")) ?? 3 },
                        set: { prop("count").wrappedValue = String($0) }), in: 1...6)
            }
        case "quests":
            Section("Quest log") {
                Toggle("Calendar events", isOn: Binding(get: { widget.flag("events", true) }, set: { v in prop("events").wrappedValue = v ? "true" : "false" }))
                Toggle("Reminders due today", isOn: Binding(get: { widget.flag("reminders", true) }, set: { v in prop("reminders").wrappedValue = v ? "true" : "false" }))
                HStack {
                    Text(QuestStore.eventsAllowed && QuestStore.remindersAllowed ? "Calendar and Reminders access: allowed"
                         : "Needs Calendar and Reminders access").foregroundStyle(.secondary)
                    Spacer()
                    if QuestStore.undecided {
                        Button("Allow Access…") { QuestStore.shared.requestAccess { widgets.rebuildAll() } }
                    } else if !(QuestStore.eventsAllowed && QuestStore.remindersAllowed) {
                        Button("Open Privacy Settings…") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                        }
                    }
                }
            }
        case "gameshelf":
            Section("Game shelf") {
                Picker("Games from", selection: prop("source", "all")) {
                    Text("Everywhere").tag("all")
                    ForEach(GameLibrary.sources, id: \.name) { Text($0.name).tag($0.name) }
                }
                Toggle("Show titles", isOn: Binding(get: { widget.flag("titles", true) }, set: { v in prop("titles").wrappedValue = v ? "true" : "false" }))
                Text("Shows as many covers as fit; make the widget wider for more.").font(.caption).foregroundStyle(.secondary)
            }
        case "launcher":
            Section("Launcher button") {
                TextField("Label", text: prop("label", "Menu"))
                TextField("Icon (sf:symbol)", text: prop("icon", "sf:circle.grid.cross.fill"))
            }
        default:
            EmptyView()
        }
    }
}
