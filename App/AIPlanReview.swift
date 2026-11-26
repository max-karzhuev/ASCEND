import SwiftUI

struct AIPlanProposal: Identifiable {
    var id: String
    var plan: AIPlan
    var baseline: Data
    var generation: String
    var applied = false
}
struct AIPlanReview: View {
    let proposal: AIPlanProposal
    @Environment(AppStore.self) private var store
    @Environment(AIClient.self) private var ai
    @Environment(\.dismiss) private var dismiss
    @State private var applied = false
    @State private var error: String?
    var plan: AIPlan { proposal.plan }
    var body: some View {
        PageScroll {
            Text(plan.summary).font(.headline).textSelection(.enabled)
            Text("New items are added; existing items below are updated. Routine edits begin tomorrow (weekly targets next Monday). Workouts update today’s open quest and future days.").font(.caption).foregroundStyle(Palette.muted)
            ForEach(plan.categories) { category in
                Card { heading(category.name, id: category.id, kind: "Category", archived: category.archived) }
            }
            ForEach(plan.goals) { goal in
                Card {
                    heading(goal.title, id: goal.id, kind: "Goal", archived: goal.archived)
                    Text(goal.notes)
                    Text("Category: \(categoryName(goal.category)) · Target: \(goal.target.formatted()) \(goal.unit)").font(.caption)
                    if !goal.targetDay.isEmpty { Text("Target date: \(goal.targetDay)").font(.caption) }
                    ForEach(goal.milestones) { Text("\($0.title) · \($0.weight.formatted())").font(.subheadline) }
                }
            }
            ForEach(plan.quests) { quest in
                Card {
                    heading(quest.title, id: quest.id, kind: "Quest", archived: quest.archived)
                    Text(quest.notes)
                    Text("\(quest.schedule.rawValue.capitalized) · \(quest.difficulty.rawValue.capitalized) · Starts \(quest.startDay)").font(.caption)
                    if quest.schedule == .weekdays { Text(days(Set(quest.weekdays))).font(.caption) }
                    if quest.schedule == .weekly { Text("\(quest.weeklyTarget) sessions per week").font(.caption) }
                    Text("Category: \(categoryName(quest.category))").font(.caption)
                    if !quest.deadline.isEmpty { Text("Due: \(quest.deadline)").font(.caption) }
                    if let minutes = quest.reminderMinutes { Text(String(format: "Reminder: %02d:%02d", minutes / 60, minutes % 60)).font(.caption) }
                    if !quest.goalID.isEmpty { Text("Goal: \(goalTitle(quest.goalID)) · \(quest.contribution.formatted()) per completion").font(.caption) }
                }
            }
            ForEach(plan.workouts) { workout in
                Card {
                    heading(workout.name, id: workout.id, kind: "Workout")
                    Text(days(workout.weekdays)).foregroundStyle(store.profile.theme.accent)
                    ForEach(workout.exercises) { exercise in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(exercise.name) · \(exercise.sets) sets · \(exercise.prescription)")
                            Text(exercise.muscles.sorted { $0.title < $1.title }.map(\.title).joined(separator: ", ")).font(.caption).foregroundStyle(Palette.muted)
                        }
                    }
                    if !workout.weekdays.isEmpty { Text("Automatically added to quests on these days.").font(.caption) }
                }
            }
            ForEach(plan.quitting) { habit in
                Card {
                    heading(habit.name, id: habit.id, kind: "Quitting goal", archived: habit.archived)
                    Text("Starts \(habit.startedDay) · Check-in opens at \(habit.checkInHour):00").font(.caption)
                }
            }
            if plan.preferences.changeCount > 0 {
                Card {
                    Text("Preferences").font(.title3.bold())
                    if let theme = plan.preferences.theme { Label(theme.rawValue.capitalized, systemImage: "paintpalette").foregroundStyle(theme.accent) }
                    if let subjects = plan.preferences.subjects { Text("Subjects: \(subjects.isEmpty ? "None" : subjects.joined(separator: ", "))") }
                    if let widgets = plan.preferences.widgets { Text("Home widgets, in order: \(widgets.isEmpty ? "None" : widgets.map(\.title).joined(separator: ", "))") }
                    if let targets = plan.preferences.muscleTargets {
                        ForEach(targets, id: \.muscle) { Text("\($0.muscle.title): \($0.sessions) sessions per week") }
                    }
                    if let difficulty = plan.preferences.mathDifficulty { Text("Mental math: \(difficulty.rawValue.capitalized)") }
                    if let seconds = plan.preferences.mathSeconds { Text("Drill duration: \(seconds) seconds") }
                }
            }
            if let error { Text(error).foregroundStyle(.orange) }
            Button(applied || proposal.applied ? "Plan applied" : "Apply plan") {
                do {
                    try store.applyAIPlan(plan, id: proposal.id, baseline: proposal.baseline, generation: proposal.generation)
                    applied = true
                    if ai.chat.proposal?.id == proposal.id { ai.chat.proposal?.applied = true }
                } catch { self.error = error.localizedDescription }
            }.buttonStyle(AccentButton(color: store.profile.theme.accent)).disabled(applied || proposal.applied || plan.changeCount == 0)
        }.navigationTitle("Review AI plan")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.buttonStyle(TargetButton()) } }
    }
    func heading(_ title: String, id: String, kind: String, archived: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(id.hasPrefix("new:") ? "Add" : "Update") \(kind.lowercased())\(archived ? " · archived" : "")").font(.caption).foregroundStyle(Palette.muted)
            Text(title).font(.title3.bold())
        }
    }
    func days(_ values: Set<Int>) -> String {
        values.isEmpty ? "On demand" : [2,3,4,5,6,7,1].filter(values.contains).map { store.planning.calendar.weekdaySymbols[$0 - 1] }.joined(separator: ", ")
    }
    func categoryName(_ id: String) -> String {
        (plan.categories + store.categories + Category.defaults).first { $0.id == id }?.name ?? id
    }
    func goalTitle(_ id: String) -> String {
        plan.goals.first { $0.id == id }?.title ?? store.ledger.goals.first { $0.id == id }?.title ?? id
    }
}
