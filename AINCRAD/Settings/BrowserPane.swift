import SwiftUI

/// Settings › Browser: opt in to AINCRAD Browser (installs from GitHub after you approve), the link between
/// the two apps, and the browser's own settings (the same form the browser shows when AINCRAD isn't installed).
struct BrowserPane: View {
    @EnvironmentObject var model: SettingsModel
    @State private var installed = BrowserLink.isInstalled
    @State private var status: String?
    @State private var busy = false

    private func bind<V>(_ path: WritableKeyPath<AppSettings, V>) -> Binding<V> {
        Binding(get: { model.settings[keyPath: path] }, set: { v in model.update { $0[keyPath: path] = v } })
    }

    var body: some View {
        Form {
            Section {
                Toggle("Use AINCRAD Browser", isOn: Binding(get: { installed }, set: { on in on ? install() : remove() }))
                    .disabled(busy)
                Text(installed
                     ? "Installed. It follows your AINCRAD theme, and its tabs, bookmarks and history are under Files › AINCRAD Browser in the launcher."
                     : "Not installed. Turning this on asks first, then downloads AINCRAD Browser from \(BrowserInstaller.releasePage) and puts it in Applications.")
                    .font(.caption).foregroundStyle(.secondary)
                if let status { Text(status).font(.callout) }
                HStack {
                    if installed { Button("Open AINCRAD Browser") { if let url = BrowserLink.appURL { NSWorkspace.shared.openApplication(at: url, configuration: .init()) } } }
                    Button("View on GitHub") { NSWorkspace.shared.open(URL(string: BrowserInstaller.releasePage)!) }
                }
            } header: { Text("AINCRAD Browser") }

            Section {
                Toggle("Open web links from the launcher in AINCRAD Browser", isOn: bind(\.openWebInAINCRADBrowser)).disabled(!installed)
                Toggle("Show its finished downloads as SAO bubbles", isOn: bind(\.browserDownloadBubbles)).disabled(!installed)
                Text("The apps stay separate. They talk through a small shared file and local notifications, with no macOS permissions. Private browser windows are never shared.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("The link") }

            if installed { BrowserPrefsForm() }
        }
        .formStyle(.grouped)
        .onAppear { installed = BrowserLink.isInstalled }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in installed = BrowserLink.isInstalled }
    }

    private func install() {
        busy = true; status = nil
        BrowserInstaller.installWithApproval(progress: { status = $0 }) { error in
            busy = false
            installed = BrowserLink.isInstalled
            status = error ?? "Installed."
        }
    }

    private func remove() {
        busy = true
        BrowserInstaller.removeWithApproval { error in
            busy = false
            installed = BrowserLink.isInstalled
            status = error ?? (installed ? nil : "Moved to the Trash.")
        }
    }
}
