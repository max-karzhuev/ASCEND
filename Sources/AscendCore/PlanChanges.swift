import Foundation

/// Builds one validated transaction for related planning records.
public struct PlanChanges {
    public private(set) var ledger: Ledger
    public private(set) var changes: [Change] = []
    public let actor: String
    public let day: String
    public let planning: Planning
    public init(ledger: Ledger, actor: String, day: String, planning: Planning) {
        self.ledger = ledger; self.actor = actor; self.day = day; self.planning = planning
    }
    public mutating func put<T: Encodable>(_ value: T, kind: EntityKind, id: String) throws {
        try append(Change(actor: actor, clock: ledger.maxClock + 1, generation: ledger.generation,
                          kind: kind, entityID: id, fields: Codec.fields(value)))
    }
    public mutating func remove(kind: EntityKind, id: String) throws {
        try append(Change(actor: actor, clock: ledger.maxClock + 1, generation: ledger.generation,
                          kind: kind, entityID: id, fields: [:], deleted: true))
    }
    private mutating func append(_ change: Change) throws {
        ledger = try ledger.merged(with: [change]); changes.append(change)
    }
    public mutating func snapshots(now: Date) throws {
        for occurrence in Recurrence.missingSnapshots(ledger: ledger, now: now) {
            try put(occurrence, kind: .occurrence, id: occurrence.id)
        }
    }
    public mutating func workout(_ plan: WorkoutPlan, deleting: Bool = false) throws {
        try plan.validate()
        if deleting { try remove(kind: .workoutPlan, id: plan.id) }
        else { try put(plan, kind: .workoutPlan, id: plan.id) }
        var quest = ledger.value(Quest.self, kind: .quest, id: plan.questID) ?? Quest()
        quest.id = plan.questID; quest.title = plan.name; quest.category = "strength"
        quest.notes = plan.exercises.map { exercise in
            "\(exercise.name) · \(exercise.sets) sets · \(exercise.prescription) · \(exercise.muscles.sorted { $0.rawValue < $1.rawValue }.map(\.title).joined(separator: ", "))"
        }.joined(separator: "\n")
        quest.notes = String(quest.notes.prefix(10000))
        quest.schedule = .weekdays; quest.weekdays = plan.weekdays.sorted()
        quest.archived = deleting || plan.weekdays.isEmpty
        if quest.startDay.isEmpty { quest.startDay = day }
        try put(quest, kind: .quest, id: quest.id)
        let revision = QuestRevision(quest: quest, effectiveDay: day)
        try put(revision, kind: .revision, id: revision.id)
        var occurrence = planning.occurrence(quest, on: day)
        occurrence.revised = true
        // Edits affect today's open workout and future dates, preserving completed and historical plans.
        // An unscheduled day is replaced by an unavailable snapshot, not a tombstone, so it can return.
        if ledger.completion(occurrence.id)?.active != true, !ledger.isDeleted(.occurrence, occurrence.id),
           occurrence.available || ledger.value(Occurrence.self, kind: .occurrence, id: occurrence.id) != nil {
            try put(occurrence, kind: .occurrence, id: occurrence.id)
        }
    }
    public mutating func removeWorkoutLog(_ log: WorkoutLog) throws {
        try remove(kind: .workoutLog, id: log.id)
        let id = "workout|\(log.planID)|day|\(log.day)"
        guard var completion = ledger.completion(id), completion.active, completion.workoutLogID == log.id else { return }
        let replacement = ledger.values(WorkoutLog.self, kind: .workoutLog).first {
            $0.planID == log.planID && $0.day == log.day && Set($0.exercises.map(\.id)) == Set(log.exercises.map(\.id))
        }
        completion.active = replacement != nil; completion.workoutLogID = replacement?.id
        try put(completion, kind: .completion, id: id)
    }
    public mutating func logWorkout(_ log: WorkoutLog) throws {
        try log.validate()
        guard let plan = ledger.value(WorkoutPlan.self, kind: .workoutPlan, id: log.planID), log.day == day else {
            throw DataError.invalid("Reopen the workout to log it for today.")
        }
        guard ledger.operations(.workoutLog, log.id).isEmpty else { return }
        try put(log, kind: .workoutLog, id: log.id)
        let id = "\(plan.questID)|day|\(day)"
        if Set(log.exercises.map(\.id)) == Set(plan.exercises.map(\.id)),
           let occurrence = ledger.value(Occurrence.self, kind: .occurrence, id: id), occurrence.available,
           !ledger.isDeleted(.occurrence, id), ledger.completion(id)?.active != true {
            var completion = ledger.completion(id) ?? Completion(occurrence: occurrence, day: day)
            completion.active = true; completion.workoutLogID = log.id
            try put(completion, kind: .completion, id: id)
        }
    }
}
extension WorkoutPlan {
    public var questID: String { "workout|\(id)" }
}
extension Quest {
    public var workoutPlanID: String? { id.hasPrefix("workout|") ? String(id.dropFirst("workout|".count)) : nil }
}
