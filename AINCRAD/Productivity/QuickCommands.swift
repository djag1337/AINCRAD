import AppKit
import Contacts

/// Typed launcher commands ("remind …", "message …", "volume 40"). Every command can be switched
/// off, and every command that needs a macOS permission is OFF until you turn it on. Permissions
/// are only ever asked for when you press Return on a command, never while typing. Nothing is
/// sent on your behalf: messages and emails open as drafts for you to send.
enum QuickCommands {
    struct Command {
        let id: String
        let prefixes: [String]
        let title: String
        let example: String
        let does: String
        /// The macOS permission it needs, in plain words; nil = none.
        let permission: String?
        /// Off by default if it needs a permission you haven't already granted for something else.
        let defaultOn: Bool
    }

    static let all: [Command] = [
        Command(id: "remind", prefixes: ["remind", "reminder"], title: "Reminders", example: "remind call mom tomorrow 5pm",
                does: "Adds a reminder, with an alert at the time you give.", permission: "Reminders", defaultOn: true),
        Command(id: "event", prefixes: ["event", "meeting"], title: "Calendar events", example: "event lunch with Sam friday 1pm",
                does: "Adds a calendar event (an hour long, or all day if you give no time).", permission: "Calendar", defaultOn: true),
        Command(id: "note", prefixes: ["note"], title: "AINCRAD notes", example: "note pick up the 3D prints",
                does: "Saves a Markdown note to ~/AINCRAD Notes.", permission: nil, defaultOn: true),
        Command(id: "applenote", prefixes: ["applenote", "anote"], title: "Apple Notes", example: "applenote gift ideas: lego, books",
                does: "Creates a note in Apple Notes.", permission: "Automation → Notes", defaultOn: false),
        Command(id: "message", prefixes: ["message", "msg", "text"], title: "Messages (draft)", example: "message mom on my way",
                does: "Opens Messages with the text ready. It is NOT sent — you press Send.", permission: "Contacts (to find the person)", defaultOn: false),
        Command(id: "mail", prefixes: ["mail", "email"], title: "Mail (draft)", example: "mail sam about the build",
                does: "Opens a new email draft. It is NOT sent — you press Send.", permission: "Contacts (to find the person)", defaultOn: false),
        Command(id: "facetime", prefixes: ["facetime", "call"], title: "FaceTime", example: "facetime sam",
                does: "Starts a FaceTime call; macOS asks you to confirm before it rings.", permission: "Contacts (to find the person)", defaultOn: false),
        Command(id: "contact", prefixes: ["contact"], title: "Contacts", example: "contact sam",
                does: "Opens that person's card in the Contacts app.", permission: "Contacts", defaultOn: false),
        Command(id: "music", prefixes: ["play", "pause", "next", "previous"], title: "Music & Spotify", example: "next",
                does: "Play/pause, next and previous for whichever player is running.", permission: "Automation → Music / Spotify", defaultOn: false),
        Command(id: "volume", prefixes: ["volume", "mute", "unmute"], title: "Volume", example: "volume 40",
                does: "Sets the volume, or mutes and unmutes.", permission: nil, defaultOn: true),
        Command(id: "appearance", prefixes: ["dark", "light"], title: "Dark / light", example: "dark",
                does: "Switches the Mac's appearance.", permission: "Automation → System Events", defaultOn: false),
        Command(id: "define", prefixes: ["define"], title: "Dictionary", example: "define ephemeral",
                does: "Looks the word up in the Dictionary app.", permission: nil, defaultOn: true),
    ]

    static func isOn(_ c: Command, _ settings: AppSettings) -> Bool { settings.quickCommands[c.id] ?? c.defaultOn }

