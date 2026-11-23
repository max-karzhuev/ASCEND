import Foundation

public struct Planning: Sendable {
    public let zone: String
    public var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: zone) ?? .gmt
        c.firstWeekday = 2; c.minimumDaysInFirstWeek = 4; return c
    }
    public init(zone: String) { self.zone = zone }
    public func day(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    public func date(_ day: String) -> Date {
        let p = day.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return Date(timeIntervalSince1970: 0) }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12)) ?? Date(timeIntervalSince1970: 0)
    }
    public static func validDay(_ day: String) -> Bool {
        guard day.count == 10, day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return false }
        let p = Planning(zone: "UTC"); return p.day(p.date(day)) == day && day >= "2000-01-01" && day <= "2200-12-31"
    }
    public func adding(_ count: Int, to day: String) -> String { self.day(calendar.date(byAdding: .day, value: count, to: date(day))!) }
    public func week(_ day: String) -> String { self.day(calendar.dateInterval(of: .weekOfYear, for: date(day))!.start) }
    public func nextMidnight(after date: Date) -> Date { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))! }
    public func days(from first: String, through last: String) -> [String] {
        guard Self.validDay(first), Self.validDay(last), first <= last else { return [] }
        var result: [String] = [], cursor = first
        while cursor <= last && result.count < 75_000 { result.append(cursor); cursor = adding(1, to: cursor) }
        return result
    }
    public func monthDays(containing date: Date) -> [String] {
        let interval = calendar.dateInterval(of: .month, for: date)!
        let offset = (calendar.component(.weekday, from: interval.start) + 5) % 7
        let first = calendar.date(byAdding: .day, value: -offset, to: interval.start)!
        let count = calendar.range(of: .day, in: .month, for: date)!.count
        let total = ((offset + count + 6) / 7) * 7
        return (0..<total).map { day(calendar.date(byAdding: .day, value: $0, to: first)!) }
    }
    public func occurrence(_ quest: Quest, on day: String) -> Occurrence {
        let inRange = day >= quest.startDay && !quest.archived
        let weekday = calendar.component(.weekday, from: date(day))
        let planned = inRange && (quest.schedule == .daily || (quest.schedule == .weekdays && quest.weekdays.contains(weekday)))
        let available = planned || (inRange && quest.schedule == .once && day == quest.startDay)
        return Occurrence(quest: quest, day: day, timeZone: zone, planned: planned, available: available)
    }
}

