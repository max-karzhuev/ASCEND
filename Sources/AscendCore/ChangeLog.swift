import Foundation

public enum EntityKind: String, Codable, CaseIterable, Sendable {
    case profile, category, quest, revision, occurrence, completion, goal, contribution, milestone, session, attempt, timezone, reset
}
/// Immutable operations. Lamport order is independent of wall-clock accuracy.
public struct Change: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var actor: String
    public var clock: Int64
    public var generation: String
    public var kind: EntityKind
    public var entityID: String
    public var fields: [String: String]
    public var deleted: Bool
    public var createdAt: Date
    public init(actor: String, clock: Int64, generation: String = "initial", kind: EntityKind, entityID: String, fields: [String: String], deleted: Bool = false) {
        id = UUID().uuidString; self.actor = actor; self.clock = clock; self.generation = generation
        self.kind = kind; self.entityID = entityID; self.fields = fields; self.deleted = deleted; createdAt = Date()
    }
    public var priority: Int { kind == .completion && fields["active"] == "false" ? 1 : 0 }
    public static func ordered(_ a: Change, _ b: Change) -> Bool {
        if a.clock != b.clock { return a.clock < b.clock }
        if a.priority != b.priority { return a.priority < b.priority }
        if a.actor != b.actor { return a.actor < b.actor }
        return a.id < b.id
    }
}

public enum Codec {
    public static func fields<T: Encodable>(_ value: T) throws -> [String: String] {
        let data = try JSONEncoder().encode(value)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw DataError.invalid("Expected an object") }
        return try object.mapValues { String(decoding: try JSONSerialization.data(withJSONObject: $0, options: [.fragmentsAllowed, .sortedKeys]), as: UTF8.self) }
    }
    public static func decode<T: Decodable>(_ type: T.Type, fields: [String: String]) throws -> T {
        let object = try fields.mapValues { try JSONSerialization.jsonObject(with: Data($0.utf8), options: .fragmentsAllowed) }
        return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object, options: .sortedKeys))
    }
    public static func patch<T: Encodable>(_ value: T, from old: T?) throws -> [String: String] {
        let next = try fields(value); let previous = try old.map(fields) ?? [:]
        // Include explicit nulls for removed optionals, otherwise a cleared reminder would remain set.
        return Dictionary(uniqueKeysWithValues: Set(next.keys).union(previous.keys).compactMap { key in
            let v = next[key] ?? "null"; return v == previous[key] ? nil : (key, v)
        })
    }
}
public enum DataError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

