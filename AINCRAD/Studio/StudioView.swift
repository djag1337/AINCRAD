import AppKit
import SwiftUI

final class StudioWindowController: NSWindowController, NSWindowDelegate {
    let model: StudioModel
    var onClose: (() -> Void)?

    init(model: StudioModel) {
        self.model = model
        let window = NSWindow(contentViewController: NSHostingController(rootView: StudioView().environmentObject(model)))
        window.title = "Extension Studio"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1120, height: 720))
        window.minSize = NSSize(width: 900, height: 560)
        window.setFrameAutosaveName("AINCRADStudio")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.ensureOnScreen()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.dirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Save “\(model.name)” before closing?"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return model.save() != nil
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { self.onClose?() }
    }
}

struct StudioView: View {
    @EnvironmentObject var model: StudioModel

    var body: some View {
        NavigationSplitView {
            List(StudioModel.Section.allCases, selection: Binding(get: { model.section }, set: { if let s = $0 { model.section = s } })) { s in
                Label(s.rawValue, systemImage: s.symbol).tag(s)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 160, max: 200)
        } detail: {
            Group {
                switch model.section {
                case .basics: StudioBasics()
                case .scripts: StudioScripts()
                case .looks: StudioLooks()
                case .menus: StudioMenus()
                case .widgets: StudioWidgets()
                case .publish: StudioPublish()
                }
            }
            .navigationTitle(model.name + (model.dirty ? " — edited" : ""))
            .toolbar {
                ToolbarItemGroup {
                    if let p = model.problem {
                        Label(p, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).lineLimit(1).frame(maxWidth: 320)
                    }
                    Button { model.save() } label: { Label("Save", systemImage: "square.and.arrow.down") }
                        .keyboardShortcut("s", modifiers: .command)
                        .disabled(model.problem != nil)
                }
            }
        }
        .alert(model.message ?? "", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }
}

// MARK: Scripts

struct StudioScripts: View {
    @EnvironmentObject var model: StudioModel
    @State private var showConsole = true

    var body: some View {
        HSplitView {
            StudioPalette().frame(minWidth: 280, idealWidth: 300, maxWidth: 360)
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Button { model.undoEdit() } label: { Image(systemName: "arrow.uturn.backward") }
                        .keyboardShortcut("z", modifiers: .command).disabled(!model.canUndo).help("Undo")
                    Button { model.redoEdit() } label: { Image(systemName: "arrow.uturn.forward") }
                        .keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!model.canRedo).help("Redo")
                    Text("Drag blocks from the left. Event blocks start a script; ▶ tests it right now.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Toggle(isOn: $showConsole) { Label("Console", systemImage: "terminal") }.toggleStyle(.button)
                }
                .padding(8)
                Divider()
                StudioCanvas()
                if showConsole {
                    Divider()
                    StudioConsole().frame(height: 140)
                }
            }
            .frame(minWidth: 520)
        }
    }
}

struct StudioPalette: View {
    @EnvironmentObject var model: StudioModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 10) {
                ForEach(BlockCategory.allCases, id: \.self) { c in
                    Button { model.category = c } label: {
                        VStack(spacing: 3) {
                            Circle().fill(BlockStyle.fill(c)).frame(width: 22, height: 22)
                                .overlay(Circle().stroke(model.category == c ? Color.primary : .clear, lineWidth: 2))
                            Text(c.title).font(.system(size: 10)).foregroundStyle(model.category == c ? .primary : .secondary)
                        }
                        .frame(width: 66)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.category.title).font(.headline)
                    ForEach(BlockSpec.all.filter { $0.category == model.category }, id: \.op) { spec in
                        let block = spec.make()
                        Group {
                            if spec.isReporter {
                                ReporterView(block: block, spec: spec, live: false)
                            } else {
                                StatementView(block: block, live: false)
                            }
                        }
                        .help(spec.help.isEmpty ? spec.label : spec.help)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // Dragging a block from the canvas back onto the palette deletes it, like Scratch.
        .dropDestination(for: String.self) { items, _ in
            guard let p = items.first.flatMap(BlockPayload.decode), p.fromCanvas else { return false }
            model.delete(p.block.id)
            return true
        }
    }
}

struct StudioCanvas: View {
    @EnvironmentObject var model: StudioModel
    @State private var newTargeted = false

    var body: some View {
        GeometryReader { geo in
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .top, spacing: 36) {
                ForEach(model.scripts) { script in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top, spacing: 6) {
                            StatementView(block: script.trigger, live: true).fixedSize()
                            Button { model.test(script) } label: { Image(systemName: "play.fill") }
                                .buttonStyle(.borderedProminent).controlSize(.small).help("Run this script now")
                                .padding(.top, 10)
                        }
                        DropGap(slot: .scriptTop(script.id), minHeight: script.steps.isEmpty ? 26 : 6)
                        ForEach(script.steps) { StatementView(block: $0, live: true) }
                    }
                    .fixedSize()
                }
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                    .foregroundStyle(newTargeted ? Color.accentColor : .secondary.opacity(0.5))
                    .frame(width: 220, height: 90)
                    .overlay(Text("Drop an event block here\nto start a new script").font(.caption)
                        .multilineTextAlignment(.center).foregroundStyle(.secondary))
                    .dropDestination(for: String.self) { items, _ in
                        guard let p = items.first.flatMap(BlockPayload.decode) else { return false }
                        return model.drop(p, at: nil)
                    } isTargeted: { newTargeted = $0 }
            }
            .padding(24)
            // Fill the viewport so scripts start top-left instead of floating in the middle.
            .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
        }
        }
        .background(
            Canvas { ctx, size in
                // Dotted grid, like Scratch's stage area.
                for x in stride(from: 0, through: size.width, by: 22) {
                    for y in stride(from: 0, through: size.height, by: 22) {
                        ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.6, height: 1.6)), with: .color(.secondary.opacity(0.25)))
                    }
                }
            }
        )
    }
}

