import AppKit

/// Launcher search: instant results (math, apps, menu items, System Settings panes, web) plus
/// files from the Spotlight index, which arrive a moment later.
final class SearchEngine {
    private var query: NSMetadataQuery?
    private var observer: NSObjectProtocol?
    private var debounce: DispatchWorkItem?

    /// Ranks how well `name` matches `q`: 0 = no match; higher is better.
    static func score(_ name: String, _ q: String) -> Int {
        let n = name.lowercased(), q = q.lowercased()
        guard !q.isEmpty else { return 0 }
        if n == q { return 100 }
        if n.hasPrefix(q) { return 80 }
        // "wifi" should find "Wi-Fi": compare without spaces and punctuation too.
        let squashed = String(n.filter { $0.isLetter || $0.isNumber })
        if squashed == q { return 90 }
        if squashed.hasPrefix(q) { return 70 }
        if n.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "." }).contains(where: { $0.hasPrefix(q) }) { return 60 }
        if n.contains(q) { return 40 }
        // Initials / subsequence, e.g. "vsc" → "Visual Studio Code".
        var it = n.makeIterator()
        for ch in q {
            var found = false
            while let c = it.next() { if c == ch { found = true; break } }
            if !found { return 0 }
        }
        return 20
    }

    static let settingsPanes: [(String, String, String)] = [
        ("Wi-Fi", "wifi", "com.apple.wifi-settings-extension"),
        ("Bluetooth", "dot.radiowaves.left.and.right", "com.apple.BluetoothSettings"),
        ("Displays", "display", "com.apple.Displays-Settings.extension"),
        ("Sound", "speaker.wave.2.fill", "com.apple.Sound-Settings.extension"),
        ("Battery & Energy", "battery.75percent", "com.apple.Battery-Settings.extension"),
        ("Wallpaper", "photo.fill", "com.apple.Wallpaper-Settings.extension"),
        ("Keyboard", "keyboard.fill", "com.apple.Keyboard-Settings.extension"),
        ("Mouse", "computermouse.fill", "com.apple.Mouse-Settings.extension"),
        ("Trackpad", "rectangle.and.hand.point.up.left.fill", "com.apple.Trackpad-Settings.extension"),
        ("Privacy & Security", "hand.raised.fill", "com.apple.settings.PrivacySecurity.extension"),
        ("Network", "network", "com.apple.Network-Settings.extension"),
        ("Notifications", "bell.badge.fill", "com.apple.Notifications-Settings.extension"),
        ("Accessibility", "accessibility", "com.apple.Accessibility-Settings.extension"),
        ("Software Update", "arrow.triangle.2.circlepath", "com.apple.Software-Update-Settings.extension"),
        ("Login Items", "person.crop.circle.badge.checkmark", "com.apple.LoginItems-Settings.extension"),
    ]

    /// Results that need no I/O. `apps` and `menu` are what the launcher already has in memory.
    static func instant(_ q: String, apps: [MenuItem], menu: [MenuItem]) -> [MenuItem] {
        let q = q.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        var out: [MenuItem] = []
        if let v = Calculator.evaluate(q) {
            let text = Calculator.format(v)
            out.append(MenuItem(id: "search:calc", name: "= \(text)", icon: "sf:equal.circle.fill",
                                action: .builtin("copy:" + text), description: "\(q) = \(text)\nReturn copies the answer"))
        }
        let rankedApps = apps.map { ($0, score($0.name, q)) }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(8).map(\.0)
        out += rankedApps
        let appPaths = Set(apps.compactMap { if case .app(let p) = $0.action { return p } else { return nil } })
        var seenMenu = Set<String>()
        let rankedMenu = flatten(menu).filter { item in
            guard item.action != nil || item.hasSubmenu else { return false }
            if case .app(let p) = item.action, appPaths.contains(p) { return false }
            return seenMenu.insert(item.name).inserted
        }.map { ($0, score($0.name, q)) }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(5).map(\.0)
        out += rankedMenu
        out += settingsPanes.map { ($0, score($0.0, q)) }.filter { $0.1 >= 60 }.prefix(3).map { pane, _ in
            MenuItem(id: "search:settings:" + pane.0, name: pane.0, icon: "sf:" + pane.1,
                     action: .url("x-apple.systempreferences:" + pane.2), description: "System Settings")
        }
        let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        out.append(MenuItem(id: "search:web", name: "Search the web for “\(q)”", icon: "sf:magnifyingglass",
                            action: .url("https://www.google.com/search?q=" + encoded)))
        return out
    }

    static func flatten(_ items: [MenuItem]) -> [MenuItem] {
        items.flatMap { [$0] + flatten($0.children ?? []) }
    }

    /// Files and folders from Spotlight, name matches in your home folder, most recently used first.
    func files(_ q: String, completion: @escaping ([MenuItem]) -> Void) {
        cancel()
        let q = q.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2, Calculator.evaluate(q) == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.startQuery(q, completion: completion) }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    func cancel() {
        debounce?.cancel()
        query?.stop()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        query = nil
    }

    private func startQuery(_ q: String, completion: @escaping ([MenuItem]) -> Void) {
        let mq = NSMetadataQuery()
        mq.predicate = NSPredicate(format: "%K LIKE[cd] %@", NSMetadataItemFSNameKey, "*\(q)*")
        mq.searchScopes = [NSMetadataQueryUserHomeScope]
        mq.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemLastUsedDateKey, ascending: false)]
        observer = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: mq, queue: .main) { [weak self] _ in
            mq.disableUpdates()
            var items: [MenuItem] = []
            for i in 0..<min(mq.resultCount, 40) {
                guard let r = mq.result(at: i) as? NSMetadataItem, let path = r.value(forAttribute: NSMetadataItemPathKey) as? String,
                      !path.contains("/Library/"), !path.hasSuffix(".app") else { continue }
                items.append(MenuItem(id: "search:file:" + path, name: (path as NSString).lastPathComponent, action: .open(path)))
                if items.count == 6 { break }
            }
            self?.cancel()
            completion(items)
        }
        query = mq
        mq.start()
    }
}

