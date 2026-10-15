import AppKit
import EventKit

/// Creates and updates reminders and calendar events from plain words ("call mom tomorrow 5pm"),
/// and completes or snoozes them from the quest log. Uses the Calendar and Reminders access the
/// quest log already asked for.
enum QuestActions {
    /// Shows an SAO message (set by the app delegate).
    static var notify: (_ text: String, _ title: String) -> Void = { _, _ in }
    /// The column of choices that opens when you click a quest.
    static let menu = AppMenuPanel()

    // MARK: Understanding the text

    struct Parsed: Equatable {
        var title: String
        var date: Date?
        /// The words named a time of day ("5pm", "noon"), not just a day.
        var hasTime: Bool
        var duration: TimeInterval?
    }

    private static let timeWords = try! NSRegularExpression(
        pattern: #"\d{1,2}(:\d{2})?\s*(am|pm|a\.m\.|p\.m\.)|\b\d{1,2}:\d{2}\b|\bnoon\b|\bmidnight\b|\bmorning\b|\bafternoon\b|\bevening\b|\btonight\b"#,
        options: [.caseInsensitive])

    static func parse(_ text: String, now: Date = Date()) -> Parsed {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let ns = trimmed as NSString
        guard let match = detector?.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: ns.length)),
              let date = match.date else {
            return Parsed(title: trimmed, date: nil, hasTime: false, duration: nil)
        }
        let said = ns.substring(with: match.range)
        let hasTime = timeWords.firstMatch(in: said, range: NSRange(location: 0, length: (said as NSString).length)) != nil
        // The title is what's left, without dangling connectors ("call mom at" → "call mom").
        var title = ns.replacingCharacters(in: match.range, with: " ")
        title = title.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        for word in [" at", " on", " by", " for", " from", " in"] where title.lowercased().hasSuffix(word) {
            title = String(title.dropLast(word.count))
        }
        if title.isEmpty {
            // The detector reads some words as times of day ("lunch friday 1pm" is all date to it).
            // Peel words off the front while the rest still means the same moment; those are the title.
            let words = trimmed.split(separator: " ").map(String.init)
            for k in 1..<max(words.count, 1) {
                let rest = words[k...].joined(separator: " ")
                let r = rest as NSString
                if let m = detector?.firstMatch(in: rest, options: [], range: NSRange(location: 0, length: r.length)), m.date == date {
                    title = words[..<k].joined(separator: " ")
                } else { break }
            }
            if title.isEmpty { title = trimmed }
        }
        return Parsed(title: title.trimmingCharacters(in: .whitespaces), date: date, hasTime: hasTime,
                      duration: match.duration > 0 ? match.duration : nil)
    }

    /// "Tomorrow 5:00 PM", "Fri 17 Oct", "Today".
    static func describe(_ p: Parsed) -> String {
        guard let date = p.date else { return "no date" }
        let cal = Calendar.current
        let day: String
        if cal.isDateInToday(date) { day = "Today" }
        else if cal.isDateInTomorrow(date) { day = "Tomorrow" }
        else { day = date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) }
        return p.hasTime ? "\(day) \(date.formatted(date: .omitted, time: .shortened))" : day
    }

    // MARK: Creating

    private static var store: EKEventStore { QuestStore.shared.store }

    @discardableResult
    static func addReminder(_ text: String) -> Bool {
        guard QuestStore.remindersAllowed else { notify("AINCRAD needs Reminders access (Settings › Widgets › Quest log).", "Quest"); return false }
        let p = parse(text)
        let reminder = EKReminder(eventStore: store)
        reminder.title = p.title
        reminder.calendar = store.defaultCalendarForNewReminders()
        if let date = p.date {
            let parts: Set<Calendar.Component> = p.hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
            reminder.dueDateComponents = Calendar.current.dateComponents(parts, from: date)
            if p.hasTime { reminder.addAlarm(EKAlarm(absoluteDate: date)) }
        }
        do {
            try store.save(reminder, commit: true)
            done("Reminder added: \(p.title)" + (p.date != nil ? " · \(describe(p))" : ""), exp: 5)
            return true
        } catch {
            notify("Couldn't add the reminder: \(error.localizedDescription)", "Quest")
            return false
        }
    }

    @discardableResult
    static func addEvent(_ text: String) -> Bool {
        guard QuestStore.eventsAllowed else { notify("AINCRAD needs Calendar access (Settings › Widgets › Quest log).", "Quest"); return false }
        let p = parse(text)
        let event = EKEvent(eventStore: store)
        event.title = p.title
        event.calendar = store.defaultCalendarForNewEvents
        if let date = p.date, !p.hasTime {
            event.isAllDay = true
            event.startDate = Calendar.current.startOfDay(for: date)
            event.endDate = event.startDate
        } else {
            // No time given: the next full hour.
            let start = p.date ?? Calendar.current.nextDate(after: Date(), matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? Date()
            event.startDate = start
            event.endDate = start.addingTimeInterval(p.duration ?? 3600)
        }
        do {
            try store.save(event, span: .thisEvent, commit: true)
            let when = describe(Parsed(title: p.title, date: event.startDate, hasTime: !event.isAllDay, duration: nil))
            done("Event added: \(p.title) · \(when)", exp: 5)
            return true
        } catch {
            notify("Couldn't add the event: \(error.localizedDescription)", "Quest")
            return false
        }
    }

    // MARK: Quest log actions

    static func complete(_ id: String) {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        reminder.isCompleted = true
        if (try? store.save(reminder, commit: true)) != nil { done("Quest complete: \(reminder.title ?? "Reminder")", exp: 15) }
    }

    /// Moves a reminder's due time to `date` (and its alarm with it).
    static func snooze(_ id: String, until date: Date) {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        reminder.alarms?.forEach { reminder.removeAlarm($0) }
        reminder.addAlarm(EKAlarm(absoluteDate: date))
        if (try? store.save(reminder, commit: true)) != nil {
            notify("Snoozed until \(describe(Parsed(title: "", date: date, hasTime: true, duration: nil)))", "Quest")
            QuestStore.shared.refresh()
        }
    }

    private static func done(_ text: String, exp: Int) {
        notify(text, "Quest")
        BattleLog.shared.add(text, symbol: "flag.checkered")
        ExpStore.shared.gain(exp)
        QuestStore.shared.refresh()
    }

    /// The choices for one quest, shown when you click it.
    static func nodes(for quest: QuestStore.Quest) -> [AXMenus.Node] {
        let open = AXMenus.Node.action(quest.kind == .reminder ? "Open in Reminders" : "Open in Calendar", icon: "sf:arrow.up.forward.app") {
            NSWorkspace.shared.open(URL(fileURLWithPath: quest.kind == .reminder ? "/System/Applications/Reminders.app" : "/System/Applications/Calendar.app"))
        }
        guard quest.kind == .reminder else { return [open] }
        let tomorrow = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0,
                                             of: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()) ?? Date()
        return [
            .action("Complete", icon: "sf:checkmark.circle.fill") { complete(quest.id) },
            .action("Snooze 1 Hour", icon: "sf:clock.arrow.circlepath") { snooze(quest.id, until: Date().addingTimeInterval(3600)) },
            .action("Snooze Until Tomorrow 9 AM", icon: "sf:sunrise.fill") { snooze(quest.id, until: tomorrow) },
            .separatorLine,
            open,
        ]
    }

    // MARK: Launcher

    /// Typed in the launcher's search: "remind …" and "event …".
    static func commandResults(_ raw: String) -> [MenuItem] {
        let q = raw.trimmingCharacters(in: .whitespaces)
        for (prefix, kind) in [("remind ", "remind"), ("reminder ", "remind"), ("event ", "event"), ("meeting ", "event")]
            where q.lowercased().hasPrefix(prefix) {
            let text = String(q.dropFirst(prefix.count))
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
            let p = parse(text)
            let encoded = text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? text
            return [MenuItem(id: "command:\(kind)", name: (kind == "remind" ? "Remind: " : "Event: ") + p.title,
                             icon: kind == "remind" ? "sf:checklist" : "sf:calendar.badge.plus",
                             action: .builtin("quests:\(kind):\(encoded)"),
                             description: describe(p) + (kind == "event" && p.date == nil ? " (next full hour)" : ""))]
        }
        return []
    }

    /// Command Center › Quests: new reminder/event, then today's quests with their actions.
    static func menuItems() -> [MenuItem] {
        var out = [
            MenuItem(id: "quests:new-reminder", name: "New Reminder…", icon: "sf:checklist", action: .builtin("quests:new-reminder"),
                     description: "Type it naturally: “call mom tomorrow 5pm”."),
            MenuItem(id: "quests:new-event", name: "New Event…", icon: "sf:calendar.badge.plus", action: .builtin("quests:new-event"),
                     description: "Type it naturally: “lunch with Sam friday 1pm”."),
        ]
        for quest in QuestStore.shared.quests.prefix(12) {
            var kids: [MenuItem] = []
            if quest.kind == .reminder {
                kids = [MenuItem(id: "q-done:" + quest.id, name: "Complete", icon: "sf:checkmark.circle.fill", action: .builtin("quests:complete:" + quest.id)),
                        MenuItem(id: "q-1h:" + quest.id, name: "Snooze 1 Hour", icon: "sf:clock.arrow.circlepath", action: .builtin("quests:snooze1h:" + quest.id)),
                        MenuItem(id: "q-tm:" + quest.id, name: "Snooze Until Tomorrow 9 AM", icon: "sf:sunrise.fill", action: .builtin("quests:snoozeTomorrow:" + quest.id))]
            }
            kids.append(MenuItem(id: "q-open:" + quest.id, name: quest.kind == .reminder ? "Open in Reminders" : "Open in Calendar",
                                 icon: "sf:arrow.up.forward.app", action: .builtin("quests:open:" + (quest.kind == .reminder ? "reminders" : "calendar"))))
            let detail = quest.overdue ? "overdue" : quest.start.map { QuestContent.countdown(to: $0, now: Date()) } ?? "today"
            out.append(MenuItem(id: "quest:" + quest.id, name: quest.title, icon: quest.kind == .reminder ? "sf:circle" : "sf:diamond.fill",
                                children: kids, description: detail))
        }
        return out
    }

    /// Runs "quests:…" builtins.
    static func perform(_ builtin: String, prompt: (String, String, String, @escaping (String) -> Void) -> Void) {
        let parts = builtin.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return }
        let arg = parts.count > 2 ? (parts[2].removingPercentEncoding ?? parts[2]) : ""
        switch parts[1] {
        case "remind": addReminder(arg)
        case "event": addEvent(arg)
        case "new-reminder": prompt("New Reminder", "call mom tomorrow 5pm", "remind") { addReminder($0) }
        case "new-event": prompt("New Event", "lunch with Sam friday 1pm", "event") { addEvent($0) }
        case "complete": complete(arg)
        case "snooze1h": snooze(arg, until: Date().addingTimeInterval(3600))
        case "snoozeTomorrow":
            let t = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            snooze(arg, until: Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: t) ?? t)
        case "open":
            NSWorkspace.shared.open(URL(fileURLWithPath: arg == "reminders" ? "/System/Applications/Reminders.app" : "/System/Applications/Calendar.app"))
        default: Log.error("quests: unknown command \(parts[1])")
        }
    }
}
