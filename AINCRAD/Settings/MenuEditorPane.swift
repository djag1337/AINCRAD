import AppKit
import SwiftUI

struct MenuEditorPane: View {
    @EnvironmentObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 8) {
            toolbar
            HSplitView {
                List(selection: $model.selectedItemID) {
                    OutlineGroup(model.menu.root, children: \.children) { item in
                        OutlineRow(item: item).tag(item.id)
                    }
                }
                .frame(minWidth: 260, idealWidth: 300)
                Group {
                    if let item = model.selectedItem {
                        ItemInspector(item: item)
                    } else {
                        Text("Select an item, or add one with ＋.").foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 400)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            Button { model.addItem(submenu: false) } label: { Image(systemName: "plus") }.help("Add item")
            Button { model.addItem(submenu: true) } label: { Image(systemName: "folder.badge.plus") }.help("Add submenu")
            Button { model.duplicateSelected() } label: { Image(systemName: "plus.square.on.square") }.help("Duplicate")
                .disabled(model.selectedItemID == nil)
            Button { model.deleteSelected() } label: { Image(systemName: "trash") }.help("Delete")
                .disabled(model.selectedItemID == nil)
            Divider().frame(height: 18)
            Button { model.moveSelected(-1) } label: { Image(systemName: "arrow.up") }.help("Move up")
            Button { model.moveSelected(1) } label: { Image(systemName: "arrow.down") }.help("Move down")
            Button { model.outdentSelected() } label: { Image(systemName: "arrow.left.to.line") }.help("Move out of its submenu")
            Button { model.indentSelected() } label: { Image(systemName: "arrow.right.to.line") }.help("Move into the submenu above")
            Divider().frame(height: 18)
            Button { model.undoMenu() } label: { Image(systemName: "arrow.uturn.backward") }.help("Undo (⌘Z)")
                .keyboardShortcut("z", modifiers: .command).disabled(!model.canUndoMenu)
            Button { model.redoMenu() } label: { Image(systemName: "arrow.uturn.forward") }.help("Redo (⇧⌘Z)")
                .keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!model.canRedoMenu)
            Spacer()
            Button("Import…") { model.importMenu() }
            Button("Export…") { model.exportMenu() }
            Button("Preview") { model.previewMenu() }.help("Open the launcher with these edits, unsaved")
            Button("Revert") { model.revertMenu() }.disabled(!model.menuDirty)
            Button("Save") { model.saveMenu() }.keyboardShortcut("s", modifiers: .command)
                .disabled(!model.menuDirty).buttonStyle(.borderedProminent)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }
}

struct OutlineRow: View {
    let item: MenuItem

