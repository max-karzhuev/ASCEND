import Foundation
import SwiftData
import Observation

@Model final class StoredChange {
    var id: String
    var payload: Data
    var uploaded: Bool
    init(_ change: Change, uploaded: Bool = false) throws {
        id = change.id; payload = try JSONEncoder().encode(change); self.uploaded = uploaded
        guard payload.count <= 250_000 else { throw DataError.invalid("This record exceeds the sync size limit. Shorten the notes or learning session.") }
    }
}
@Model final class StoredMetadata {
    var key: String
    var value: Data
    init(key: String, value: Data) { self.key = key; self.value = value }
}

@MainActor @Observable final class AppStore {
    private(set) var ledger = Ledger()
    private(set) var actor = UUID().uuidString
    var error: String?
    var toast: String?
    var isDemo = false
    var isValidation = false
    var clockNow = Date()
    let container: ModelContainer
    let context: ModelContext
    var didChange: (() -> Void)?
    var today: String { planning.day(clockNow) }
    var planning: Planning { Planning(zone: ledger.effectiveZone(at: clockNow)) }
    var profile: Profile { ledger.profile }
    var progress: PlayerProgress { Progression.player(xp: Progression.totalXP(ledger)) }
    var categories: [Category] { ledger.values(Category.self, kind: .category).sorted { $0.name < $1.name } }
    var activeGoals: [Goal] { ledger.goals.filter { !$0.archived }.sorted { $0.title < $1.title } }
    var syncEnabled: Bool { metadataString("syncEnabled") == "true" && !isDemo }

