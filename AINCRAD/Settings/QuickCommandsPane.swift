import SwiftUI

/// Settings › Quick Commands: every typed launcher command, what it does, the permission it needs,
/// and a switch. Commands that need a permission start off.
struct QuickCommandsPane: View {
    @EnvironmentObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Text("Type these in the launcher's search and press Return. Each one can be switched off. Any command that needs a macOS permission is off until you turn it on here, and macOS only asks for that permission the first time you actually run it — never while you're typing. AINCRAD never sends anything for you: messages and emails open as drafts, and you press Send.")
                    .font(.callout)
                Text("Type “commands” in the launcher to see this list there.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Commands") {
                ForEach(QuickCommands.all, id: \.id) { c in
                    HStack(alignment: .top, spacing: 12) {
                        Toggle("", isOn: Binding(
                            get: { QuickCommands.isOn(c, model.settings) },
                            set: { on in model.update { $0.quickCommands[c.id] = on } }))
                            .labelsHidden()
                            .toggleStyle(.switch)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(c.title).font(.headline)
                                Spacer()
                                Text(c.permission.map { "Needs: \($0)" } ?? "No permission needed")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(c.permission == nil ? Color.green.opacity(0.18) : Color.orange.opacity(0.22),
                                                in: RoundedRectangle(cornerRadius: 5))
                            }
                            Text(c.does).font(.callout)
                            Text(c.example).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
            Section {
                Button("Open Privacy & Security…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension")!)
                }
                Text("Turning a command off doesn't take back a permission you already granted; do that in Privacy & Security.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
