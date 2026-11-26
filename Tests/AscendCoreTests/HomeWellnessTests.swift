import XCTest
@testable import AscendCore

final class HomeWellnessTests: XCTestCase {
    let p = Planning(zone: "America/Toronto")
    func status(_ days: Set<String>, _ today: String) -> StreakStatus { StreakRules.status(days: days, today: today, planning: p) }
    func op<T: Encodable>(_ value: T, _ kind: EntityKind, _ id: String, clock: Int64 = 1) throws -> Change {
        Change(actor: "test", clock: clock, kind: kind, entityID: id, fields: try Codec.fields(value))
    }
    func plan() -> WorkoutPlan {
        var p = WorkoutPlan(); p.name = "Upper body"; p.weekdays = [2,4,6]
        var e = WorkoutExercise(); e.name = "Press"; e.muscles = [.chest, .triceps]
        var second = WorkoutExercise(); second.name = "Push-up"; second.muscles = [.chest, .shoulders]
        p.exercises = [e, second]; return p
    }
    func testTwoMissedDaysFreezeAndRecoveryDoesNotAwardMissedDays() {
        let days: Set<String> = ["2026-11-22", "2026-11-23"]
        XCTAssertEqual(status(days, "2026-11-24").count, 2)
        XCTAssertFalse(status(days, "2026-11-24").frozen)
        XCTAssertTrue(status(days, "2026-11-25").frozen)
        XCTAssertEqual(status(days, "2026-11-26").recoverBy, "2026-11-26")
        XCTAssertEqual(status(days, "2026-11-26").count, 2)
        let recovered = status(days.union(["2026-11-26"]), "2026-11-26")
        XCTAssertEqual(recovered.count, 3)
        XCTAssertTrue(recovered.completedToday)
        XCTAssertFalse(recovered.frozen)
    }
    func testExpiredFreezeAndLateReturnStartANewStreak() {
        XCTAssertTrue(status(["2026-11-23"], "2026-11-27").expired)
        XCTAssertEqual(status(["2026-11-23"], "2026-11-27").count, 0)
        XCTAssertEqual(status(["2026-11-22", "2026-11-23", "2026-11-27"], "2026-11-27").count, 1)
        XCTAssertEqual(status(["2026-11-22", "2026-11-23", "2026-11-27", "2026-11-28"], "2026-11-28").count, 2)
    }
    func testFreezeUsesCalendarDaysAcrossDSTAndYearBoundary() {
        XCTAssertEqual(status(["2026-10-31"], "2026-11-03").count, 1)
        XCTAssertEqual(status(["2026-10-31"], "2026-11-04").count, 0)
        XCTAssertEqual(status(["2026-12-30", "2027-01-02"], "2027-01-02").count, 2)
        XCTAssertEqual(status(["2026-03-07"], "2026-03-10").count, 1)
    }
    func testDuplicateAndFutureCreditDoesNotInflateStreak() {
        XCTAssertEqual(status(["2026-11-25", "2026-11-25", "2026-11-26"], "2026-11-25").count, 1)
        XCTAssertEqual(status([], "2026-11-25").count, 0)
        XCTAssertEqual(status(["invalid"], "2026-11-25").count, 0)
    }
    func testQuitCheckInGateAndSetbackReset() {
        var habit = QuitHabit(name: "Smoking", startedDay: "2026-11-20")
        let formatter = ISO8601DateFormatter()
        XCTAssertFalse(habit.canCheckIn(now: formatter.date(from: "2026-11-26T00:59:59Z")!, planning: p)) // 7:59 PM Toronto
        XCTAssertTrue(habit.canCheckIn(now: formatter.date(from: "2026-11-26T01:00:00Z")!, planning: p))
        let entries = [
            QuitCheckIn(habitID: habit.id, day: "2026-11-22", stayedFree: true, loggedAt: p.date("2026-11-22")),
            QuitCheckIn(habitID: habit.id, day: "2026-11-23", stayedFree: false, loggedAt: p.date("2026-11-23")),
            QuitCheckIn(habitID: habit.id, day: "2026-11-24", stayedFree: true, loggedAt: p.date("2026-11-24"))
        ]
        XCTAssertEqual(Quitting.status(habit: habit, checkIns: entries, today: "2026-11-24", planning: p).count, 1)
        habit.archived = true
        XCTAssertFalse(habit.canCheckIn(now: formatter.date(from: "2026-11-26T01:00:00Z")!, planning: p))
    }
    func testIndependentQuittingStreaksAndMissedCheckIns() {
        let habit = QuitHabit(name: "Custom", startedDay: "2026-11-20")
        let entries = [
            QuitCheckIn(habitID: habit.id, day: "2026-11-22", stayedFree: true, loggedAt: p.date("2026-11-22")),
            QuitCheckIn(habitID: "other", day: "2026-11-23", stayedFree: false, loggedAt: p.date("2026-11-23")),
            QuitCheckIn(habitID: habit.id, day: "2026-11-25", stayedFree: true, loggedAt: p.date("2026-11-25"))
        ]
        XCTAssertEqual(Quitting.status(habit: habit, checkIns: entries, today: "2026-11-25", planning: p).count, 2)
        XCTAssertTrue(Quitting.status(habit: habit, checkIns: entries, today: "2026-11-24", planning: p).frozen)
    }
    func testWorkoutRequiresMusclesOnEveryExerciseAndValidSchedule() {
        var workout = plan(); XCTAssertNoThrow(try workout.validate())
        workout.exercises[1].muscles = []; XCTAssertThrowsError(try workout.validate())
        workout = plan(); workout.weekdays = [0]; XCTAssertThrowsError(try workout.validate())
        workout = plan(); workout.exercises = []; XCTAssertThrowsError(try workout.validate())
        workout = plan(); workout.exercises[0].sets = 0; XCTAssertThrowsError(try workout.validate())
        XCTAssertEqual(Set(MuscleGroup.allCases).count, 14)
    }
    func testScheduleAndWeeklyMuscleProgressUseOnlyActualLogs() {
        let workout = plan()
        XCTAssertTrue(workout.scheduled(on: "2026-11-25", planning: p))
        XCTAssertFalse(workout.scheduled(on: "2026-11-26", planning: p))
        let logs = ["2026-11-22", "2026-11-23", "2026-11-25", "2026-11-26"].map { WorkoutLog(plan: workout, day: $0, loggedAt: p.date($0)) }
        XCTAssertEqual(GymProgress.sessions(.chest, logs: logs, today: "2026-11-25", planning: p), 2) // Two chest exercises still count once.
        XCTAssertEqual(GymProgress.sessions(.quads, logs: logs, today: "2026-11-25", planning: p), 0)
        XCTAssertEqual(GymProgress.sessions(.chest, logs: logs, today: "2026-11-30", planning: p), 0)
        var partial = workout; partial.exercises.removeFirst()
        XCTAssertFalse(WorkoutLog(plan: partial, day: "2026-11-25", loggedAt: p.date("2026-11-25")).muscles.contains(.triceps))
    }
    func testWellnessArchiveRoundTripReplayAndDeletion() throws {
        let habit = QuitHabit(name: "Weed", startedDay: "2026-11-25"), workout = plan()
        let check = QuitCheckIn(habitID: habit.id, day: "2026-11-25", stayedFree: true, loggedAt: p.date("2026-11-25"))
        let log = WorkoutLog(plan: workout, day: "2026-11-25", loggedAt: p.date("2026-11-25"))
        let changes = try [op(habit, .quitHabit, habit.id), op(check, .quitCheckIn, check.id), op(workout, .workoutPlan, workout.id), op(log, .workoutLog, log.id), op(GymSettings(), .gymSettings, "shared")]
        let archive = try Archive.decode(Archive(changes: changes).encoded())
        let ledger = try Ledger(changes: archive.changes).merged(with: changes)
        XCTAssertEqual(ledger.values(QuitCheckIn.self, kind: .quitCheckIn).count, 1)
        XCTAssertEqual(ledger.values(WorkoutLog.self, kind: .workoutLog).count, 1)
        let deletedPlan = try ledger.merged(with: [Change(actor: "test", clock: 5, kind: .workoutPlan, entityID: workout.id, fields: [:], deleted: true)])
        XCTAssertTrue(deletedPlan.values(WorkoutPlan.self, kind: .workoutPlan).isEmpty)
        XCTAssertEqual(deletedPlan.values(WorkoutLog.self, kind: .workoutLog).first?.name, workout.name)
        XCTAssertNoThrow(try Archive.validate(deletedPlan))
        let deletedLog = try ledger.merged(with: [Change(actor: "test", clock: 6, kind: .workoutLog, entityID: log.id, fields: [:], deleted: true)])
        XCTAssertTrue(deletedLog.values(WorkoutLog.self, kind: .workoutLog).isEmpty)
    }
    func testCheckInCorrectionIsAtomicAndDoesNotDoubleCount() throws {
        let habit = QuitHabit(name: "Alcohol", startedDay: "2026-11-25")
        var check = QuitCheckIn(habitID: habit.id, day: "2026-11-25", stayedFree: true, loggedAt: p.date("2026-11-25"))
        let first = try op(check, .quitCheckIn, check.id)
        check.stayedFree = false
        let latest = try op(check, .quitCheckIn, check.id, clock: 2)
        let ledger = Ledger(changes: [try op(habit, .quitHabit, habit.id), latest, first])
        XCTAssertEqual(ledger.values(QuitCheckIn.self, kind: .quitCheckIn).count, 1)
        XCTAssertEqual(ledger.values(QuitCheckIn.self, kind: .quitCheckIn).first?.stayedFree, false)
    }
    func testInvalidImportsAreRejected() throws {
        var workout = plan(); workout.exercises[0].muscles = []
        XCTAssertThrowsError(try Archive.decode(Archive(changes: [op(workout, .workoutPlan, workout.id)]).encoded()))
        let orphan = QuitCheckIn(habitID: "missing", day: "2026-11-25", stayedFree: true, loggedAt: Date())
        XCTAssertThrowsError(try Archive.decode(Archive(changes: [op(orphan, .quitCheckIn, orphan.id)]).encoded()))
        var settings = GymSettings(); settings.targets[.chest] = -1
        XCTAssertThrowsError(try settings.validate())
    }
    func testHomeLayoutPersistsOrderHiddenCardsAndWidth() throws {
        var layout = HomeLayout(); layout.hidden = [.calendar, .player]; layout.wide = [.gym]
        layout.move(.gym, by: -1)
        let saved = try JSONDecoder().decode(HomeLayout.self, from: JSONEncoder().encode(layout))
        XCTAssertEqual(saved, layout)
        XCTAssertFalse(saved.visible.contains(.calendar))
        XCTAssertEqual(saved.rows(twoColumns: true).flatMap { $0 }, saved.visible)
        XCTAssertTrue(saved.rows(twoColumns: true).contains([.gym]))
        XCTAssertTrue(saved.rows(twoColumns: false).allSatisfy { $0.count == 1 })
        layout.hidden = Set(HomeWidget.allCases); XCTAssertTrue(layout.visible.isEmpty)
        layout.order = [.gym, .gym]; XCTAssertEqual(layout.normalized.order.count, HomeWidget.allCases.count)
    }
    func testOverlappingSleepIsUnionedAndClippedToWindow() {
        let zero = Date(timeIntervalSince1970: 0)
        func range(_ start: Double, _ end: Double) -> DateInterval { DateInterval(start: zero.addingTimeInterval(start), end: zero.addingTimeInterval(end)) }
        XCTAssertEqual(HealthIntervals.duration([range(0, 60), range(30, 90), range(35, 50), range(100, 120)], within: range(10, 110)), 90)
        XCTAssertEqual(HealthIntervals.duration([], within: range(0, 10)), 0)
    }
}