public enum Recurrence {
    public static func revision(for templateID: String, day: String, ledger: Ledger) -> Quest? {
        let revisions = ledger.values(QuestRevision.self, kind: .revision).filter { $0.quest.id == templateID && $0.effectiveDay <= day }
        let ordered = revisions.sorted { a, b in
            if a.effectiveDay != b.effectiveDay { return a.effectiveDay < b.effectiveDay }
            return Change.ordered(ledger.operations(.revision, a.id).last!, ledger.operations(.revision, b.id).last!)
        }
        var fields: [String: String] = [:]
        for revision in ordered {
            let patch = revision.changedFields ?? ((try? Codec.fields(revision.quest)) ?? [:])
            fields.merge(patch, uniquingKeysWith: { _, new in new })
        }
        return try? Codec.decode(Quest.self, fields: fields)
    }
    /// Materialize only elapsed/current days. Future plans are projections, never frozen early.
    public static func missingSnapshots(ledger: Ledger, now: Date) -> [Occurrence] {
        let p = Planning(zone: ledger.effectiveZone(at: now)); let today = p.day(now)
        let existing = Set(ledger.values(Occurrence.self, kind: .occurrence).map(\.id))
        let revisions = ledger.values(QuestRevision.self, kind: .revision)
        var result: [Occurrence] = []
        for id in Set(revisions.map { $0.quest.id }).sorted() {
            guard !ledger.isDeleted(.quest, id), let start = revisions.filter({ $0.quest.id == id }).map(\.effectiveDay).min() else { continue }
            for day in p.days(from: start, through: today) {
                guard let quest = revision(for: id, day: day, ledger: ledger), quest.schedule != .weekly else { continue }
                let historicalZone = ledger.effectiveZone(at: Planning(zone: ledger.profile.timeZone).date(day))
                let o = Planning(zone: historicalZone).occurrence(quest, on: day)
                if quest.schedule == .once && day != quest.startDay { continue }
                if !existing.contains(o.id) && !ledger.isDeleted(.occurrence, o.id) { result.append(o) }
            }
        }
        return result
    }
    public static func projected(on day: String, ledger: Ledger, zone: String) -> [Occurrence] {
        let p = Planning(zone: zone)
        return ledger.quests.compactMap { q in
            guard !ledger.isDeleted(.quest, q.id), let current = revision(for: q.id, day: day, ledger: ledger) else { return nil }
            let o = p.occurrence(current, on: day); return o.available && !ledger.isDeleted(.occurrence, o.id) ? o : nil
        }
    }
    /// A weekly session is an explicit user action, not an automatically generated daily occurrence.
    /// Its persisted identity is reused on retry, completion, undo and sync. Independent sessions
    /// logged offline on two devices have distinct identities and both survive reconciliation.
    public static func weeklySession(quest: Quest, day: String, zone: String, sessionID: String) -> Occurrence {
        let week = Planning(zone: zone).week(day)
        var occurrence = Occurrence(quest: quest, day: day, timeZone: zone, planned: false, available: true, weeklySlot: 1, week: week)
        occurrence.id = "\(quest.id)|week|\(week)|session|\(sessionID)"
        return occurrence
    }
    public static func loggedSessions(templateID: String, day: String, zone: String, ledger: Ledger) -> [Occurrence] {
        let prefix = "\(templateID)|week|\(Planning(zone: zone).week(day))|"
        return ledger.occurrences.filter { $0.id.hasPrefix(prefix) && $0.weeklySlot != nil }.sorted { $0.day == $1.day ? $0.id < $1.id : $0.day < $1.day }
    }
}

public struct DaySummary: Sendable {
    public var day: String
    public var planned: Int
    public var completed: Int
    public var extras: Int
    public var xp: Int
    public var brainSessions: Int
    public var isFuture: Bool
    public var ratio: Double? { planned > 0 ? Double(completed) / Double(planned) : nil }
    public var intensity: Double { isFuture ? 0 : min(1, max(0, ratio ?? 0)) }
    public var rest: Bool { planned == 0 && !isFuture }
}
public struct PlayerProgress: Sendable {
    public var level: Int
    public var intoLevel: Int
    public var required: Int
    public var lifetime: Int
    public var rank: String {
        switch level { case 1...9: "E"; case 10...19: "D"; case 20...34: "C"; case 35...49: "B"; case 50...74: "A"; default: "S" }
    }
}
public enum Progression {
    public static func required(level: Int) -> Int { 100 + 25 * (max(1, level) - 1) }
    public static func player(xp: Int) -> PlayerProgress {
        var level = 1, remainder = max(0, xp)
        while remainder >= required(level: level) { remainder -= required(level: level); level += 1 }
        return PlayerProgress(level: level, intoLevel: remainder, required: required(level: level), lifetime: max(0, xp))
    }
    public static func totalXP(_ ledger: Ledger) -> Int { ledger.completions.reduce(0) { $0 + $1.xp } + ledger.attempts.reduce(0) { $0 + LearningRules.xp($1) } }
    public static func categoryXP(_ category: String, ledger: Ledger) -> Int { ledger.completions.filter { $0.category == category }.reduce(0) { $0 + $1.xp } }
    public static func day(_ day: String, ledger: Ledger, today: String) -> DaySummary {
        let planned = ledger.occurrences.filter { $0.day == day && $0.planned }
        let active = ledger.completions
        let completed = planned.filter { o in active.contains { $0.occurrenceID == o.id } }.count
        let credits = active.filter { $0.day == day }
        let extras = credits.filter { c in !planned.contains { $0.id == c.occurrenceID } }.count
        let attempts = ledger.attempts.filter { $0.day == day && $0.submitted }
        return DaySummary(day: day, planned: planned.count, completed: completed, extras: extras,
                          xp: credits.reduce(0) { $0 + $1.xp } + attempts.reduce(0) { $0 + LearningRules.xp($1) },
                          brainSessions: Set(attempts.map(\.sessionID)).count, isFuture: day > today)
    }
    public static func streak(ledger: Ledger, now: Date) -> Int {
        let p = Planning(zone: ledger.effectiveZone(at: now)), today = p.day(now)
        let start = ledger.occurrences.map(\.day).min() ?? today
        var count = 0
        for day in p.days(from: start, through: today).reversed() {
            let s = self.day(day, ledger: ledger, today: today)
            if s.planned == 0 { continue }
            if s.completed == s.planned { count += 1 }
            else if day != today { break }
        }
        return count
    }
    public static func goalValue(_ goal: Goal, ledger: Ledger) -> Double {
        if goal.kind == .milestones {
            let checks = ledger.values(MilestoneCheck.self, kind: .milestone).filter { $0.goalID == goal.id && $0.done }
            return goal.milestones.filter { m in checks.contains { $0.id == m.id } }.reduce(0) { $0 + $1.weight }
        }
        let linked = ledger.completions.filter { $0.goalID == goal.id }.reduce(0) { $0 + $1.amount }
        let manual = ledger.values(Contribution.self, kind: .contribution).filter { $0.goalID == goal.id }.reduce(0) { $0 + $1.amount }
        return linked + manual
    }
    public static func goalTarget(_ goal: Goal) -> Double { goal.kind == .milestones ? goal.milestones.reduce(0) { $0 + $1.weight } : goal.target }
    public static func goalRatio(_ goal: Goal, ledger: Ledger) -> Double { min(1, max(0, goalValue(goal, ledger: ledger) / max(1, goalTarget(goal)))) }
}