    var body: some View {
        HStack(spacing: 6) {
            ItemIcon(spec: IconCache.defaultSpec(for: item), size: 16)
            Text(item.name).strikethrough(item.hidden == true).foregroundStyle(item.hidden == true ? .secondary : .primary)
            if let p = item.provider {
                Text(p == "applications" ? "all apps" : p == "appCategories" ? "apps by category" : p == "recentApps" ? "recent apps" : "extension").font(.caption).foregroundStyle(.secondary)
            }
            if let s = item.shortcut, let spec = HotKey.parse(s) { Spacer(); Text(HotKey.display(spec)).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct ItemIcon: View {
    let spec: String
    let size: CGFloat

    var body: some View {
        if let cg = IconCache.shared.image(spec, size: size, tint: IconCache.isSymbol(spec) ? .secondaryLabelColor : nil,
                                           scale: NSScreen.main?.backingScaleFactor ?? 1) {
            Image(nsImage: NSImage(cgImage: cg, size: NSSize(width: size, height: size)))
        } else {
            Image(systemName: "questionmark.square.dashed").frame(width: size, height: size)
        }
    }
}

struct ItemInspector: View {
    @EnvironmentObject var model: SettingsModel
    let item: MenuItem

    private static let symbols = ["star.fill", "folder.fill", "globe", "gearshape.fill", "gamecontroller.fill", "music.note",
                                  "film.fill", "book.fill", "terminal.fill", "hammer.fill", "paintbrush.fill", "camera.fill",
                                  "message.fill", "envelope.fill", "cart.fill", "house.fill", "doc.fill", "photo.fill",
                                  "bolt.fill", "heart.fill", "shield.fill", "person.fill", "clock.fill", "square.grid.3x3.fill"]

    private func edit(_ field: String, _ change: (inout MenuItem) -> Void) {
        var i = item
        change(&i)
        model.updateSelected(i, field: field)
    }

    private func bind<V>(_ path: WritableKeyPath<MenuItem, V>, _ field: String) -> Binding<V> {
        Binding(get: { item[keyPath: path] }, set: { v in edit(field) { $0[keyPath: path] = v } })
    }

    private func optionalText(_ path: WritableKeyPath<MenuItem, String?>, _ field: String) -> Binding<String> {
        Binding(get: { item[keyPath: path] ?? "" },
                set: { v in edit(field) { $0[keyPath: path] = v.isEmpty ? nil : v } })
    }

    private enum Kind: String { case action, submenu, dynamic }

    private var kind: Binding<Kind> {
        Binding(get: { item.provider != nil ? .dynamic : item.children != nil ? .submenu : .action },
                set: { k in edit("kind") { i in
                    switch k {
                    case .action: i.children = nil; i.provider = nil; i.action = i.action ?? .url("https://")
                    case .submenu: i.action = nil; i.provider = nil; i.children = i.children ?? []
                    case .dynamic: i.action = nil; i.children = nil; i.provider = i.provider ?? "applications"
                    }
                } })
    }

    private var actionType: Binding<String> {
        Binding(get: { item.action?.parts.0 ?? "url" },
                set: { t in edit("actionType") { i in
                    let target = t == "builtin" ? "reload" : (i.action?.parts.1 ?? "")
                    i.action = MenuAction(type: t, target: target)
                } })
    }

    private var actionTarget: Binding<String> {
        Binding(get: { item.action?.parts.1 ?? "" },
                set: { v in edit("target") { i in i.action = MenuAction(type: i.action?.parts.0 ?? "url", target: v) } })
    }

    private func conditionText(_ path: WritableKeyPath<MenuItem.Conditions, String?>, _ field: String) -> Binding<String> {
        Binding(get: { item.visibleWhen?[keyPath: path] ?? "" },
                set: { v in edit(field) { i in
                    var c = i.visibleWhen ?? MenuItem.Conditions()
                    c[keyPath: path] = v.isEmpty ? nil : v
                    i.visibleWhen = c == MenuItem.Conditions() ? nil : c
                } })
    }

    var body: some View {
        Form {
            Section("Item") {
                TextField("Name", text: bind(\.name, "name"))
                LabeledContent("Icon") {
                    HStack {
                        ItemIcon(spec: IconCache.defaultSpec(for: item), size: 22)
                        TextField("automatic", text: optionalText(\.icon, "icon")).labelsHidden().frame(minWidth: 150)
                        Menu("Symbols") {
                            ForEach(Self.symbols, id: \.self) { s in
                                Button { edit("icon") { $0.icon = "sf:" + s } } label: { Label(s, systemImage: s) }
                            }
                        }
                        .fixedSize()
                        Button("Image…") {
                            let panel = NSOpenPanel()
                            panel.allowedContentTypes = [.png, .jpeg, .icns, .tiff]
                            if panel.runModal() == .OK, let url = panel.url { edit("icon") { $0.icon = "image:" + url.path } }
                        }
                    }
                }
                Picker("Type", selection: kind) {
                    Text("Action").tag(Kind.action)
                    Text("Submenu").tag(Kind.submenu)
                    Text("Dynamic list").tag(Kind.dynamic)
                }
                .pickerStyle(.segmented)
            }

            switch kind.wrappedValue {
            case .action: actionSection
            case .submenu:
                Section("Submenu") {
                    Text("\(item.children?.count ?? 0) items. Use ＋ with this selected to add inside it, or → to move the item above into it.")
                        .foregroundStyle(.secondary)
                }
            case .dynamic:
                Section("Dynamic list") {
                    Picker("Shows", selection: Binding(get: { item.provider ?? "applications" },
                                                       set: { v in edit("provider") { $0.provider = v } })) {
                        Text("Applications by category").tag("appCategories")
                        Text("Games (Steam, GOG, Epic, Minecraft, game apps)").tag("games")
                        Text("All installed applications").tag("applications")
                        Text("Recently used applications").tag("recentApps")
                        ForEach(model.extensions.menuProviders, id: \.id) { Text($0.name).tag($0.id) }
                    }
                }
            }

            Section("Appearance") {
                TextField("Description (info panel)", text: optionalText(\.description, "description"), axis: .vertical)
                    .lineLimit(1...3)
                LabeledContent("Highlight colour") {
                    HStack {
                        if item.accent != nil {
                            ColorPicker("", selection: hexColor(Binding(get: { item.accent ?? "#F2A516" },
                                                                        set: { v in edit("accent") { $0.accent = v } })))
                                .labelsHidden()
                            Button("Use theme colour") { edit("accent") { $0.accent = nil } }
                        } else {
                            Button("Custom…") { edit("accent") { $0.accent = "#3FA9F5" } }
                        }
                    }
                }
                Toggle("Hidden", isOn: Binding(get: { item.hidden == true }, set: { v in edit("hidden") { $0.hidden = v ? true : nil } }))
            }

            Section("When to show") {
                Picker("Only on display", selection: conditionText(\.display, "display")) {
                    Text("Any display").tag("")
                    ForEach(NSScreen.screens.map(\.localizedName), id: \.self) { Text($0).tag($0) }
                    if let d = item.visibleWhen?.display, !NSScreen.screens.contains(where: { $0.localizedName == d }) {
                        Text("\(d) (disconnected)").tag(d)
                    }
                }
                TextField("Only while this app runs (bundle id)", text: conditionText(\.appRunning, "appRunning"))
                TextField("Only while this app is not running", text: conditionText(\.appNotRunning, "appNotRunning"))
                TextField("Only if this app is installed", text: conditionText(\.appInstalled, "appInstalled"))
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var actionSection: some View {
        Section("Action") {
            Picker("Does", selection: actionType) {
                Text("Open application").tag("app")
                Text("Open file or folder").tag("open")
                Text("Open website / URL").tag("url")
                Text("Run a Shortcut").tag("shortcut")
                Text("Run shell command").tag("shell")
                Text("AINCRAD command").tag("builtin")
            }
            switch actionType.wrappedValue {
            case "builtin":
                Picker("Command", selection: actionTarget) {
                    Text("Reload configuration").tag("reload")
                    Text("Open settings").tag("settings")
                    Text("Show menu file").tag("openConfig")
                    Text("Show log").tag("openLog")
                    Text("Pause activation").tag("pause")
                    Text("Quit AINCRAD").tag("quit")
                }
            case "app", "open":
                LabeledContent(actionType.wrappedValue == "app" ? "Application" : "Path") {
                    HStack {
                        TextField(actionType.wrappedValue == "app" ? "path or bundle id" : "~/Documents", text: actionTarget).labelsHidden()
                        Button("Choose…") { choose(app: actionType.wrappedValue == "app") }
                    }
                }
            case "shell":
                TextField("Command", text: actionTarget, axis: .vertical).lineLimit(1...4).font(.system(.body, design: .monospaced))
                if !model.settings.allowShellCommands {
                    Text("Shell commands are blocked until enabled in General › Safety.").font(.caption).foregroundStyle(.orange)
                }
            case "shortcut":
                TextField("Shortcut name (from the Shortcuts app)", text: actionTarget)
            default:
                TextField("URL", text: actionTarget)
            }
            LabeledContent("Global shortcut") {
                ShortcutRecorder(spec: Binding(get: { item.shortcut.flatMap(HotKey.parse) },
                                               set: { v in edit("shortcut") { $0.shortcut = v.map(HotKey.string) } }))
            }
        }
    }

    private func choose(app: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = !app
        panel.canChooseFiles = true
        if app {
            panel.allowedContentTypes = [.application]
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let home = NSHomeDirectory()
        let path = url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
        edit("target") { i in
            i.action = app ? .app(url.path) : .open(path)
            if i.name.hasPrefix("New Item") { i.name = AppScanner.displayName(url.path) }
        }
    }
}