    /// The command and the text after its prefix, if `query` starts with one.
    static func match(_ query: String) -> (Command, String, String)? {
        let q = query.trimmingCharacters(in: .whitespaces)
        let lower = q.lowercased()
        for c in all {
            for p in c.prefixes where lower == p || lower.hasPrefix(p + " ") {
                return (c, p, String(q.dropFirst(p.count)).trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }

    private static func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s }

    /// Rows for the launcher's search.
    static func results(_ query: String, settings: AppSettings) -> [MenuItem] {
        let lower = query.trimmingCharacters(in: .whitespaces).lowercased()
        if lower == "commands" || lower == "help" || lower == "?" { return help(settings) }
        guard let (c, prefix, rest) = match(query) else { return [] }
        let perm = c.permission.map { " · needs \($0)" } ?? ""
        guard isOn(c, settings) else {
            // Short enough to read in a launcher row; the permission and where to turn it on are in the info panel.
            return [MenuItem(id: "qc-off:" + c.id, name: "\(prefix) is off", icon: "sf:lock.fill", action: .builtin("settings:quickcommands"),
                             description: "Off\(perm). \(c.does) Choose this to turn it on in Settings › Quick Commands.")]
        }
        func row(_ name: String, _ icon: String, _ builtin: String, _ about: String) -> [MenuItem] {
            [MenuItem(id: "qc:" + c.id, name: name, icon: icon, action: .builtin(builtin), description: about + (c.permission.map { " Uses \($0)." } ?? ""))]
        }
        switch c.id {
        case "remind", "event":
            return QuestActions.commandResults(query)
        case "note":
            guard !rest.isEmpty else { return [] }
            return row("Note: \(rest)", "sf:note.text", "qc:note:" + enc(rest), "Saves to ~/AINCRAD Notes.")
        case "applenote":
            guard !rest.isEmpty else { return [] }
            return row("Apple Note: \(rest)", "sf:note.text.badge.plus", "qc:applenote:" + enc(rest), "Creates a note in Apple Notes.")
        case "message", "mail", "facetime":
            guard !rest.isEmpty else { return [] }
            let words = rest.split(separator: " ", maxSplits: 1).map(String.init)
            let who = words[0], body = words.count > 1 ? words[1] : ""
            let verb = c.id == "message" ? "Message" : c.id == "mail" ? "Email" : "FaceTime"
            let icon = c.id == "message" ? "sf:message.fill" : c.id == "mail" ? "sf:envelope.fill" : "sf:video.fill"
            let shown = body.isEmpty ? "\(verb) \(who)" : "\(verb) \(who): \(body)"
            let note = c.id == "facetime" ? "macOS asks before calling." : "Opens a draft; you press Send."
            return row(shown, icon, "qc:\(c.id):\(enc(who)):\(enc(body))", note)
        case "contact":
            guard !rest.isEmpty else { return [] }
            return row("Open contact: \(rest)", "sf:person.crop.circle.fill", "qc:contact:" + enc(rest), "Opens their card in Contacts.")
        case "music":
            let verb = prefix == "play" || prefix == "pause" ? "playpause" : prefix
            return row(prefix.capitalized, prefix == "next" ? "sf:forward.fill" : prefix == "previous" ? "sf:backward.fill" : "sf:playpause.fill",
                       "qc:music:" + verb, "For Music or Spotify, whichever is running.")
        case "volume":
            if prefix == "mute" { return row("Mute", "sf:speaker.slash.fill", "system:mute:1", "") }
            if prefix == "unmute" { return row("Unmute", "sf:speaker.wave.2.fill", "system:mute:0", "") }
            guard let v = Int(rest), (0...100).contains(v) else { return row("Volume: type 0–100", "sf:speaker.wave.2.fill", "none", "") }
            return row("Set volume to \(v)%", "sf:speaker.wave.2.fill", "system:volume:\(v)", "")
        case "appearance":
            return row(prefix == "dark" ? "Switch to Dark" : "Switch to Light", prefix == "dark" ? "sf:moon.fill" : "sf:sun.max.fill",
                       "system:dark:\(prefix == "dark" ? 1 : 0)", "")
        case "define":
            guard !rest.isEmpty else { return [] }
            return row("Define “\(rest)”", "sf:character.book.closed.fill", "qc:define:" + enc(rest), "Opens the Dictionary app.")
        default: return []
        }
    }

    private static func help(_ settings: AppSettings) -> [MenuItem] {
        all.map { c in
            let on = isOn(c, settings)
            return MenuItem(id: "qc-help:" + c.id, name: "\(c.prefixes[0]): \(on ? "on" : "off")", icon: on ? "sf:checkmark.circle.fill" : "sf:circle",
                            action: .builtin("settings:quickcommands"),
                            description: "\(c.example). \(c.does) Permission: \(c.permission ?? "none").")
        }
    }

    // MARK: Running (main thread, after you pressed Return)

    static func perform(_ builtin: String, notify: @escaping (String) -> Void) {
        let parts = builtin.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2 else { return }
        func dec(_ i: Int) -> String { parts.count > i ? (parts[i].removingPercentEncoding ?? parts[i]) : "" }
        switch parts[1] {
        case "note":
            let text = dec(2)
            let folder = NotesPad.folder
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("Note \(Int(Date().timeIntervalSince1970)).md")
            if (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil { notify("Note saved: \(text)") }
        case "applenote":
            let text = dec(2).replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            script("tell application \"Notes\" to make new note with properties {body:\"\(text)\"}") { ok in notify(ok ? "Added to Apple Notes." : "Couldn't reach Notes (check Automation in Privacy & Security).") }
        case "message", "mail", "facetime":
            let kind = parts[1], who = dec(2), body = dec(3)
            resolve(who, wantEmail: kind == "mail") { address in
                guard let address else { notify("No contact found for “\(who)”."); return }
                let q = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body
                let url: String
                switch kind {
                case "message": url = "sms:\(address)" + (body.isEmpty ? "" : "&body=\(q)")
                case "mail": url = "mailto:\(address)" + (body.isEmpty ? "" : "?subject=\(q)")
                default: url = "facetime:\(address)"
                }
                if let u = URL(string: url) { NSWorkspace.shared.open(u) }
            }
        case "contact":
            let who = dec(2)
            card(who) { id in
                guard let id, let u = URL(string: "addressbook://" + id) else { notify("No contact found for “\(who)”."); return }
                NSWorkspace.shared.open(u)
            }
        case "music": MediaControl.players.filter(MediaControl.isRunning).first.map { MediaControl.command(dec(2), app: $0.app) }
        case "define":
            if let u = URL(string: "dict://" + (dec(2).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")) { NSWorkspace.shared.open(u) }
        default: break
        }
    }

    /// A phone number or email typed directly is used as-is; otherwise the first matching contact.
    static func resolve(_ who: String, wantEmail: Bool, done: @escaping (String?) -> Void) {
        if who.contains("@") || who.filter(\.isNumber).count >= 6 { return done(who) }
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { granted, _ in
            guard granted else { return DispatchQueue.main.async { done(nil) } }
            let keys = [CNContactPhoneNumbersKey, CNContactEmailAddressesKey, CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey] as [CNKeyDescriptor]
            let contacts = (try? store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: who), keysToFetch: keys)) ?? []
            let c = contacts.first
            let phone = c?.phoneNumbers.first?.value.stringValue
            let email = c?.emailAddresses.first.map { $0.value as String }
            DispatchQueue.main.async { done(wantEmail ? (email ?? phone) : (phone ?? email)) }
        }
    }

    /// The first matching contact's identifier (asks for Contacts access the first time).
    static func card(_ who: String, done: @escaping (String?) -> Void) {
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { granted, _ in
            let c = granted ? (try? store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: who),
                                                          keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor]))?.first : nil
            DispatchQueue.main.async { done(c?.identifier) }
        }
    }

    private static func script(_ source: String, done: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            DispatchQueue.main.async { done(error == nil) }
        }
    }
}
