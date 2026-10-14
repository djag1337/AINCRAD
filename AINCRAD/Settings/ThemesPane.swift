import AppKit
import SwiftUI

struct ThemesPane: View {
    @EnvironmentObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Button { model.undoTheme() } label: { Image(systemName: "arrow.uturn.backward") }.help("Undo (⌘Z)")
                    .keyboardShortcut("z", modifiers: .command).disabled(!model.canUndoTheme)
                Button { model.redoTheme() } label: { Image(systemName: "arrow.uturn.forward") }.help("Redo (⇧⌘Z)")
                    .keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!model.canRedoTheme)
                Spacer()
                Button(model.publishingTheme ? "Publishing…" : "Publish") { model.publishTheme() }
                    .disabled(model.publishingTheme)
                    .help("Add this theme to your catalog on GitHub")
                Button("Preview") { model.previewTheme() }.help("Open the launcher in this theme, unsaved")
                Button("Revert") { model.revertTheme() }.disabled(!model.themeDirty)
                Button("Save") { model.saveTheme() }.keyboardShortcut("s", modifiers: .command)
                    .disabled(!model.themeDirty).buttonStyle(.borderedProminent)
            }
            .buttonStyle(.bordered)
            HSplitView {
                themeList.frame(minWidth: 200, idealWidth: 220, maxWidth: 280)
                ThemeEditor().frame(minWidth: 460)
            }
        }
    }

    private var themeList: some View {
        VStack(spacing: 6) {
            List(selection: Binding(get: { model.editingThemeID }, set: { id in
                guard let id, id != model.editingThemeID else { return }
                if model.themeDirty { model.saveTheme() }
                model.selectTheme(id)
            })) {
                ForEach(model.themeIDs, id: \.self) { id in
                    HStack {
                        Text(id)
                        Spacer()
                        if id == model.settings.theme { Text("in use").font(.caption).foregroundStyle(.secondary) }
                    }
                    .tag(Optional(id))
                }
            }
            HStack(spacing: 4) {
                Button("Use") { model.useTheme(model.editingThemeID) }
                    .disabled(model.editingThemeID == model.settings.theme)
                Button { model.duplicateTheme() } label: { Image(systemName: "plus.square.on.square") }.help("Duplicate")
                Button { model.importTheme() } label: { Image(systemName: "square.and.arrow.down") }.help("Import…")
                Button { model.exportTheme() } label: { Image(systemName: "square.and.arrow.up") }.help("Export…")
                Button { model.deleteTheme() } label: { Image(systemName: "trash") }.help("Delete")
                    .disabled(model.editingThemeID == model.settings.theme)
            }
            .buttonStyle(.bordered)
        }
    }
}

struct ThemeEditor: View {
    @EnvironmentObject var model: SettingsModel

    private static let colors: [(String, WritableKeyPath<Theme.Colors, String>)] = [
        ("Accent (selection)", \.accent), ("Text on accent", \.accentText),
        ("Panel", \.panel), ("Panel text", \.panelText), ("Panel border", \.panelBorder), ("Hover", \.hover),
        ("Icon badge", \.iconBadge), ("Icon glyph", \.iconGlyph),
        ("Round button", \.circle), ("Round button icon", \.circleIcon), ("Round button border", \.circleBorder),
        ("Info panel footer", \.infoFooter), ("Info panel icon", \.infoIcon),
        ("Caption", \.caption), ("Caption shadow", \.captionShadow), ("Shadow", \.shadow), ("Screen tint", \.backdrop),
    ]

    @State private var families = NSFontManager.shared.availableFontFamilies.sorted()