    init(inMemory: Bool = false, validation: Bool = false) throws {
        let schema = Schema([StoredChange.self, StoredMetadata.self])
        let config: ModelConfiguration
        if inMemory { config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none) }
        else {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let directory = support.appendingPathComponent(validation ? "ASCEND-Validation" : "ASCEND", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            config = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("history.store"), cloudKitDatabase: .none)
        }
        container = try ModelContainer(for: schema, configurations: [config]); context = ModelContext(container)
        context.autosaveEnabled = false
        isValidation = validation
        ledger = Ledger(changes: try context.fetch(FetchDescriptor<StoredChange>()).map { try JSONDecoder().decode(Change.self, from: $0.payload) })
        if let saved = metadataString("actor") { actor = saved }
        else { try setMetadata("actor", string: actor) }
        // No seed progress. Profile/category defaults are written only after onboarding.
    }
    func perform(_ action: () throws -> Void) { do { try action() } catch { self.error = error.localizedDescription } }
    func metadata(_ key: String) -> Data? { (try? context.fetch(FetchDescriptor<StoredMetadata>()))?.first { $0.key == key }?.value }
    func metadataString(_ key: String) -> String? { metadata(key).flatMap { String(data: $0, encoding: .utf8) } }
    func setMetadata(_ key: String, string: String) throws { try setMetadata(key, data: Data(string.utf8)) }
    func setMetadata(_ key: String, data: Data) throws {
        if let row = try context.fetch(FetchDescriptor<StoredMetadata>()).first(where: { $0.key == key }) { row.value = data }
        else { context.insert(StoredMetadata(key: key, value: data)) }
        do { try context.save() } catch { context.rollback(); throw error }
    }
    private func commit(_ changes: [Change], uploaded: Bool = false, token: Data? = nil) throws {
        let merged = try ledger.merged(with: changes)
        var known = Set(ledger.changes.map(\.id))
        do {
            for change in changes where known.insert(change.id).inserted { context.insert(try StoredChange(change, uploaded: uploaded)) }
            if let token {
                if let row = try context.fetch(FetchDescriptor<StoredMetadata>()).first(where: { $0.key == "cloudToken" }) { row.value = token }
                else { context.insert(StoredMetadata(key: "cloudToken", value: token)) }
            }
            try context.save(); ledger = merged
        } catch { context.rollback(); throw error }
        #if os(macOS)
        publishWidget()
        #endif
        didChange?()
    }
    func put<T: Encodable>(_ value: T, kind: EntityKind, id: String, old: T? = nil, atomic: Bool = false) throws {
        let fields = try atomic ? Codec.fields(value) : Codec.patch(value, from: old)
        guard !fields.isEmpty else { return }
        try commit([Change(actor: actor, clock: ledger.maxClock + 1, generation: ledger.generation, kind: kind, entityID: id, fields: fields)])
    }
    func delete(kind: EntityKind, id: String) throws {
        try commit([Change(actor: actor, clock: ledger.maxClock + 1, generation: ledger.generation, kind: kind, entityID: id, fields: [:], deleted: true)])
    }
    func saveProfile(_ profile: Profile, old: Profile? = nil) throws { try put(profile, kind: .profile, id: "shared", old: old ?? ledger.profile) }
    func onboard(profile: Profile, firstQuest: String, selectedCategories: Set<String>) throws {
        var p = profile; p.onboarded = true; p.startedDay = Planning(zone: p.timeZone).day(Date())
        try put(p, kind: .profile, id: "shared")
        for c in Category.defaults { var category = c; category.archived = !selectedCategories.contains(c.id); try put(category, kind: .category, id: c.id) }
        if !firstQuest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var q = Quest(); q.title = firstQuest; q.startDay = today
            q.category = selectedCategories.sorted().first ?? "knowledge"; try saveQuest(q)
        }
    }
    func saveQuest(_ quest: Quest, old: Quest? = nil) throws {
        try Archive.validateQuest(quest)
        try reconcile()
        let effective = old == nil ? quest.startDay : quest.schedule == .weekly ? planning.adding(7, to: planning.week(today)) : planning.adding(1, to: today)
        // One-off changes update their occurrence via a separate override; routines start tomorrow.
        let patch = try Codec.patch(quest, from: old)
        let revision = QuestRevision(quest: quest, effectiveDay: effective, changedFields: patch)
        let qChange = Change(actor: actor, clock: ledger.maxClock + 1, generation: ledger.generation, kind: .quest, entityID: quest.id, fields: patch)
        let rChange = Change(actor: actor, clock: ledger.maxClock + 2, generation: ledger.generation, kind: .revision, entityID: revision.id, fields: try Codec.fields(revision))
        try commit([qChange, rChange])
        if old?.schedule == .once, quest.schedule == .once, let occurrence = ledger.occurrences.first(where: { $0.templateID == quest.id }) { try editOccurrence(occurrence, quest: quest) }
        try reconcile()
    }
    func archiveQuest(_ quest: Quest) throws { var q = quest; q.archived = true; try saveQuest(q, old: quest) }
    func editOccurrence(_ occurrence: Occurrence, quest: Quest) throws {
        // Occurrence-only details live under a distinct quest key, leaving its frozen plan intact.
        var q = quest; q.id = "override|\(occurrence.id)"
        let old = ledger.value(Quest.self, kind: .quest, id: q.id)
        try put(q, kind: .quest, id: q.id, old: old)
    }
    func displayOccurrence(_ occurrence: Occurrence) -> Occurrence {
        var o = occurrence
        if let override = ledger.value(Quest.self, kind: .quest, id: "override|\(o.id)") { o.quest = override }
        return o
    }
    func reconcile() throws {
        clockNow = Date()
        let missing = Recurrence.missingSnapshots(ledger: ledger, now: Date())
        guard !missing.isEmpty else { return }
        let changes = try missing.enumerated().map { index, o in
            Change(actor: actor, clock: ledger.maxClock + Int64(index) + 1, generation: ledger.generation, kind: .occurrence, entityID: o.id, fields: try Codec.fields(o))
        }
        try commit(changes)
    }
    func complete(_ occurrence: Occurrence) throws {
        guard !ledger.isDeleted(.quest, occurrence.templateID), !ledger.isDeleted(.occurrence, occurrence.id) else {
            throw DataError.invalid("This quest was deleted.")
        }
        if ledger.completion(occurrence.id)?.active == true { return }
        var o = displayOccurrence(occurrence)
        guard o.available, o.day <= today else { throw DataError.invalid("Future quests become available on their scheduled day") }
        if ledger.value(Occurrence.self, kind: .occurrence, id: o.id) == nil { try put(o, kind: .occurrence, id: o.id) }
        // Re-completion restores the original reward and quantity, even if difficulty changed.
        var c = ledger.completion(o.id) ?? Completion(occurrence: o, day: o.weeklySlot == nil ? o.day : today)
        c.active = true
        let previousLevel = progress.level
        try put(c, kind: .completion, id: c.id, atomic: true)
        toast = progress.level > previousLevel ? "Level \(progress.level). Keep rising." : "+\(c.xp) XP · Quest complete"
        o.quest.id = occurrence.quest.id
    }
    func undo(_ occurrence: Occurrence) throws {
        guard var c = ledger.completion(occurrence.id), c.active else { return }
        c.active = false; try put(c, kind: .completion, id: c.id, atomic: true); toast = "Completion undone"
    }
    func toggle(_ occurrence: Occurrence) { perform { if ledger.completion(occurrence.id)?.active == true { try undo(occurrence) } else { try complete(occurrence) } } }
    func occurrences(on day: String) -> [Occurrence] {
        let list = day <= today ? ledger.occurrences.filter { $0.day == day && $0.weeklySlot == nil } : Recurrence.projected(on: day, ledger: ledger, zone: planning.zone)
        return list.map(displayOccurrence).sorted { $0.quest.title < $1.quest.title }
    }
    var todayQuests: [Occurrence] {
        let scheduled = occurrences(on: today).filter { o in o.quest.schedule != .once || ledger.quests.first(where: { $0.id == o.templateID })?.archived != true || ledger.completion(o.id)?.active == true }
        let overdue = ledger.occurrences.filter { occurrence in occurrence.quest.schedule == .once && occurrence.day < today && ledger.completion(occurrence.id)?.active != true && ledger.quests.first(where: { q in q.id == occurrence.templateID })?.archived != true }
        return (scheduled + overdue.map(displayOccurrence)).sorted { $0.quest.title < $1.quest.title }
    }
    func changeTimeZone(_ zone: String) throws {
        guard TimeZone(identifier: zone) != nil else { throw DataError.invalid("Choose a valid IANA timezone, such as America/Toronto") }
        try reconcile()
        let transition = TimeZoneTransition(timeZone: zone, effectiveAt: planning.nextMidnight(after: Date()))
        try put(transition, kind: .timezone, id: transition.id)
    }
    func receive(_ incoming: [Change], token: Data) throws {
        let merged = try ledger.merged(with: incoming); try Archive.validate(merged)
        try commit(incoming, uploaded: true, token: token)
    }
    func pending() throws -> [StoredChange] { try context.fetch(FetchDescriptor<StoredChange>()).filter { !$0.uploaded } }
    func markUploaded(_ ids: Set<String>) throws {
        for row in try context.fetch(FetchDescriptor<StoredChange>()) where ids.contains(row.id) { row.uploaded = true }
        do { try context.save() } catch { context.rollback(); throw error }
    }
    func importData(_ data: Data) throws {
        let archive = try Archive.decode(data, mergingInto: ledger)
        try commit(archive.changes); try reconcile()
    }
    func resetEverywhere() throws {
        let reset = Change(actor: actor, clock: ledger.maxClock + 1, generation: ledger.generation, kind: .reset, entityID: UUID().uuidString, fields: [:])
        try commit([reset]); toast = "History reset. Cloud deletion will propagate at the next successful exchange."
    }
    func clearLocal() throws {
        do {
            for row in try context.fetch(FetchDescriptor<StoredChange>()) { context.delete(row) }
            for row in try context.fetch(FetchDescriptor<StoredMetadata>()) { context.delete(row) }
            try context.save(); ledger = Ledger(); actor = UUID().uuidString; try setMetadata("actor", string: actor)
        }
        catch { context.rollback(); throw error }
        #if os(macOS)
        publishWidget()
        #endif
        didChange?()
    }
}