/// A tiny arithmetic evaluator (+ − × ÷ ^ %, parentheses, decimals). Hand-written because
/// NSExpression raises uncatchable exceptions on malformed input.
enum Calculator {
    static func evaluate(_ text: String) -> Double? {
        let s = text.replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: ",", with: "").replacingOccurrences(of: " ", with: "")
        guard !s.isEmpty, s.rangeOfCharacter(from: CharacterSet(charactersIn: "+-*/^%")) != nil,
              s.allSatisfy({ "0123456789.+-*/^%()".contains($0) }) else { return nil }
        var p = Parser(chars: Array(s))
        guard let v = p.expression(), p.i == p.chars.count, v.isFinite else { return nil }
        return v
    }

    static func format(_ v: Double) -> String {
        if v == v.rounded(), abs(v) < 1e15 { return String(Int64(v)) }
        let f = NumberFormatter()
        f.maximumFractionDigits = 8
        f.minimumFractionDigits = 0
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    private struct Parser {
        let chars: [Character]
        var i = 0

        mutating func expression() -> Double? {
            guard var v = term() else { return nil }
            while i < chars.count, chars[i] == "+" || chars[i] == "-" {
                let op = chars[i]; i += 1
                guard let r = term() else { return nil }
                v = op == "+" ? v + r : v - r
            }
            return v
        }

        mutating func term() -> Double? {
            guard var v = power() else { return nil }
            while i < chars.count, "*/%".contains(chars[i]) {
                let op = chars[i]; i += 1
                guard let r = power() else { return nil }
                switch op {
                case "*": v *= r
                case "/": guard r != 0 else { return nil }; v /= r
                default: guard r != 0 else { return nil }; v = v.truncatingRemainder(dividingBy: r)
                }
            }
            return v
        }

        mutating func power() -> Double? {
            guard let base = unary() else { return nil }
            if i < chars.count, chars[i] == "^" {
                i += 1
                guard let e = power() else { return nil }
                return pow(base, e)
            }
            return base
        }

        mutating func unary() -> Double? {
            if i < chars.count, chars[i] == "-" { i += 1; return unary().map { -$0 } }
            if i < chars.count, chars[i] == "+" { i += 1; return unary() }
            return primary()
        }

        mutating func primary() -> Double? {
            if i < chars.count, chars[i] == "(" {
                i += 1
                guard let v = expression(), i < chars.count, chars[i] == ")" else { return nil }
                i += 1
                return v
            }
            let start = i
            while i < chars.count, chars[i].isNumber || chars[i] == "." { i += 1 }
            return start < i ? Double(String(chars[start..<i])) : nil
        }
    }
}
