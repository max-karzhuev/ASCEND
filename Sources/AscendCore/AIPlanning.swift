import Foundation

/// Provider-independent planning contract. Activity and credentials are never writable by AI.
struct AIPlan: Codable, Equatable {
    var summary: String
    var categories: [Category]
    var goals: [Goal]
    var quests: [Quest]
    var workouts: [WorkoutPlan]
    var quitting: [QuitHabit]
    var preferences: AIPlanPreferences

    var changeCount: Int {
        categories.count + goals.count + quests.count + workouts.count + quitting.count + preferences.changeCount
    }
    func transaction(ledger: Ledger, actor: String, day: String, planning: Planning, proposalID: String) throws -> PlanChanges {
        guard !summary.isEmpty, summary.count <= 4000,
              categories.count <= 10, goals.count <= 12, quests.count <= 30, workouts.count <= 14, quitting.count <= 10 else {
            throw DataError.invalid("The AI plan is too large or incomplete. Ask for a smaller plan.")
        }
        try preferences.validate()
        var batch = PlanChanges(ledger: ledger, actor: actor, day: day, planning: planning)
        var seen = Set<String>()
        func resolved(_ id: String, kind: EntityKind) throws -> String {
            guard !id.isEmpty, id.count <= 200, !id.contains("|"), seen.insert("\(kind.rawValue)|\(id)").inserted else {
                throw DataError.invalid("The AI returned an invalid or repeated identifier.")
            }
            if id.hasPrefix("new:"), id.count > 100 { throw DataError.invalid("New AI identifiers must be short.") }
            if id.hasPrefix("new:") { return "ai-\(proposalID)-\(kind.rawValue)-\(id.dropFirst(4))" }
            guard ledger.fields(kind, id) != nil, !ledger.isDeleted(kind, id) else { throw DataError.invalid("The AI tried to update a missing record. Generate a new plan.") }
            return id
        }
        var categoryIDs: [String: String] = [:], goalIDs: [String: String] = [:]
        for var category in categories {
            let source = category.id; category.id = try resolved(source, kind: .category)
            guard !category.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, category.name.count <= 100 else { throw DataError.invalid("Invalid category in AI plan.") }
            categoryIDs[source] = category.id
            try batch.put(category, kind: .category, id: category.id)
        }
        for var goal in goals {
            let source = goal.id; goal.id = try resolved(source, kind: .goal); goalIDs[source] = goal.id
            goal.category = categoryIDs[goal.category] ?? goal.category
            guard !goal.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, goal.title.count <= 200, goal.notes.count <= 10000,
                  goal.unit.count <= 100, goal.targetDay.isEmpty || Planning.validDay(goal.targetDay), goal.milestones.count <= 20 else { throw DataError.invalid("Invalid goal in AI plan.") }
            let old = ledger.value(Goal.self, kind: .goal, id: goal.id)
            for i in goal.milestones.indices {
                let milestone = goal.milestones[i]
                guard !milestone.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, milestone.title.count <= 200 else { throw DataError.invalid("Invalid milestone in AI plan.") }
                if milestone.id.hasPrefix("new:") { goal.milestones[i].id = "ai-\(proposalID)-milestone-\(goal.id)-\(i)" }
                else if old?.milestones.contains(where: { $0.id == milestone.id }) != true { throw DataError.invalid("Unknown milestone in AI plan.") }
            }
            try batch.put(goal, kind: .goal, id: goal.id)
        }
        for var quest in quests {
            let source = quest.id; quest.id = try resolved(source, kind: .quest)
            let old = ledger.value(Quest.self, kind: .quest, id: quest.id)
            quest.category = categoryIDs[quest.category] ?? quest.category
            quest.goalID = goalIDs[quest.goalID] ?? quest.goalID
            if old == nil, quest.startDay < day { throw DataError.invalid("New AI quests must start today or later.") }
            try Archive.validateQuest(quest)
            try batch.put(quest, kind: .quest, id: quest.id)
            let effective = old == nil ? quest.startDay : quest.schedule == .weekly ? planning.adding(7, to: planning.week(day)) : planning.adding(1, to: day)
            let revision = QuestRevision(quest: quest, effectiveDay: effective)
            try batch.put(revision, kind: .revision, id: revision.id)
            if old?.schedule == .once, quest.schedule == .once, let occurrence = ledger.occurrences.first(where: { $0.templateID == quest.id }) {
                var override = quest; override.id = "override|\(occurrence.id)"
                try batch.put(override, kind: .quest, id: override.id)
            }
        }
        for var workout in workouts {
            workout.id = try resolved(workout.id, kind: .workoutPlan)
            let old = ledger.value(WorkoutPlan.self, kind: .workoutPlan, id: workout.id)
            for i in workout.exercises.indices {
                if workout.exercises[i].id.hasPrefix("new:") { workout.exercises[i].id = "ai-\(proposalID)-exercise-\(workout.id)-\(i)" }
                else if old?.exercises.contains(where: { $0.id == workout.exercises[i].id }) != true { throw DataError.invalid("Unknown exercise in AI plan.") }
            }
            try batch.workout(workout)
        }
        for var habit in quitting {
            habit.id = try resolved(habit.id, kind: .quitHabit)
            try habit.validate()
            try batch.put(habit, kind: .quitHabit, id: habit.id)
        }
        if preferences.theme != nil || preferences.subjects != nil {
            var profile = ledger.profile
            if let theme = preferences.theme { profile.theme = theme }
            if let subjects = preferences.subjects { profile.subjects = subjects }
            try batch.put(profile, kind: .profile, id: "shared")
        }
        if let targets = preferences.muscleTargets {
            var gym = ledger.value(GymSettings.self, kind: .gymSettings, id: "shared") ?? GymSettings()
            for target in targets { gym.targets[target.muscle] = target.sessions }
            try batch.put(gym, kind: .gymSettings, id: "shared")
        }
        try Archive.validate(batch.ledger)
        return batch
    }
}
struct AIPlanPreferences: Codable, Equatable {
    struct MuscleTarget: Codable, Equatable { var muscle: MuscleGroup; var sessions: Int }
    var theme: Theme?
    var subjects: [String]?
    var widgets: [HomeWidget]?
    var muscleTargets: [MuscleTarget]?
    var mathDifficulty: Difficulty?
    var mathSeconds: Int?
    var changeCount: Int { [theme != nil, subjects != nil, widgets != nil, muscleTargets != nil, mathDifficulty != nil || mathSeconds != nil].filter { $0 }.count }
    func validate() throws {
        if let subjects {
            guard subjects.count <= 30, Set(subjects).count == subjects.count,
                  subjects.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 120 }) else { throw DataError.invalid("Invalid AI subject preferences.") }
        }
        if let widgets, Set(widgets).count != widgets.count { throw DataError.invalid("Repeated widgets in AI plan.") }
        if let targets = muscleTargets {
            guard Set(targets.map(\.muscle)).count == targets.count, targets.allSatisfy({ (1...14).contains($0.sessions) }) else { throw DataError.invalid("Invalid AI muscle targets.") }
        }
        if let seconds = mathSeconds, !MentalMathSettings.durations.contains(seconds) { throw DataError.invalid("Invalid AI drill duration.") }
    }
}
