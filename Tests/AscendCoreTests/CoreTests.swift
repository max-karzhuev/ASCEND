import XCTest
@testable import AscendCore

final class CoreTests: XCTestCase {
    let p = Planning(zone: "America/Toronto")
    func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    func quest(_ schedule: Schedule = .daily, start: String = "2026-03-06") -> Quest {
        var q = Quest(); q.id = "quest-1"; q.title = "Practice"; q.startDay = start; q.schedule = schedule; return q
    }
    func op<T: Encodable>(_ value: T, kind: EntityKind, id: String, clock: Int64 = 1, actor: String = "A", generation: String = "initial") throws -> Change {
        Change(actor: actor, clock: clock, generation: generation, kind: kind, entityID: id, fields: try Codec.fields(value))
    }
    func plannedLedger(_ q: Quest, through day: String) throws -> Ledger {
        var profile = Profile(); profile.timeZone = p.zone; profile.startedDay = q.startDay
        let revision = QuestRevision(quest: q, effectiveDay: q.startDay)
        var ledger = Ledger(changes: [try op(profile, kind: .profile, id: "shared"), try op(q, kind: .quest, id: q.id), try op(revision, kind: .revision, id: revision.id)])
        let snapshots = Recurrence.missingSnapshots(ledger: ledger, now: p.date(day))
        ledger = try ledger.merged(with: snapshots.enumerated().map { try op($0.element, kind: .occurrence, id: $0.element.id, clock: Int64($0.offset + 2)) })
        return ledger
    }
    func complete(_ ledger: Ledger, ids: [String]) throws -> Ledger {
        try ledger.merged(with: ledger.occurrences.filter { ids.contains($0.id) }.enumerated().map { try op(Completion(occurrence: $0.element), kind: .completion, id: $0.element.id, clock: ledger.maxClock + Int64($0.offset) + 1) })
    }
    func testDaylightSavingSpringAndFallHaveOneCivilOccurrence() throws {
        XCTAssertEqual(p.day(date("2026-03-08T04:59:00Z")), "2026-03-07")
        XCTAssertEqual(p.day(date("2026-03-08T05:01:00Z")), "2026-03-08")
        XCTAssertEqual(p.day(date("2026-11-01T05:30:00Z")), p.day(date("2026-11-01T06:30:00Z")))
        let ledger = try plannedLedger(quest(start: "2026-03-07"), through: "2026-03-09")
        XCTAssertEqual(ledger.occurrences.count, 3)
        XCTAssertTrue(Recurrence.missingSnapshots(ledger: ledger, now: p.date("2026-03-09")).isEmpty)
        XCTAssertEqual(p.nextMidnight(after: date("2026-03-08T05:00:00Z")).timeIntervalSince(date("2026-03-08T05:00:00Z")), 23 * 3600)
    }
    func testSharedTimezoneOverridesDeviceDay() throws {
        let instant = date("2026-11-21T02:00:00Z")
        XCTAssertEqual(Planning(zone: "America/Toronto").day(instant), "2026-11-20")
        XCTAssertEqual(Planning(zone: "Asia/Tokyo").day(instant), "2026-11-21")
    }
    func testTimezoneTransitionPreservesExistingDayAssignments() throws {
        let ledger = try plannedLedger(quest(), through: "2026-03-08")
        let transition = TimeZoneTransition(timeZone: "Asia/Tokyo", effectiveAt: date("2026-03-09T04:00:00Z"))
        let next = try ledger.merged(with: [op(transition, kind: .timezone, id: transition.id, clock: 20)])
        XCTAssertEqual(next.effectiveZone(at: date("2026-03-09T03:59:00Z")), p.zone)
        XCTAssertEqual(next.effectiveZone(at: date("2026-03-09T04:00:00Z")), "Asia/Tokyo")
        XCTAssertEqual(next.occurrences, ledger.occurrences)
    }
    func testWeekdayScheduleAndMondayBoundaries() {
        let q = quest(.weekdays)
        XCTAssertTrue(p.occurrence(q, on: "2026-03-06").planned)
        XCTAssertFalse(p.occurrence(q, on: "2026-03-07").planned)
        XCTAssertEqual(p.week("2026-03-08"), "2026-03-02")
        XCTAssertEqual(p.week("2026-03-09"), "2026-03-09")
    }
    func testRepeatedReconciliationDoesNotDuplicateOccurrences() throws {
        let ledger = try plannedLedger(quest(), through: "2026-03-12")
        XCTAssertEqual(ledger.occurrences.count, 7)
        XCTAssertTrue(Recurrence.missingSnapshots(ledger: ledger, now: p.date("2026-03-12")).isEmpty)
    }
    func testRoutineEditingAndArchivingPreservesHistory() throws {
        var q = quest(); var ledger = try plannedLedger(q, through: "2026-03-08")
        let previous = ledger.occurrences
        q.archived = true
        let revision = QuestRevision(quest: q, effectiveDay: "2026-03-09")
        ledger = try ledger.merged(with: [op(q, kind: .quest, id: q.id, clock: 20), op(revision, kind: .revision, id: revision.id, clock: 21)])
        XCTAssertEqual(ledger.occurrences, previous)
        XCTAssertTrue(Recurrence.projected(on: "2026-03-09", ledger: ledger, zone: p.zone).isEmpty)
    }
    func testFrozenSnapshotWinsOverLaterSnapshot() throws {
        let q = quest(); let original = p.occurrence(q, on: q.startDay)
        var newer = original; newer.quest.title = "Changed"; newer.planned = false
        let ledger = Ledger(changes: [try op(newer, kind: .occurrence, id: original.id, clock: 99), try op(original, kind: .occurrence, id: original.id)])
        XCTAssertEqual(ledger.value(Occurrence.self, kind: .occurrence, id: original.id), original)
    }
    func testIndependentFutureRoutineEditsComposeWithoutRewritingHistory() throws {
        let q = quest(), base = try plannedLedger(quest(), through: "2026-03-08")
        var renamed = q; renamed.title = "Read"
        var harder = q; harder.difficulty = .hard
        let name = QuestRevision(quest: renamed, effectiveDay: "2026-03-09", changedFields: ["title": "\"Read\""])
        let difficulty = QuestRevision(quest: harder, effectiveDay: "2026-03-09", changedFields: ["difficulty": "\"hard\""])
        let a = try op(name, kind: .revision, id: name.id, clock: 20, actor: "phone")
        let b = try op(difficulty, kind: .revision, id: difficulty.id, clock: 20, actor: "mac")
        let merged = try base.merged(with: [a, b]), reversed = try base.merged(with: [b, a])
        let projected = Recurrence.revision(for: q.id, day: "2026-03-09", ledger: merged)
        XCTAssertEqual(projected?.title, "Read"); XCTAssertEqual(projected?.difficulty, .hard)
        XCTAssertEqual(projected, Recurrence.revision(for: q.id, day: "2026-03-09", ledger: reversed))
        XCTAssertEqual(Recurrence.revision(for: q.id, day: "2026-03-08", ledger: merged), q)
        XCTAssertEqual(merged.occurrences, base.occurrences)
    }
    func testWeeklyTargetsUseStableExplicitSessionsAndNoDailyDenominator() throws {
        let q = quest(.weekly)
        let a = Recurrence.weeklySession(quest: q, day: "2026-03-06", zone: p.zone, sessionID: "session-A")
        let retry = Recurrence.weeklySession(quest: q, day: "2026-03-06", zone: p.zone, sessionID: "session-A")
        let b = Recurrence.weeklySession(quest: q, day: "2026-03-06", zone: p.zone, sessionID: "session-B")
        XCTAssertEqual(a.id, retry.id); XCTAssertNotEqual(a.id, b.id); XCTAssertFalse(a.planned)
        let changes = try [op(a, kind: .occurrence, id: a.id), op(b, kind: .occurrence, id: b.id), op(Completion(occurrence: a), kind: .completion, id: a.id, clock: 2), op(Completion(occurrence: b), kind: .completion, id: b.id, clock: 2)]
        let merged = Ledger(changes: changes + changes)
        XCTAssertEqual(Progression.totalXP(merged), 50)
        XCTAssertEqual(Recurrence.loggedSessions(templateID: q.id, day: "2026-03-08", zone: p.zone, ledger: merged).count, 2)
        XCTAssertEqual(Recurrence.loggedSessions(templateID: q.id, day: "2026-03-09", zone: p.zone, ledger: merged).count, 0)
        XCTAssertTrue(try plannedLedger(q, through: "2026-03-09").occurrences.isEmpty)
    }
    func testCompleteOnBothDevicesAwardsOneRewardAndContribution() throws {
        var q = quest(); q.goalID = "goal"; q.contribution = 2
        let base = try plannedLedger(q, through: q.startDay), o = base.occurrences[0]
        let a = try op(Completion(occurrence: o), kind: .completion, id: o.id, clock: 5, actor: "phone")
        let b = try op(Completion(occurrence: o), kind: .completion, id: o.id, clock: 5, actor: "mac")
        let merged = try base.merged(with: [a,b,a,b])
        XCTAssertEqual(Progression.totalXP(merged), 25)
        var goal = Goal(); goal.id = "goal"
        XCTAssertEqual(Progression.goalValue(goal, ledger: merged), 2)
    }
    func testUndoExactlyReversesRewardAndGoal() throws {
        var q = quest(); q.goalID = "goal"; q.contribution = 1.5
        var ledger = try plannedLedger(q, through: q.startDay); let o = ledger.occurrences[0]
        ledger = try complete(ledger, ids: [o.id]); var undone = Completion(occurrence: o); undone.active = false
        let undo = try op(undone, kind: .completion, id: o.id, clock: 100)
        ledger = try ledger.merged(with: [undo,undo])
        var goal = Goal(); goal.id = "goal"
        XCTAssertEqual(Progression.totalXP(ledger), 0); XCTAssertEqual(Progression.goalValue(goal, ledger: ledger), 0)
    }
    func testDifficultyEditDoesNotRewriteEarnedXP() throws {
        var q = quest(); var ledger = try plannedLedger(q, through: q.startDay)
        ledger = try complete(ledger, ids: ledger.occurrences.map(\.id)); q.difficulty = .hard
        ledger = try ledger.merged(with: [op(q, kind: .quest, id: q.id, clock: 100)])
        XCTAssertEqual(Progression.totalXP(ledger), 25)
    }
    func testHeatmapUsesPlannedOnlyAndMarksExtras() throws {
        let q = quest(); var ledger = try plannedLedger(q, through: q.startDay)
        var one = quest(.once); one.id = "extra"
        let extra = p.occurrence(one, on: one.startDay)
        ledger = try ledger.merged(with: [op(extra, kind: .occurrence, id: extra.id, clock: 5), op(Completion(occurrence: extra), kind: .completion, id: extra.id, clock: 6)])
        var summary = Progression.day(q.startDay, ledger: ledger, today: q.startDay)
        XCTAssertEqual(summary.planned, 1); XCTAssertEqual(summary.completed, 0); XCTAssertEqual(summary.extras, 1); XCTAssertEqual(summary.intensity, 0)
        ledger = try complete(ledger, ids: ledger.occurrences.filter(\.planned).map(\.id))
        summary = Progression.day(q.startDay, ledger: ledger, today: q.startDay)
        XCTAssertEqual(summary.intensity, 1); XCTAssertEqual(summary.ratio, 1)
    }
    func testCalendarLightChangesWithEachCompletionAndUndo() {
        var day = DaySummary(day: "2026-11-22", planned: 12, completed: 0, extras: 2,
                             xp: 0, brainSessions: 0, isFuture: false)
        for count in Array(0...12) + Array((0..<12).reversed()) {
            day.completed = count
            XCTAssertEqual(day.intensity, Double(count) / 12, accuracy: 0.000001)
        }
        day.completed = 12
        day.isFuture = true
        XCTAssertEqual(day.intensity, 0)
    }
    func testActivityWithoutPlanHasNoPercentage() throws {
        let ledger = try plannedLedger(quest(.once), through: "2026-03-06")
        let completed = try complete(ledger, ids: ledger.occurrences.map(\.id))
        let day = Progression.day("2026-03-06", ledger: completed, today: "2026-03-06")
        XCTAssertNil(day.ratio); XCTAssertEqual(day.extras, 1); XCTAssertEqual(day.intensity, 0)
    }
    func testStreakSkipsRestAndDoesNotBreakForUnfinishedToday() throws {
        var ledger = try plannedLedger(quest(.weekdays), through: "2026-03-09")
        ledger = try complete(ledger, ids: ledger.occurrences.filter { $0.day == "2026-03-06" }.map(\.id))
        XCTAssertEqual(Progression.streak(ledger: ledger, now: p.date("2026-03-09")), 1)
        XCTAssertEqual(Progression.streak(ledger: ledger, now: p.date("2026-03-10")), 0)
    }
    func testXPThresholdsAndRanks() {
        XCTAssertEqual(Progression.player(xp: 0).level, 1)
        XCTAssertEqual(Progression.player(xp: 99).intoLevel, 99)
        XCTAssertEqual(Progression.player(xp: 100).level, 2)
        XCTAssertEqual(Progression.player(xp: 225).level, 3)
        for (level, rank) in [(1,"E"),(10,"D"),(20,"C"),(35,"B"),(50,"A"),(75,"S")] {
            let xp = (1..<level).reduce(0) { $0 + Progression.required(level: $1) }
            XCTAssertEqual(Progression.player(xp: xp).rank, rank)
        }
    }
    func testIndependentFieldEditsSurviveAndOrderDoesNotMatter() throws {
        let q = quest(); let create = try op(q, kind: .quest, id: q.id)
        let name = Change(actor: "A", clock: 2, kind: .quest, entityID: q.id, fields: ["title":"\"Read\""])
        let notes = Change(actor: "B", clock: 2, kind: .quest, entityID: q.id, fields: ["notes":"\"Twenty pages\""])
        let a = Ledger(changes: [create,name,notes]), b = Ledger(changes: [notes,create,name])
        XCTAssertEqual(a.quests, b.quests); XCTAssertEqual(a.quests.first?.title, "Read"); XCTAssertEqual(a.quests.first?.notes, "Twenty pages")
    }
    func testConcurrentCompletionUndoTiePrefersUndoAndLaterRecompleteWins() throws {
        let o = p.occurrence(quest(), on: "2026-03-06")
        let done = try op(Completion(occurrence: o), kind: .completion, id: o.id, clock: 5, actor: "Z")
        let undo = try op(Completion(occurrence: o, active: false), kind: .completion, id: o.id, clock: 5, actor: "A")
        XCTAssertEqual(Ledger(changes: [done,undo]).completion(o.id)?.active, false)
        let restore = try op(Completion(occurrence: o), kind: .completion, id: o.id, clock: 6)
        XCTAssertEqual(Ledger(changes: [restore,done,undo]).completion(o.id)?.active, true)
    }
    func testStickyDeletionDefeatsStaleAndLaterEdits() throws {
        let q = quest(), create = try op(quest(), kind: .quest, id: "quest-1")
        let deletion = Change(actor: "A", clock: 3, kind: .quest, entityID: q.id, fields: [:], deleted: true)
        let stale = try op(q, kind: .quest, id: q.id, clock: 100, actor: "B")
        XCTAssertTrue(Ledger(changes: [create,deletion,stale]).quests.isEmpty)
    }
    func testGenerationResetPreventsUnseenStaleRecordsResurrecting() throws {
        let reset = Change(actor: "A", clock: 5, kind: .reset, entityID: "new-generation", fields: [:])
        var q = quest(); q.id = "previously-unseen"
        let old = try op(q, kind: .quest, id: q.id, clock: 900, actor: "offline")
        let ledger = Ledger(changes: [reset,old]); XCTAssertTrue(ledger.quests.isEmpty)
        let new = try op(q, kind: .quest, id: q.id, clock: 901, generation: "new-generation")
        XCTAssertEqual(try ledger.merged(with: [new]).quests.count, 1)
    }
    func testMergeIsAssociativeCommutativeAndIdempotent() throws {
        let q = quest(); let operations = try (1...30).map { n in try op(q, kind: .quest, id: q.id, clock: Int64(n % 7 + 1), actor: "\(n)") }
        let expected = Ledger(changes: operations)
        for _ in 0..<20 {
            let shuffled = operations.shuffled()
            let combined = try Ledger(changes: Array(shuffled.prefix(10))).merged(with: Array(shuffled.dropFirst(10))).merged(with: shuffled)
            XCTAssertEqual(combined.changes, expected.changes); XCTAssertEqual(combined.quests, expected.quests)
        }
    }
    func testTwoDifferentOfflineCompletionsSurvive() throws {
        var ledger = try plannedLedger(quest(), through: "2026-03-07")
        let a = try op(Completion(occurrence: ledger.occurrences[0]), kind: .completion, id: ledger.occurrences[0].id, clock: 10, actor: "A")
        let b = try op(Completion(occurrence: ledger.occurrences[1]), kind: .completion, id: ledger.occurrences[1].id, clock: 10, actor: "B")
        ledger = try ledger.merged(with: [a,b]); XCTAssertEqual(Progression.totalXP(ledger), 50)
    }
    func testArchiveRoundTripAndDuplicateImport() throws {
        var ledger = try plannedLedger(quest(), through: "2026-03-09")
        ledger = try complete(ledger, ids: ledger.occurrences.map(\.id))
        let data = try Archive(changes: ledger.changes).encoded()
        let imported = try Archive.decode(data, mergingInto: ledger)
        let merged = try ledger.merged(with: imported.changes)
        XCTAssertEqual(merged.changes, ledger.changes); XCTAssertEqual(Progression.totalXP(merged), 100)
    }
    func testImportRejectsMalformedVersionRelationshipsAndCollisions() throws {
        XCTAssertThrowsError(try Archive.decode(Data("{}".utf8)))
        var archive = Archive(changes: []); archive.version = 999
        XCTAssertThrowsError(try Archive.decode(archive.encoded()))
        let o = p.occurrence(quest(), on: "2026-03-06")
        let completion = try op(Completion(occurrence: o), kind: .completion, id: o.id)
        XCTAssertThrowsError(try Archive.decode(Archive(changes: [completion]).encoded()))
        var other = completion; other.fields["active"] = "false"
        XCTAssertThrowsError(try Ledger(changes: [completion]).merged(with: [other]))
    }
    func testOptionalFieldClearIsAnExplicitNullPatch() throws {
        var old = quest(); old.reminderMinutes = 600
        var new = old; new.reminderMinutes = nil
        XCTAssertEqual(try Codec.patch(new, from: old)["reminderMinutes"], "null")
    }
    func question(kind: QuestionKind = .numerical) -> Question {
        Question(id: "q1", kind: kind, prompt: "2 + 2?", options: [], answer: "4", tolerance: 0.01, hints: ["Add two pairs"], explanation: "Two pairs make four.", topic: "Arithmetic")
    }
    func testDeterministicGradingAndUncertainTypes() {
        XCTAssertEqual(LearningRules.deterministic(question(), answer: "4.005"), true)
        XCTAssertEqual(LearningRules.deterministic(question(), answer: "4.1"), false)
        XCTAssertEqual(LearningRules.deterministic(question(), answer: "nan"), false)
        XCTAssertNil(LearningRules.deterministic(question(kind: .proof), answer: "proof"))
    }
    func testMalformedQuestionsAreRejected() throws {
        XCTAssertThrowsError(try LearningRules.validate([question(),question()], count: 2))
        var q = question(); q.answer = "not numeric"
        XCTAssertThrowsError(try LearningRules.validate([q], count: 1))
        q = question(kind: .multipleChoice); q.options = ["1","2"]
        XCTAssertThrowsError(try LearningRules.validate([q], count: 1))
        q = question(); q.hints = []
        XCTAssertThrowsError(try LearningRules.validate([q], count: 1))
    }
    func testAttemptReopeningDoesNotDuplicateXPAndPracticeIsSeparate() throws {
        let session = LearningSession(config: LearningConfig(), questions: [question()], day: "2026-03-06", provider: "offline-cache", model: "test")
        var attempt = Attempt(session: session, question: question(), day: "2026-03-06"); attempt.submitted = true; attempt.correct = false
        let a = try op(attempt, kind: .attempt, id: attempt.id)
        let b = try op(attempt, kind: .attempt, id: attempt.id, clock: 2)
        XCTAssertEqual(Progression.totalXP(Ledger(changes: [a,b,a])), 5)
        attempt.mode = .assessment; XCTAssertEqual(LearningRules.xp(attempt), 0)
        attempt.correct = true; XCTAssertEqual(LearningRules.xp(attempt), 10)
        attempt.hintsUsed = 1; XCTAssertEqual(LearningRules.xp(attempt), 5)
    }
    func testStaleDraftCannotUnsubmitAnswerAndHintsNeverDecrease() throws {
        let session = LearningSession(config: LearningConfig(), questions: [question()], day: "2026-03-06", provider: "fixture", model: "fixture")
        var submitted = Attempt(session: session, question: question(), day: "2026-03-06"); submitted.answer = "4"; submitted.submitted = true; submitted.correct = true; submitted.hintsUsed = 2
        var stale = submitted; stale.submitted = false; stale.answer = "3"; stale.hintsUsed = 0; stale.correct = nil
        let ledger = Ledger(changes: [try op(submitted, kind: .attempt, id: submitted.id, clock: 2), try op(stale, kind: .attempt, id: stale.id, clock: 99)])
        XCTAssertTrue(ledger.attempts[0].submitted); XCTAssertEqual(ledger.attempts[0].answer, "4"); XCTAssertEqual(ledger.attempts[0].hintsUsed, 2)
    }
    func testWeightedMilestonesAndManualQuantityAreIndependentOfXP() throws {
        var g = Goal(); g.kind = .milestones; g.milestones = [Milestone(title: "Research", weight: 1), Milestone(title: "Ship", weight: 3)]
        let check = MilestoneCheck(id: g.milestones[1].id, goalID: g.id, done: true)
        let ledger = Ledger(changes: [try op(check, kind: .milestone, id: check.id)])
        XCTAssertEqual(Progression.goalRatio(g, ledger: ledger), 0.75); XCTAssertEqual(Progression.totalXP(ledger), 0)
    }
}
