import AppKit
import SwiftUI

struct BrowsePane: View {
    @EnvironmentObject var model: SettingsModel
    @ObservedObject var catalog: CatalogModel
    @State private var busy: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("", selection: $catalog.filter) {
                    Text("All").tag("all")
                    Text("Themes").tag("theme")
                    Text("Extensions").tag("extension")
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 260)
                TextField("Search", text: $catalog.search).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                Spacer()
                Button { Task { await catalog.load() } } label: { Image(systemName: "arrow.clockwise") }.help("Reload the catalog")
            }
            HStack(spacing: 6) {
                Text("Catalog:").font(.caption).foregroundStyle(.secondary)
                TextField("an https:// URL or a path to catalog.json",
                          text: Binding(get: { model.settings.catalogURL }, set: { v in model.update { $0.catalogURL = v } }))
                    .font(.caption).textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await catalog.load() } }
                if let name = catalog.index?.name { Text(name).font(.caption.bold()) }
            }
            content
        }
        .task { if catalog.status == .idle { await catalog.load() } }
    }

    @ViewBuilder private var content: some View {
        switch catalog.status {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            VStack(spacing: 10) {
                Image(systemName: "shippingbox").font(.largeTitle).foregroundStyle(.secondary)
                Text(message).foregroundStyle(.secondary)
                // No existence check here: even that touches ~/Documents, which can prompt.
                do {
                    Button("Use the Local Catalog in Documents/AINCRAD-catalog") {
                        model.update { $0.catalogURL = "~/Documents/AINCRAD-catalog/catalog.json" }
                        Task { await catalog.load() }
                    }
                    .buttonStyle(.borderedProminent)
                    Text("macOS may ask once whether AINCRAD can open files in your Documents folder.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Use the AINCRAD Community Catalog") {
                    model.update { $0.catalogURL = AppSettings.communityCatalog }
                    Task { await catalog.load() }
                }
                Button("Choose a catalog.json…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.json]
                    if panel.runModal() == .OK, let url = panel.url {
                        model.update { $0.catalogURL = url.path }
                        Task { await catalog.load() }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
                    ForEach(catalog.visibleItems) { item in card(item) }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func card(_ item: CatalogItem) -> some View {
        let state = catalog.state(item)
        return VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.25))
                if let img = catalog.previews[item.id] {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: item.type == "theme" ? "paintpalette" : "puzzlepiece.extension")
                        .font(.largeTitle).foregroundStyle(.secondary)
                }
            }
            .frame(height: 130)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            HStack {
                Text(item.name).font(.headline)
                Spacer()
                Text(item.type == "theme" ? "Theme" : "Extension").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.2)))
            }
            Text((item.author.map { "by \($0) · " } ?? "") + "v\(item.version)").font(.caption).foregroundStyle(.secondary)
            if let d = item.description { Text(d).font(.callout).lineLimit(3).fixedSize(horizontal: false, vertical: true) }
            if let p = item.permissions, !p.isEmpty {
                Label("Asks for: " + p.joined(separator: ", "), systemImage: "lock.shield").font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button(busy == item.id ? "Installing…" : state == .installed ? "Installed" : state == .update ? "Update" : "Install") {
                    busy = item.id
                    Task {
                        if let msg = await catalog.install(item) { model.message = msg }
                        busy = nil
                        model.refreshThemes()
                    }
                }
                .disabled(state == .installed || busy != nil)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }
}