public struct Ledger: Sendable {
    public private(set) var changes: [Change]
    public let maxClock: Int64
    public let generation: String
    public let current: [Change]
    private let index: [EntityKind: [String: [Change]]]
    public init(changes: [Change] = []) {
        // Colliding operation IDs with different payloads are rejected at the import/sync boundary.
        self.changes = Dictionary(changes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }).values.sorted(by: Change.ordered)
        self.maxClock = self.changes.map(\.clock).max() ?? 0
        let generation = self.changes.last(where: { $0.kind == .reset })?.entityID ?? "initial"
        self.generation = generation
        self.current = self.changes.filter { $0.generation == generation && $0.kind != .reset }
        self.index = Dictionary(grouping: self.current, by: \.kind).mapValues { Dictionary(grouping: $0, by: \.entityID) }
    }
    public func operations(_ kind: EntityKind, _ id: String) -> [Change] { index[kind]?[id] ?? [] }
    public func isDeleted(_ kind: EntityKind, _ id: String) -> Bool { operations(kind, id).contains(where: \.deleted) }
    public func fields(_ kind: EntityKind, _ id: String) -> [String: String]? {
        let ops = operations(kind, id)
        guard !ops.isEmpty, !ops.contains(where: \.deleted) else { return nil }
        // Occurrence snapshots are first-writer-wins and atomic. Their first Lamport identity
        // freezes historical plans; explicit edits live in the separate quest/occurrence override.
        if kind == .occurrence { return ops.first?.fields }
        // Completion and attempt submissions are atomic, so two devices cannot blend a
        // completion's reward with another operation's goal quantity or answer.
        if kind == .completion { return ops.last?.fields }
        if kind == .attempt {
            // Drafts never unsubmit a previously submitted answer after an offline merge.
            var result = (ops.last(where: { $0.fields["submitted"] == "true" }) ?? ops.last)?.fields ?? [:]
            let hints = ops.compactMap { $0.fields["hintsUsed"].flatMap(Int.init) }.max() ?? 0
            result["hintsUsed"] = String(hints)
            if let report = ops.last(where: { $0.fields["reported"] == "true" }) { result["reported"] = "true"; result["report"] = report.fields["report"] }
            return result
        }
        var result: [String: String] = [:]
        for op in ops { result.merge(op.fields, uniquingKeysWith: { _, new in new }) }
        return result
    }
    public func value<T: Decodable>(_ type: T.Type, kind: EntityKind, id: String) -> T? {
        guard let fields = fields(kind, id) else { return nil }
        return try? Codec.decode(type, fields: fields)
    }
    public func values<T: Decodable>(_ type: T.Type, kind: EntityKind) -> [T] {
        (index[kind]?.keys.sorted() ?? []).compactMap { value(type, kind: kind, id: $0) }
    }
    public func merged(with incoming: [Change]) throws -> Ledger {
        var byID = Dictionary(uniqueKeysWithValues: changes.map { ($0.id, $0) })
        for change in incoming {
            if let old = byID[change.id], old != change { throw DataError.invalid("Conflicting payloads for an immutable operation") }
            byID[change.id] = change
        }
        return Ledger(changes: Array(byID.values))
    }
    public var profile: Profile { value(Profile.self, kind: .profile, id: "shared") ?? Profile() }
    public var quests: [Quest] { values(Quest.self, kind: .quest) }
    public var goals: [Goal] { values(Goal.self, kind: .goal) }
    public var occurrences: [Occurrence] { values(Occurrence.self, kind: .occurrence).filter(\.available) }
    public var completions: [Completion] { values(Completion.self, kind: .completion).filter(\.active) }
    public var sessions: [LearningSession] { values(LearningSession.self, kind: .session) }
    public var attempts: [Attempt] { values(Attempt.self, kind: .attempt) }
    public func completion(_ id: String) -> Completion? { value(Completion.self, kind: .completion, id: id) }
    public func effectiveZone(at now: Date) -> String {
        let transitions = values(TimeZoneTransition.self, kind: .timezone).filter { $0.effectiveAt <= now }
        return transitions.sorted { a, b in
            if a.effectiveAt != b.effectiveAt { return a.effectiveAt < b.effectiveAt }
            let ac = operations(.timezone, a.id).last!, bc = operations(.timezone, b.id).last!
            return Change.ordered(ac, bc)
        }.last?.timeZone ?? profile.timeZone
    }
}