struct StudioConsole: View {
    @EnvironmentObject var model: StudioModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Console").font(.caption.bold())
                Spacer()
                Button("Clear") { model.log = [] }.controlSize(.small)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(model.log.enumerated()), id: \.offset) { i, line in
                            Text(line).font(.system(.caption, design: .monospaced)).textSelection(.enabled).id(i)
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: model.log.count) { _, n in proxy.scrollTo(n - 1, anchor: .bottom) }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

// MARK: Basics, looks, menus, widgets, publish

struct StudioBasics: View {
    @EnvironmentObject var model: StudioModel

    var body: some View {
        Form {
            Section("Extension") {
                TextField("Name", text: Binding(get: { model.name }, set: { model.setName($0) }))
                TextField("Identifier", text: Binding(get: { model.extID }, set: { model.extID = $0; model.idEdited = true }))
                    .font(.system(.body, design: .monospaced))
                TextField("Version", text: $model.version)
                TextField("Author", text: $model.author)
                TextField("Description", text: $model.summary, axis: .vertical).lineLimit(2...5)
            }
            Section {
                if model.permissions.isEmpty {
                    Label("None. This extension only uses blocks that stay inside AINCRAD.", systemImage: "checkmark.shield")
                }
                ForEach(model.permissions, id: \.self) { p in
                    Label(p == "network" ? "Network: uses “fetch” to download from the web"
                          : "Files: reads files outside its own folder", systemImage: "lock.shield").foregroundStyle(.orange)
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("Worked out from the blocks you use. People installing your extension approve these.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct StudioLooks: View {
    @EnvironmentObject var model: StudioModel
    private let colorKeys: [(String, WritableKeyPath<Theme.Colors, String>)] = [
        ("Accent", \.accent), ("Panel", \.panel), ("Panel text", \.panelText), ("Round button", \.circle),
        ("Button icon", \.circleIcon), ("Icon badge", \.iconBadge), ("Info footer", \.infoFooter),
    ]

    var body: some View {
        Form {
            Section {
                Menu("Add a Copy of One of My Themes") {
                    ForEach(model.store.themeIDs(), id: \.self) { id in Button(id) { model.addTheme(from: id) } }
                }
                .fixedSize()
            } footer: {
                Text("Themes travel with the extension; people install them with “Install Themes”. Fine-tune everything else in Settings › Themes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach($model.themes) { $t in
                Section {
                    TextField("Name", text: $t.theme.name)
                    ForEach(colorKeys, id: \.0) { title, key in
                        ColorPicker(title, selection: hexColor(Binding(get: { t.theme.colors[keyPath: key] },
                                                                        set: { t.theme.colors[keyPath: key] = $0 })))
                    }
                    Picker("Motion", selection: Binding(get: { t.theme.animation.preset }, set: { t.theme.animation = .preset($0) })) {
                        ForEach(["classic", "snappy", "gentle", "minimal"], id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    Button("Remove Theme", role: .destructive) { model.themes.removeAll { $0.id == t.id } }
                } header: {
                    Text(t.theme.name)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct StudioMenus: View {
    @EnvironmentObject var model: StudioModel

    var body: some View {
        Form {
            Section {
                Button("Add Menu") {
                    let n = model.menus.count + 1
                    model.menus.append(.init(id: "menu\(n)", name: "Menu \(n)",
                                             items: [MenuItem(name: "Apple", icon: "sf:globe", action: .url("https://www.apple.com"))]))
                }
            } footer: {
                Text("People add these to their launcher as a Dynamic list (Settings › Menu › Type › Dynamic list).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach($model.menus, id: \.id) { $menu in
                Section {
                    TextField("Menu name", text: $menu.name)
                    ForEach($menu.items) { $item in
                        HStack {
                            TextField("Name", text: $item.name).frame(width: 150)
                            Picker("", selection: Binding(get: { item.action?.parts.0 ?? "url" },
                                                          set: { item.action = MenuAction(type: $0, target: item.action?.parts.1 ?? "") })) {
                                Text("App").tag("app"); Text("File").tag("open"); Text("URL").tag("url"); Text("Shortcut").tag("shortcut")
                            }
                            .labelsHidden().frame(width: 100)
                            TextField("Target", text: Binding(get: { item.action?.parts.1 ?? "" },
                                                              set: { item.action = MenuAction(type: item.action?.parts.0 ?? "url", target: $0) }))
                            Button { menu.items.removeAll { $0.id == item.id } } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                        }
                    }
                    HStack {
                        Button("Add Item") { menu.items.append(MenuItem(name: "New Item", action: .url("https://"))) }
                        Spacer()
                        Button("Remove Menu", role: .destructive) { model.menus.removeAll { $0.id == menu.id } }
                    }
                } header: {
                    Text("\(menu.name)  ·  ext:\(model.extID)/\(menu.id)").font(.caption.monospaced())
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct StudioWidgets: View {
    @EnvironmentObject var model: StudioModel

    private var sources: [(key: String, title: String)] {
        model.gaugeSources + StatSource.allCases.map { ($0.rawValue, $0.title) }
    }

    var body: some View {
        Form {
            Section {
                Button("Add Widget Preset") {
                    let src = model.gaugeSources.first?.key ?? "cpu"
                    model.widgets.append(.init(name: "My Gauge", widget: WidgetConfig(type: "stat", width: 260, height: 70,
                                                                                     props: ["source": src, "show": "bar"])))
                }
            } footer: {
                Text("Presets appear in Settings › Widgets › Library once the extension is enabled. Pick a gauge to show what your “set gauge” blocks write.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            // Bound by stable id, not index: removing one while the list redraws can't go out of range.
            ForEach($model.widgets, id: \.widget.id) { $def in
                Section {
                    TextField("Name in the library", text: $def.name)
                    Picker("Shows", selection: Binding(get: { def.widget.props["source"] ?? "cpu" },
                                                       set: { def.widget.props["source"] = $0 })) {
                        ForEach(sources, id: \.key) { Text($0.title).tag($0.key) }
                    }
                    Picker("As", selection: Binding(get: { def.widget.props["show"] ?? "bar" },
                                                    set: { def.widget.props["show"] = $0 })) {
                        Text("Bar").tag("bar"); Text("Ring").tag("ring"); Text("Text").tag("text")
                    }
                    TextField("Label", text: Binding(get: { def.widget.props["label"] ?? "" },
                                                     set: { def.widget.props["label"] = $0 }))
                    Button("Remove", role: .destructive) { model.widgets.removeAll { $0.widget.id == def.widget.id } }
                } header: {
                    Text(def.name)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct StudioPublish: View {
    @EnvironmentObject var model: StudioModel

    var body: some View {
        Form {
            Section("Check") {
                if let p = model.problem {
                    Label(p, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                } else {
                    Label("Ready: \(model.scripts.count) scripts, \(model.themes.count) themes, \(model.menus.count) menus, \(model.widgets.count) widget presets.",
                          systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                }
            }
            Section {
                Button("Save to My Extensions") {
                    if model.save() != nil {
                        model.message = "Saved. Turn it on in Settings › Extensions to run its scripts."
                    }
                }
                Button("Export .aincrad File…") { model.export() }
                Button(model.publishing ? "Publishing…" : "Publish to My Catalog") { model.publish() }
                    .disabled(model.publishing || model.problem != nil)
                    .help("Copies it into your catalog repository, rebuilds the catalog, commits and pushes to GitHub")
                if let f = model.folder {
                    Button("Show Folder") { NSWorkspace.shared.activateFileViewerSelecting([f]) }
                }
            } header: {
                Text("Share")
            } footer: {
                Text("An .aincrad file is the whole extension in one file: send it to anyone with AINCRAD. Publish puts it in your catalog (\(model.store.settings.catalogRepoPath)) and pushes it, so it appears in everyone's Browse tab. The progress shows in the Scripts console.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
