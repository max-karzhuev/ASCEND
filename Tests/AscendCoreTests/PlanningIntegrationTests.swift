import XCTest
@testable import AscendCore

final class PlanningIntegrationTests: XCTestCase {
    let p = Planning(zone: "America/Toronto")
    let day = "2026-11-25" // Wednesday
    func workout() -> WorkoutPlan {
        var exercise = WorkoutExercise(); exercise.id = "exercise"; exercise.name = "Press"; exercise.muscles = [.chest, .triceps]
        var plan = WorkoutPlan(); plan.id = "plan"; plan.name = "Push day"; plan.weekdays = [2,4,6]; plan.exercises = [exercise]
        return plan
    }
    func batch(_ ledger: Ledger = Ledger(), day: String = "2026-11-25") -> PlanChanges {
        PlanChanges(ledger: ledger, actor: "test", day: day, planning: p)
    }
    func testWorkoutCreatesOneQuestPerScheduledDayAndProjectsUpcoming() throws {
        let plan = workout(); var b = batch(); try b.workout(plan)
        try b.snapshots(now: p.date(day)); try b.snapshots(now: p.date(day))
        XCTAssertEqual(b.ledger.occurrences.count, 1)
        XCTAssertEqual(b.ledger.occurrences.first?.quest.title, "Push day")
        XCTAssertTrue(b.ledger.occurrences.first!.quest.notes.contains("Chest"))
        XCTAssertEqual(Recurrence.projected(on: "2026-11-27", ledger: b.ledger, zone: p.zone).count, 1)
        XCTAssertTrue(Recurrence.projected(on: "2026-11-26", ledger: b.ledger, zone: p.zone).isEmpty)
        XCTAssertNoThrow(try Archive.decode(Archive(changes: b.changes).encoded()))
    }
    func testReschedulingRemovesTodaysOpenQuestAndKeepsPastSnapshots() throws {
        var plan = workout(); var b = batch(day: "2026-11-23"); try b.workout(plan)
        try b.snapshots(now: p.date(day))
        var edit = batch(b.ledger); plan.weekdays = [5]; try edit.workout(plan)
        XCTAssertTrue(edit.ledger.occurrences.contains { $0.day == "2026-11-23" })
        XCTAssertFalse(edit.ledger.occurrences.contains { $0.day == day })
        XCTAssertEqual(Recurrence.projected(on: "2026-11-26", ledger: edit.ledger, zone: p.zone).count, 1)
    }
    func testEditingTodaysWorkoutUpdatesTheOpenQuest() throws {
        var plan = workout(); var b = batch(); try b.workout(plan)
        plan.name = "Heavy push"; plan.exercises[0].name = "Incline press"
        var edit = batch(b.ledger); try edit.workout(plan)
        XCTAssertEqual(edit.ledger.occurrences.map(\.quest.title), ["Heavy push"])
        XCTAssertTrue(edit.ledger.occurrences.first?.quest.notes.contains("Incline press") == true)
        try edit.logWorkout(WorkoutLog(plan: plan, day: day, loggedAt: p.date(day)))
        XCTAssertEqual(edit.ledger.completions.map(\.title), ["Heavy push"])
        XCTAssertNoThrow(try Archive.validate(edit.ledger))
    }
    func testAddingTodayAfterRestDaySnapshotCreatesTodaysQuest() throws {
        var plan = workout(); plan.weekdays = [2]; var b = batch(day: "2026-11-23"); try b.workout(plan)
        // Normal reconciliation records an unavailable snapshot for today, a rest day.
        try b.snapshots(now: p.date(day))
        plan.weekdays = [2,4]; var edit = batch(b.ledger); try edit.workout(plan)
        XCTAssertEqual(edit.ledger.occurrences.filter { $0.day == day }.count, 1)
        try edit.logWorkout(WorkoutLog(plan: plan, day: day, loggedAt: p.date(day)))
        XCTAssertEqual(Progression.totalXP(edit.ledger), 25)
    }
    func testRemovingAndRestoringTodayBringsTheQuestBack() throws {
        var plan = workout(); var b = batch(); try b.workout(plan)
        plan.weekdays = [5]; var removed = batch(b.ledger); try removed.workout(plan)
        XCTAssertTrue(removed.ledger.occurrences.isEmpty)
        plan.weekdays = [4,5]; var restored = batch(removed.ledger); try restored.workout(plan)
        try restored.snapshots(now: p.date(day))
        XCTAssertEqual(restored.ledger.occurrences.map(\.day), [day])
        XCTAssertNoThrow(try Archive.decode(Archive(changes: restored.ledger.changes).encoded()))
    }
    func testWorkoutEditsLeaveCompletedQuestsAndOrdinarySnapshotsFrozen() throws {
        var plan = workout(); var b = batch(); try b.workout(plan)
        try b.logWorkout(WorkoutLog(plan: plan, day: day, loggedAt: p.date(day)))
        plan.name = "Renamed"; var edit = batch(b.ledger); try edit.workout(plan)
        XCTAssertEqual(edit.ledger.occurrences.map(\.quest.title), ["Push day"])
        // A later snapshot without an explicit workout edit never replaces the first one.
        var stale = edit.ledger.occurrences[0]; stale.quest.title = "Stale"; stale.revised = nil
        try edit.put(stale, kind: .occurrence, id: stale.id)
        XCTAssertEqual(edit.ledger.occurrences.map(\.quest.title), ["Push day"])
    }
    func testCompleteLogCreditsQuestOnceAndDeletionPreservesHistory() throws {
        let plan = workout(); var b = batch(); try b.workout(plan)
        let log = WorkoutLog(plan: plan, day: day, loggedAt: p.date(day))
        try b.logWorkout(log); try b.logWorkout(log)
        XCTAssertEqual(b.ledger.values(WorkoutLog.self, kind: .workoutLog).count, 1)
        XCTAssertEqual(b.ledger.completions.count, 1)
        XCTAssertEqual(Progression.totalXP(b.ledger), 25)
        try b.workout(plan, deleting: true)
        XCTAssertEqual(b.ledger.completions.count, 1)
        XCTAssertEqual(b.ledger.occurrences.count, 1)
        XCTAssertTrue(Recurrence.projected(on: "2026-11-27", ledger: b.ledger, zone: p.zone).isEmpty)
        XCTAssertNoThrow(try Archive.validate(b.ledger))
    }
    func testPartialLogDoesNotCompleteQuest() throws {
        var plan = workout(); var second = plan.exercises[0]; second.id = "second"; plan.exercises.append(second)
        var b = batch(); try b.workout(plan)
        var partial = plan; partial.exercises.removeLast()
        try b.logWorkout(WorkoutLog(plan: partial, day: day, loggedAt: p.date(day)))
        XCTAssertTrue(b.ledger.completions.isEmpty)
        XCTAssertEqual(GymProgress.sessions(.chest, logs: b.ledger.values(WorkoutLog.self, kind: .workoutLog), today: day, planning: p), 1)
    }
    func testOnDemandWorkoutDoesNotCreateDailyQuest() throws {
        var plan = workout(); plan.weekdays = []; var b = batch(); try b.workout(plan)
        try b.logWorkout(WorkoutLog(plan: plan, day: day, loggedAt: p.date(day)))
        XCTAssertTrue(b.ledger.occurrences.isEmpty); XCTAssertTrue(b.ledger.completions.isEmpty)
    }
    func aiPlan() -> AIPlan {
        var goal = Goal(); goal.id = "new:strength"; goal.title = "Build a rhythm"
        var quest = Quest(); quest.id = "new:read"; quest.title = "Read"; quest.startDay = day; quest.goalID = goal.id
        var plan = workout(); plan.id = "new:push"; plan.exercises[0].id = "new:press"
        return AIPlan(summary: "A balanced week", categories: [], goals: [goal], quests: [quest], workouts: [plan], quitting: [], preferences: AIPlanPreferences())
    }
    func testAIPlanResolvesNewGoalLinksAndSchedulesWorkoutsAtomically() throws {
        let plan = aiPlan()
        var b = try plan.transaction(ledger: Ledger(), actor: "test", day: day, planning: p, proposalID: "fixture")
        try b.snapshots(now: p.date(day))
        XCTAssertEqual(b.ledger.goals.count, 1); XCTAssertEqual(b.ledger.occurrences.count, 2)
        XCTAssertEqual(b.ledger.quests.first { $0.title == "Read" }?.goalID, b.ledger.goals.first?.id)
        XCTAssertNoThrow(try Archive.decode(Archive(changes: b.changes).encoded()))
    }
    func testInvalidAIPlanCannotCommitMissingReferencesOrUnspecifiedMuscles() {
        var plan = aiPlan(); plan.quests[0].goalID = "missing"
        XCTAssertThrowsError(try plan.transaction(ledger: Ledger(), actor: "test", day: day, planning: p, proposalID: "fixture"))
        plan = aiPlan(); plan.workouts[0].exercises[0].muscles = []
        XCTAssertThrowsError(try plan.transaction(ledger: Ledger(), actor: "test", day: day, planning: p, proposalID: "fixture"))
        plan = aiPlan(); plan.quests[0].id = "unknown-record"
        XCTAssertThrowsError(try plan.transaction(ledger: Ledger(), actor: "test", day: day, planning: p, proposalID: "fixture"))
        plan = aiPlan(); plan.quests.append(plan.quests[0])
        XCTAssertThrowsError(try plan.transaction(ledger: Ledger(), actor: "test", day: day, planning: p, proposalID: "fixture"))
    }
    func testGatewayShapedPlanDecodesAndApplies() throws {
        // Mirrors the wire shape of Gateway/planning.mjs, including explicit nulls.
        let json = """
        {"summary":"Week","categories":[{"id":"new:health","name":"Health","archived":false}],
        "goals":[{"id":"new:g","title":"Run","notes":"","category":"new:health","kind":"milestones","target":1,"unit":"","targetDay":"","milestones":[{"id":"new:m","title":"5 km","weight":1}],"archived":false}],
        "quests":[{"id":"new:q","title":"Jog","notes":"","category":"new:health","difficulty":"easy","schedule":"daily","weekdays":[],"weeklyTarget":1,"startDay":"2026-11-25","deadline":"","reminderMinutes":null,"goalID":"new:g","contribution":0,"archived":false}],
        "workouts":[{"id":"new:w","name":"Push","exercises":[{"id":"new:e","name":"Press","muscles":["chest","upperBack"],"sets":3,"prescription":"8 reps"}],"weekdays":[4]}],
        "quitting":[{"id":"new:h","name":"Smoking","startedDay":"2026-11-25","checkInHour":20,"archived":false}],
        "preferences":{"theme":"baby blue","subjects":null,"widgets":["gym","quests"],"muscleTargets":[{"muscle":"chest","sessions":2}],"mathDifficulty":"hard","mathSeconds":null}}
        """
        let plan = try JSONDecoder().decode(AIPlan.self, from: Data(json.utf8))
        let b = try plan.transaction(ledger: Ledger(), actor: "test", day: day, planning: p, proposalID: "wire")
        XCTAssertEqual(b.ledger.quests.count, 2); XCTAssertEqual(b.ledger.profile.theme, .babyBlue)
        XCTAssertNoThrow(try Archive.decode(Archive(changes: b.changes).encoded()))
    }
    func testNewPaletteRetainsEveryExistingValue() throws {
        for raw in ["shadow","amber","emerald","crimson","blue","baby blue","pink","lilac","peach","teal"] {
            XCTAssertNotNil(Theme(rawValue: raw))
        }
        XCTAssertEqual(Theme.allCases.count, 20)
        for theme in Theme.allCases { XCTAssertEqual(try JSONDecoder().decode(Theme.self, from: JSONEncoder().encode(theme)), theme) }
    }
    func testRemovingAutoCompletedLogReversesRewardButRetainsOtherFullLogs() throws {
        let plan = workout(); var b = batch(); try b.workout(plan)
        let first = WorkoutLog(plan: plan, day: day, loggedAt: p.date(day))
        let second = WorkoutLog(plan: plan, day: day, loggedAt: p.date(day))
        try b.logWorkout(first); try b.logWorkout(second)
        XCTAssertEqual(Progression.totalXP(b.ledger), 25)
        try b.removeWorkoutLog(first)
        XCTAssertEqual(Progression.totalXP(b.ledger), 25)
        try b.removeWorkoutLog(second)
        XCTAssertEqual(Progression.totalXP(b.ledger), 0)
        XCTAssertTrue(b.ledger.values(WorkoutLog.self, kind: .workoutLog).isEmpty)
        XCTAssertNoThrow(try Archive.validate(b.ledger))
    }

}