public struct Archive: Codable {
    public var version = 1
    public var exportedAt = Date()
    public var changes: [Change]
    public init(changes: [Change]) { self.changes = changes }
    public func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
    public static func decode(_ data: Data, mergingInto existing: Ledger = Ledger()) throws -> Archive {
        guard data.count <= 50_000_000 else { throw DataError.invalid("Archive exceeds 50 MB") }
        let archive = try JSONDecoder().decode(Archive.self, from: data)
        guard archive.version == 1, archive.changes.count <= 100_000 else { throw DataError.invalid("Unsupported archive version or size") }
        for c in archive.changes { try validateChange(c) }
        let ledger = try existing.merged(with: archive.changes)
        try validate(ledger)
        return archive
    }
    public static func validate(_ ledger: Ledger) throws {
        for change in ledger.changes { try validateChange(change) }
        func exists(_ kind: EntityKind, _ id: String) -> Bool { !ledger.operations(kind, id).isEmpty }
        func questReferences(_ q: Quest) throws {
            guard q.goalID.isEmpty || exists(.goal, q.goalID) else { throw DataError.invalid("Quest references a missing goal") }
            guard Category.defaults.contains(where: { $0.id == q.category }) || exists(.category, q.category) else { throw DataError.invalid("Quest references a missing category") }
        }
        // Validate every complete entity before any disk mutation; tombstones may retain references.
        for kind in EntityKind.allCases where kind != .reset {
            for id in Set(ledger.current.filter { $0.kind == kind }.map(\.entityID)) {
                guard let f = ledger.fields(kind, id) else { continue }
                switch kind {
                case .profile:
                    let p = try Codec.decode(Profile.self, fields: f)
                    guard TimeZone(identifier: p.timeZone) != nil, p.name.count <= 100 else { throw DataError.invalid("Invalid profile") }
                case .quest:
                    let q = try Codec.decode(Quest.self, fields: f); try validateQuest(q); try questReferences(q)
                    guard q.id == id else { throw DataError.invalid("Quest identity mismatch") }
                case .revision:
                    let r = try Codec.decode(QuestRevision.self, fields: f); try validateQuest(r.quest); try questReferences(r.quest)
                    guard r.id == id, exists(.quest, r.quest.id), Planning.validDay(r.effectiveDay) else { throw DataError.invalid("Invalid routine revision") }
                    if let patch = r.changedFields {
                        let full = try Codec.fields(r.quest)
                        guard patch.allSatisfy({ full[$0.key] == $0.value || ($0.key == "reminderMinutes" && $0.value == "null" && r.quest.reminderMinutes == nil) }) else { throw DataError.invalid("Revision patch does not match its snapshot") }
                    }
                case .occurrence:
                    let o = try Codec.decode(Occurrence.self, fields: f); try validateQuest(o.quest)
                    try questReferences(o.quest)
                    guard o.id == id, o.quest.id == o.templateID, exists(.quest, o.templateID), Planning.validDay(o.day), TimeZone(identifier: o.timeZone) != nil else { throw DataError.invalid("Invalid occurrence or missing template") }
                case .goal:
                    let g = try Codec.decode(Goal.self, fields: f)
                    guard g.id == id, g.target.isFinite, g.target > 0, g.milestones.allSatisfy({ $0.weight.isFinite && $0.weight > 0 }), Set(g.milestones.map(\.id)).count == g.milestones.count else { throw DataError.invalid("Invalid goal") }
                case .contribution:
                    let c = try Codec.decode(Contribution.self, fields: f)
                    guard c.id == id, c.amount.isFinite, c.amount > 0, Planning.validDay(c.day), exists(.goal, c.goalID) else { throw DataError.invalid("Invalid contribution or missing goal") }
                case .completion:
                    let c = try Codec.decode(Completion.self, fields: f)
                    guard c.id == id, c.id == c.occurrenceID, [10,25,50].contains(c.xp), c.amount.isFinite, c.amount >= 0, Planning.validDay(c.day), exists(.occurrence, c.occurrenceID), c.goalID.isEmpty || exists(.goal, c.goalID) else { throw DataError.invalid("Invalid completion or missing relationship") }
                case .session:
                    let s = try Codec.decode(LearningSession.self, fields: f); try LearningRules.validate(s.questions, count: s.config.count)
                    guard s.id == id, Planning.validDay(s.day) else { throw DataError.invalid("Invalid learning session identity") }
                case .attempt:
                    let a = try Codec.decode(Attempt.self, fields: f)
                    guard a.id == id, a.id == "\(a.sessionID)|\(a.questionID)", Planning.validDay(a.day), let s = ledger.value(LearningSession.self, kind: .session, id: a.sessionID), s.questions.contains(where: { $0.id == a.questionID }), a.answer.count <= 12000, a.hintsUsed >= 0, a.hintsUsed <= 3 else { throw DataError.invalid("Invalid learning attempt") }
                case .category: _ = try Codec.decode(Category.self, fields: f)
                case .milestone:
                    let m = try Codec.decode(MilestoneCheck.self, fields: f)
                    guard m.id == id, exists(.goal, m.goalID) else { throw DataError.invalid("Invalid milestone relationship") }
                case .timezone:
                    let t = try Codec.decode(TimeZoneTransition.self, fields: f)
                    guard TimeZone(identifier: t.timeZone) != nil else { throw DataError.invalid("Unknown planning timezone") }
                case .reset: break
                }
            }
        }
    }
    static func validateChange(_ c: Change) throws {
        guard !c.id.isEmpty, c.id.count < 200, !c.actor.isEmpty, c.actor.count < 200, !c.entityID.isEmpty, c.entityID.count < 500,
              !c.generation.isEmpty, c.generation.count < 200, c.clock > 0, c.clock < Int64.max - 1_000_000, c.fields.count <= 50,
              c.fields.values.allSatisfy({ $0.utf8.count <= 200_000 }), try JSONEncoder().encode(c).count <= 250_000 else { throw DataError.invalid("Invalid operation or record size") }
        for v in c.fields.values { _ = try JSONSerialization.jsonObject(with: Data(v.utf8), options: .fragmentsAllowed) }
    }
    static func validateQuest(_ q: Quest) throws {
        guard !q.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, q.title.count <= 200, q.notes.count <= 10000,
              Planning.validDay(q.startDay), q.deadline.isEmpty || Planning.validDay(q.deadline),
              (1...20).contains(q.weeklyTarget), q.weekdays.allSatisfy({ (1...7).contains($0) }),
              q.contribution.isFinite, q.contribution >= 0,
              q.reminderMinutes == nil || (0..<1440).contains(q.reminderMinutes!) else { throw DataError.invalid("Invalid quest fields") }
    }
}