    /// Copies a font file into ~/Library/Fonts, registers it for this session and uses it.
    private func installFont() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.font]
        panel.message = "Choose a .ttf or .otf font (for example a fan-made SAO font you downloaded)"
        guard panel.runModal() == .OK, let src = panel.url else { return }
        let fontsDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Fonts")
        let dest = fontsDir.appendingPathComponent(src.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: fontsDir, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.copyItem(at: src, to: dest) }
            CTFontManagerRegisterFontsForURL(dest as CFURL, .process, nil)
            let descriptors = CTFontManagerCreateFontDescriptorsFromURL(dest as CFURL) as? [CTFontDescriptor] ?? []
            let family = descriptors.first.flatMap { CTFontDescriptorCopyAttribute($0, kCTFontFamilyNameAttribute) as? String }
            families = NSFontManager.shared.availableFontFamilies.sorted()
            if let family {
                model.editTheme(key: "family") { $0.font.family = family }
                model.message = "Installed “\(family)” and set it as this theme's font. Save the theme to keep it."
            }
        } catch {
            model.message = "Couldn't install the font: \(error.localizedDescription)"
        }
    }
    private static let builtinSounds = ["open", "select", "back", "close", "hover", "error"]

    private func number(_ path: WritableKeyPath<Theme, Double>, _ key: String) -> Binding<Double> {
        model.themeBinding(path, key: key)
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Theme name", text: model.themeBinding(\.name, key: "name"))
            }
            Section("Colours") {
                ForEach(Self.colors, id: \.0) { title, path in
                    let full = (\Theme.colors).appending(path: path)
                    LabeledContent(title) {
                        HStack {
                            Text(model.theme[keyPath: full]).font(.caption.monospaced()).foregroundStyle(.secondary)
                            ColorPicker("", selection: hexColor(model.themeBinding(full, key: title)), supportsOpacity: true)
                                .labelsHidden()
                        }
                    }
                }
            }
            Section("Text") {
                HStack {
                    Picker("Text font", selection: model.themeBinding(\.font.family, key: "family")) {
                        ForEach(families, id: \.self) { Text($0).tag($0) }
                    }
                    Button("Install Font…") { installFont() }
                }
                Picker("Title font", selection: model.themeBinding(\.font.display, key: "display")) {
                    Text("Same as above").tag("")
                    ForEach(families, id: \.self) { Text($0).tag($0) }
                }
                SliderRow(title: "Item text size", value: number(\.font.size, "size"), range: 10...32)
                SliderRow(title: "Title text size", value: number(\.font.captionSize, "captionSize"), range: 12...40)
            }
            Section("Layout") {
                SliderRow(title: "Round button size", value: number(\.geometry.circleDiameter, "d"), range: 32...96)
                SliderRow(title: "Round button spacing", value: number(\.geometry.circleSpacing, "cs"), range: 0...40)
                SliderRow(title: "Item width", value: number(\.geometry.itemWidth, "iw"), range: 120...400)
                SliderRow(title: "Item height", value: number(\.geometry.itemHeight, "ih"), range: 24...72)
                SliderRow(title: "Item spacing", value: number(\.geometry.itemSpacing, "is"), range: 0...20)
                SliderRow(title: "Column gap", value: number(\.geometry.columnGap, "cg"), range: 4...60)
                SliderRow(title: "Corner radius", value: number(\.geometry.cornerRadius, "cr"), range: 0...20)
                Stepper("Visible rows each side: \(model.theme.geometry.visibleRows)",
                        value: model.themeBinding(\.geometry.visibleRows, key: "vr"), in: 2...12)
                Toggle("Info panel", isOn: model.themeBinding(\.effects.showInfoPanel, key: "info"))
                Toggle("HUD frame around the screen", isOn: model.themeBinding(\.effects.hud, key: "hud"))
                SliderRow(title: "Info panel width", value: number(\.geometry.infoPanelWidth, "ipw"), range: 160...400)
                SliderRow(title: "Info panel height", value: number(\.geometry.infoPanelHeight, "iph"), range: 200...600)
            }
            Section("Effects") {
                SliderRow(title: "Border width", value: number(\.effects.borderWidth, "bw"), range: 0...4, step: 0.5, format: "%.1f")
                SliderRow(title: "Shadow radius", value: number(\.effects.shadowRadius, "sr"), range: 0...30)
                SliderRow(title: "Shadow opacity", value: number(\.effects.shadowOpacity, "so"), range: 0...1, step: 0.05, format: "%.2f")
                SliderRow(title: "Selection glow", value: number(\.effects.selectedGlow, "glow"), range: 0...30)
                SliderRow(title: "Glow opacity", value: number(\.effects.glowOpacity, "go"), range: 0...1, step: 0.05, format: "%.2f")
                SliderRow(title: "Ring width", value: number(\.effects.selectedRingWidth, "ring"), range: 0...6, step: 0.5, format: "%.1f")
                SliderRow(title: "Perspective tilt (°)", value: number(\.effects.tilt, "tilt"), range: 0...25)
            }
            Section("Motion") {
                Picker("Preset", selection: Binding(get: { model.theme.animation.preset }, set: { name in
                    model.editTheme { t in
                        let speed = t.animation.speed
                        t.animation = .preset(name)
                        t.animation.speed = speed
                    }
                })) {
                    Text("Classic").tag("classic")
                    Text("Snappy").tag("snappy")
                    Text("Gentle").tag("gentle")
                    Text("Minimal").tag("minimal")
                }
                SliderRow(title: "Speed", value: number(\.animation.speed, "speed"), range: 0.25...3, step: 0.05, format: "%.2f×")
                DisclosureGroup("Fine-tune durations") {
                    SliderRow(title: "Open (s)", value: number(\.animation.open, "ao"), range: 0...1, step: 0.01, format: "%.2f")
                    SliderRow(title: "Button stagger (s)", value: number(\.animation.stagger, "ast"), range: 0...0.2, step: 0.005, format: "%.3f")
                    SliderRow(title: "Submenu (s)", value: number(\.animation.column, "ac"), range: 0...1, step: 0.01, format: "%.2f")
                    SliderRow(title: "Row stagger (s)", value: number(\.animation.rowStagger, "ars"), range: 0...0.1, step: 0.002, format: "%.3f")
                    SliderRow(title: "Move (s)", value: number(\.animation.move, "am"), range: 0...1, step: 0.01, format: "%.2f")
                    SliderRow(title: "Hover (s)", value: number(\.animation.highlight, "ah"), range: 0...0.5, step: 0.01, format: "%.2f")
                    SliderRow(title: "Close (s)", value: number(\.animation.close, "acl"), range: 0...1, step: 0.01, format: "%.2f")
                    SliderRow(title: "Drop distance", value: number(\.animation.dropDistance, "add"), range: 0...80)
                    SliderRow(title: "Slide distance", value: number(\.animation.slideDistance, "asd"), range: 0...80)
                }
            }
            Section("Sounds") {
                SliderRow(title: "Volume", value: number(\.sounds.volume, "vol"), range: 0...1, step: 0.05, format: "%.2f")
                soundRow("Open", \.open)
                soundRow("Select", \.select)
                soundRow("Back", \.back)
                soundRow("Close", \.close)
                soundRow("Hover", \.hover)
                soundRow("Error", \.error)
            }
        }
        .formStyle(.grouped)
    }

    private func soundRow(_ title: String, _ path: WritableKeyPath<Theme.Sounds, String>) -> some View {
        let full = (\Theme.sounds).appending(path: path)
        let binding = model.themeBinding(full, key: "sound." + title)
        let custom = !binding.wrappedValue.isEmpty && !binding.wrappedValue.hasPrefix("builtin:")
        return LabeledContent(title) {
            HStack {
                Picker("", selection: binding) {
                    Text("None").tag("")
                    ForEach(Self.builtinSounds, id: \.self) { Text("Built-in: \($0)").tag("builtin:" + $0) }
                    if custom { Text((binding.wrappedValue as NSString).lastPathComponent).tag(binding.wrappedValue) }
                }
                .labelsHidden()
                Button("File…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.audio]
                    if panel.runModal() == .OK, let url = panel.url { binding.wrappedValue = url.path }
                }
            }
        }
    }
}

struct AboutPane: View {
    @EnvironmentObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("AINCRAD").font(.largeTitle.weight(.semibold))
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
                .foregroundStyle(.secondary)
            Text("An SAO-style launcher for macOS. Unofficial fan project, not affiliated with the Sword Art Online rights holders.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 420)
            HStack {
                Button("Configuration Folder") { NSWorkspace.shared.open(model.store.directory) }
                Button("Backups") {
                    try? FileManager.default.createDirectory(at: model.store.backupsURL, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(model.store.backupsURL)
                }
                Button("Log") { NSWorkspace.shared.open(Log.fileURL) }
            }
            if !model.store.problems.isEmpty {
                VStack(alignment: .leading) {
                    ForEach(model.store.problems, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
