import AppKit
import SwiftUI

struct ExtensionsPane: View {
    @EnvironmentObject var model: SettingsModel
    @ObservedObject var extensions: ExtensionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Extensions add themes, menus, data sources and widget presets. They are data only: they can't run code, and anything outside their own folder needs your approval.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Open Folder") {
                    try? FileManager.default.createDirectory(at: extensions.folder, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(extensions.folder)
                }
                Button("Reload") { extensions.load() }
                Button("New Extension…") { model.actions.openStudio(nil) }.buttonStyle(.borderedProminent)
                Button("Create Example") {
                    do { _ = try extensions.createExample() } catch { model.message = error.localizedDescription }
                }
            }
            List {
                if extensions.extensions.isEmpty {
                    Text("No extensions installed. Put an extension folder in the Extensions folder, or create the example.")
                        .foregroundStyle(.secondary)
                }
                ForEach(extensions.extensions) { ext in ExtensionRow(extensions: extensions, ext: ext) }
                if !extensions.problems.isEmpty {
                    Section("Problems") {
                        ForEach(extensions.problems, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                    }
                }
            }
        }
    }
}

struct ExtensionRow: View {
    @EnvironmentObject var model: SettingsModel
    @ObservedObject var extensions: ExtensionManager
    let ext: LoadedExtension

    private var m: ExtensionManifest { ext.manifest }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "puzzlepiece.extension.fill").foregroundStyle(.secondary)
                Text(m.name).font(.headline)
                Text("\(m.version) · \(m.id)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(extensions.isEnabled(ext) ? "On" : "Off").font(.caption).foregroundStyle(.secondary)
                Toggle("Enabled", isOn: Binding(get: { extensions.isEnabled(ext) }, set: { on in
                    if on && !ext.requested.isEmpty && !confirm() { return }
                    extensions.setEnabled(ext, on)
                    model.actions.reloadAll()
                }))
                .toggleStyle(.switch)
                .labelsHidden()
            }
            if let d = m.description { Text(d).font(.callout) }
            HStack(spacing: 14) {
                summary("paintpalette", m.provides.themes?.count, "themes")
                summary("list.bullet", m.provides.menus?.count, "menus")
                summary("gauge.medium", m.provides.dataSources?.count, "data sources")
                summary("square.grid.2x2", m.provides.widgets?.count, "widget presets")
                summary("puzzlepiece", m.provides.scripts?.count, "scripts")
                if !ext.requested.isEmpty {
                    Label("Asks for: " + ext.requested.sorted().joined(separator: ", "), systemImage: "lock.shield")
                        .foregroundStyle(.orange)
                }
                Spacer()
                if (m.provides.themes?.isEmpty == false) {
                    Button("Install Themes") {
                        do {
                            let ids = try extensions.installThemes(ext)
                            model.refreshThemes()
                            model.message = "Installed: \(ids.joined(separator: ", ")). Choose one in Themes."
                        } catch { model.message = error.localizedDescription }
                    }
                }
                Button("Edit in Studio") { model.actions.openStudio(ext) }
                Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([ext.folder]) }
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private func summary(_ symbol: String, _ count: Int?, _ noun: String) -> some View {
        if let count, count > 0 { Label("\(count) \(count == 1 ? String(noun.dropLast()) : noun)", systemImage: symbol) }
    }

    private func confirm() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Enable “\(m.name)”?"
        let explain = ext.requested.sorted().map { p in
            p == "network" ? "• network: its data sources may download from the internet" :
            p == "files" ? "• files: its data sources may read files elsewhere on your Mac" : "• \(p)"
        }
        alert.informativeText = "This extension asks for:\n" + explain.joined(separator: "\n")
        alert.addButton(withTitle: "Allow and Enable")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
