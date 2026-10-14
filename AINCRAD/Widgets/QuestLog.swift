import AppKit
import EventKit

/// Today's calendar events and due reminders, as quests. Reads EventKit off the main thread and
/// tells its listeners when anything changes.
final class QuestStore {
    static let shared = QuestStore()

    struct Quest: Equatable {
        enum Kind { case event, reminder }
        var title: String
        var kind: Kind
        var start: Date?
        var end: Date?
        var allDay = false
        var overdue = false
    }

    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    private var listeners: [UUID: () -> Void] = [:]
    private(set) var quests: [Quest] = []

    static var eventsAllowed: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    static var remindersAllowed: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }
    static var undecided: Bool {
        EKEventStore.authorizationStatus(for: .event) == .notDetermined || EKEventStore.authorizationStatus(for: .reminder) == .notDetermined
    }

    /// Asks for Calendar and Reminders access (macOS shows its prompt once for each).
    func requestAccess(_ done: @escaping () -> Void = {}) {
        store.requestFullAccessToEvents { _, _ in
            self.store.requestFullAccessToReminders { _, _ in
                DispatchQueue.main.async {
                    Log.info("quests: calendar=\(QuestStore.eventsAllowed) reminders=\(QuestStore.remindersAllowed)")
                    self.refresh()
                    done()
                }
            }
        }
    }

    func listen(_ change: @escaping () -> Void) -> UUID {
        let id = UUID()
        listeners[id] = change
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
                self?.refresh()
            }
        }
        refresh()
        return id
    }

    func unlisten(_ id: UUID) {
        listeners[id] = nil
        if listeners.isEmpty, let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }

    func refresh() {
        let now = Date()
        let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now.addingTimeInterval(86_400)
        var events: [Quest] = []
        if QuestStore.eventsAllowed {
            // From an hour ago, so a quest in progress stays listed.
            let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-3600), end: endOfDay, calendars: nil)
            events = store.events(matching: predicate)
                .filter { $0.endDate > now && $0.status != .canceled }
                .map { Quest(title: $0.title ?? "Event", kind: .event, start: $0.startDate, end: $0.endDate, allDay: $0.isAllDay) }
        }
        guard QuestStore.remindersAllowed else { return publish(events) }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: endOfDay, calendars: nil)
        store.fetchReminders(matching: predicate) { reminders in
            let start = Calendar.current.startOfDay(for: now)
            let due = (reminders ?? []).map { r -> Quest in
                let date = r.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
                return Quest(title: r.title ?? "Reminder", kind: .reminder, start: date, overdue: (date ?? now) < start)
            }
            DispatchQueue.main.async { self.publish(events + due) }
        }
    }

    /// Overdue first, then by time; all-day and undated last.
    static func ordered(_ list: [Quest]) -> [Quest] {
        list.sorted { a, b in
            if a.overdue != b.overdue { return a.overdue }
            let ka = a.allDay ? .distantFuture : (a.start ?? .distantFuture), kb = b.allDay ? .distantFuture : (b.start ?? .distantFuture)
            return ka < kb
        }
    }

    private func publish(_ list: [Quest]) {
        let sorted = QuestStore.ordered(list)
        guard sorted != quests else { return }
        quests = sorted
        listeners.values.forEach { $0() }
    }
}

/// The SAO quest log widget: a header, the next timed event as the Floor Boss with a countdown
/// bar, then the rest of today's quests.
final class QuestContent: WidgetContent {
    private var listener: UUID?
    private var timer: Timer?
    private var dynamic: [CALayer] = []

    override func build() {
        let fs = config.style.fontSize
        let header = text("QUEST LOG", size: fs * 0.8, color: accent)
        header.font = ThemeFonts.display(theme, fs * 0.8)
        header.frame = CGRect(x: 14, y: 10, width: size.width - 28, height: lineHeight(fs * 0.8) + 2)
        let rule = CALayer()
        rule.frame = CGRect(x: 14, y: header.frame.maxY + 4, width: size.width - 28, height: 1)
        rule.backgroundColor = accent.withAlphaComponent(0.6).cgColor
        root.addSublayer(rule)
        render()
    }

    override func start() {
        listener = QuestStore.shared.listen { [weak self] in self?.render() }
        // Countdowns tick by the minute.
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.render() }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    override func stop() {
        if let listener { QuestStore.shared.unlisten(listener) }
        listener = nil
        timer?.invalidate()
        timer = nil
    }