public enum LearningRules {
    /// Activity credit is separate from assessment accuracy. Hints reduce assessed XP.
    public static func xp(_ attempt: Attempt) -> Int {
        guard attempt.submitted else { return 0 }
        if attempt.mode == .practice { return 5 }
        guard attempt.correct == true else { return 0 }
        return attempt.hintsUsed == 0 ? 10 : 5
    }
    public static func deterministic(_ question: Question, answer: String) -> Bool? {
        switch question.kind {
        case .multipleChoice: return answer.trimmingCharacters(in: .whitespacesAndNewlines) == question.answer
        case .numerical:
            guard let a = Double(answer.trimmingCharacters(in: .whitespacesAndNewlines)), a.isFinite,
                  let expected = Double(question.answer), expected.isFinite else { return false }
            return abs(a - expected) <= question.tolerance
        default: return nil
        }
    }
    public static func validate(_ questions: [Question], count: Int) throws {
        guard (1...10).contains(count), questions.count == count, Set(questions.map(\.id)).count == count else { throw DataError.invalid("The provider returned an invalid question count or duplicate question IDs") }
        for q in questions {
            guard !q.id.isEmpty, q.id.count <= 100, !q.prompt.isEmpty, q.prompt.count <= 8000,
                  !q.answer.isEmpty, q.answer.count <= 8000, !q.explanation.isEmpty, q.explanation.count <= 12000,
                  (1...3).contains(q.hints.count), q.hints.allSatisfy({ !$0.isEmpty && $0.count <= 2000 }),
                  q.tolerance.isFinite, q.tolerance >= 0, q.topic.count <= 200 else { throw DataError.invalid("The provider returned an incomplete question") }
            if q.kind == .multipleChoice {
                guard (2...6).contains(q.options.count), Set(q.options).count == q.options.count, q.options.contains(q.answer) else { throw DataError.invalid("Invalid multiple-choice answer") }
            }
            if q.kind == .numerical { guard let n = Double(q.answer), n.isFinite else { throw DataError.invalid("Invalid numerical answer") } }
        }
    }
}