    private func render() {
        Motion.instant {
            dynamic.forEach { $0.removeFromSuperlayer() }
            dynamic = []
            let fs = config.style.fontSize
            var y = 10 + lineHeight(fs * 0.8) + 14
            let showEvents = config.flag("events", true), showReminders = config.flag("reminders", true)
            guard (showEvents && QuestStore.eventsAllowed) || (showReminders && QuestStore.remindersAllowed) else {
                let t = text(QuestStore.undecided ? "Waiting for Calendar & Reminders access…"
                                                  : "Allow Calendar & Reminders: Settings › Widgets › Quest log", size: fs * 0.75)
                t.isWrapped = true
                t.truncationMode = .none
                t.frame = CGRect(x: 14, y: y, width: size.width - 28, height: size.height - y - 8)
                dynamic.append(t)
                return
            }
            let quests = QuestStore.shared.quests.filter { ($0.kind == .event && showEvents) || ($0.kind == .reminder && showReminders) }
            if quests.isEmpty {
                let t = text("No quests today. Free roam!", size: fs * 0.8, color: textColor.withAlphaComponent(0.7))
                t.frame = CGRect(x: 14, y: y, width: size.width - 28, height: lineHeight(fs * 0.8) + 2)
                dynamic.append(t)
                return
            }
            let now = Date()
            // The Floor Boss: the next timed event that hasn't started.
            let boss = quests.firstIndex { $0.kind == .event && !$0.allDay && ($0.start ?? now) > now }
            if let b = boss {
                y = drawBoss(quests[b], at: y, now: now)
            }
            let rowH = lineHeight(fs * 0.85) + 8
            for (i, q) in quests.enumerated() where i != boss {
                guard y + rowH <= size.height - 6 else { break }
                drawRow(q, at: y, height: rowH, now: now)
                y += rowH
            }
        }
    }

    private func drawBoss(_ q: QuestStore.Quest, at top: CGFloat, now: Date) -> CGFloat {
        let fs = config.style.fontSize
        let tag = text("FLOOR BOSS", size: fs * 0.6, color: HPBarContent.red)
        tag.font = ThemeFonts.display(theme, fs * 0.6)
        tag.frame = CGRect(x: 14, y: top, width: 120, height: lineHeight(fs * 0.6) + 2)
        let when = text(QuestContent.countdown(to: q.start ?? now, now: now), size: fs * 0.7, align: .right)
        when.frame = CGRect(x: size.width - 140, y: top, width: 126, height: lineHeight(fs * 0.7) + 2)
        let name = text(q.title, size: fs)
        name.frame = CGRect(x: 14, y: tag.frame.maxY + 2, width: size.width - 28, height: lineHeight(fs) + 2)
        // Slanted bar that fills as the start time approaches (over the last two hours).
        let barY = name.frame.maxY + 4, barW = size.width - 28, h: CGFloat = 8
        let minutes = (q.start ?? now).timeIntervalSince(now) / 60
        let fraction = CGFloat(min(max(1 - minutes / 120, 0.02), 1))
        let shape = CGMutablePath()
        shape.move(to: .zero)
        shape.addLine(to: CGPoint(x: barW, y: 0))
        shape.addLine(to: CGPoint(x: barW - 5, y: h))
        shape.addLine(to: CGPoint(x: 0, y: h))
        shape.closeSubpath()
        let track = CAShapeLayer()
        track.frame = CGRect(x: 14, y: barY, width: barW, height: h)
        track.path = shape
        track.fillColor = textColor.withAlphaComponent(0.12).cgColor
        track.strokeColor = textColor.withAlphaComponent(0.5).cgColor
        track.lineWidth = 1
        root.addSublayer(track)
        let holder = CALayer()
        holder.frame = track.frame
        let mask = CAShapeLayer()
        mask.path = shape
        holder.mask = mask
        let fill = CALayer()
        fill.frame = CGRect(x: 0, y: 0, width: barW * fraction, height: h)
        fill.backgroundColor = (minutes < 15 ? HPBarContent.red : minutes < 60 ? HPBarContent.yellow : accent).cgColor
        holder.addSublayer(fill)
        root.addSublayer(holder)
        dynamic += [tag, when, name, track, holder]
        return barY + h + 12
    }

    private func drawRow(_ q: QuestStore.Quest, at y: CGFloat, height: CGFloat, now: Date) {
        let fs = config.style.fontSize * 0.85
        let marker = CALayer()
        let m: CGFloat = 8
        marker.frame = CGRect(x: 16, y: y + (height - m) / 2, width: m, height: m)
        if q.kind == .event {
            marker.backgroundColor = accent.cgColor
            marker.transform = CATransform3DMakeRotation(.pi / 4, 0, 0, 1)
        } else {
            marker.borderColor = (q.overdue ? HPBarContent.red : accent).cgColor
            marker.borderWidth = 1.5
            marker.cornerRadius = 1.5
        }
        root.addSublayer(marker)
        let detail: String
        if q.overdue { detail = "overdue" }
        else if q.allDay { detail = "today" }
        else if let s = q.start, let e = q.end, s <= now { detail = "now · ends " + QuestContent.clock(e) }
        else if let s = q.start { detail = q.kind == .event ? QuestContent.countdown(to: s, now: now) : QuestContent.clock(s) }
        else { detail = "today" }
        let detailW: CGFloat = 110
        let title = text(q.title, size: fs)
        title.frame = CGRect(x: 32, y: y + (height - lineHeight(fs)) / 2, width: size.width - 46 - detailW, height: lineHeight(fs) + 2)
        let right = text(detail, size: fs * 0.82, color: q.overdue ? HPBarContent.red : textColor.withAlphaComponent(0.7), align: .right)
        right.frame = CGRect(x: size.width - 14 - detailW, y: y + (height - lineHeight(fs * 0.82)) / 2, width: detailW, height: lineHeight(fs * 0.82) + 2)
        dynamic += [marker, title, right]
    }

    static func countdown(to date: Date, now: Date) -> String {
        let minutes = Int((date.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 0 { return "now" }
        if minutes < 60 { return "in \(minutes)m" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "in \(h)h" : "in \(h)h \(m)m"
    }

    static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
