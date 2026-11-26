import SwiftUI

enum GymRoute: Identifiable {
    case plans, edit(WorkoutPlan?), log(WorkoutPlan), settings, history, muscles
    var id: String { switch self { case .plans: "plans"; case .edit(let p): "edit-\(p?.id ?? "new")"; case .log(let p): "log-\(p.id)"; case .settings: "settings"; case .history: "history"; case .muscles: "muscles" } }
}
struct GymCard: View {
    @Environment(AppStore.self) private var store
    @State private var selected = MuscleGroup.chest
    @State private var route: GymRoute?
    var todayPlans: [WorkoutPlan] { store.workoutPlans.filter { $0.scheduled(on: store.today, planning: store.planning) } }
    var planned: Set<MuscleGroup> { todayPlans.reduce(into: []) { $0.formUnion($1.muscles) } }
    var ratios: [MuscleGroup: Double] { Dictionary(uniqueKeysWithValues: MuscleGroup.allCases.map { ($0, Double(count($0)) / Double(store.gymSettings.target($0))) }) }
    func count(_ muscle: MuscleGroup) -> Int { GymProgress.sessions(muscle, logs: store.workoutLogs, today: store.today, planning: store.planning) }
    var body: some View {
        Card(padding: 18, spacing: 12) {
            HStack {
                Label("Gym progress", systemImage: "figure.strengthtraining.traditional").font(.title3.bold())
                Spacer()
                Button { route = .settings } label: { Image(systemName: "slider.horizontal.3") }.buttonStyle(TargetButton()).accessibilityLabel("Weekly muscle targets")
            }
            MuscleMap(planned: planned, progress: ratios, selected: $selected)
            VStack(alignment: .leading, spacing: 8) {
                Button { route = .muscles } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(selected.title).font(.headline)
                            Text(count(selected) >= store.gymSettings.target(selected) ? "Weekly target complete" : planned.contains(selected) ? "On today’s plan" : "Weekly training")
                                .font(.caption).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Text("\(count(selected)) / \(store.gymSettings.target(selected))").font(.headline.monospacedDigit()).foregroundStyle(store.profile.theme.accent)
                        Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(Palette.muted)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(TargetButton()).accessibilityLabel("Choose muscle, \(selected.title), \(count(selected)) of \(store.gymSettings.target(selected)) weekly sessions")
                Meter(value: ratios[selected] ?? 0, height: 5)
            }.padding(12).background(Palette.background, in: RoundedRectangle(cornerRadius: 12))
            if todayPlans.isEmpty {
                Text(store.workoutPlans.isEmpty ? "Build a workout to light up your training plan." : "Rest day on your plan. Your saved workouts are always available.")
                    .font(.caption).foregroundStyle(Palette.muted)
            } else {
                ForEach(Array(todayPlans.prefix(2))) { plan in
                    Button { route = .log(plan) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(plan.name).font(.subheadline.bold())
                                Text("Today · \(plan.exercises.count) exercises").font(.caption).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            Label("Log", systemImage: "plus.circle").font(.subheadline).foregroundStyle(store.profile.theme.accent)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(TargetButton()).accessibilityLabel("Log \(plan.name)")
                }
            }
            HStack(spacing: 10) {
                Button { route = .plans } label: {
                    Label(store.workoutPlans.isEmpty ? "Create workout" : "Workout plans", systemImage: "dumbbell").frame(maxWidth: .infinity)
                }.buttonStyle(AccentButton(color: store.profile.theme.accent))
                Button { route = .history } label: { Image(systemName: "clock.arrow.circlepath") }.buttonStyle(TargetButton()).accessibilityLabel("Workout history")
            }
            Text("Tap the body or choose a muscle · week resets Monday").font(.caption2).foregroundStyle(Palette.muted)
        }.sheet(item: $route) { route in
            NavigationStack {
                switch route {
                case .plans: WorkoutPlansView()
                case .edit(let plan): WorkoutEditor(original: plan)
                case .log(let plan): WorkoutLogView(plan: plan)
                case .settings: GymSettingsView()
                case .history: WorkoutHistoryView()
                case .muscles: MuscleSelector(selected: $selected, planned: planned)
                }
            }.editorFrame().preferredColorScheme(.dark)
        }
    }
}
private struct MuscleSelector: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var selected: MuscleGroup
    var planned: Set<MuscleGroup>
    var body: some View {
        PageScroll {
            Text("Choose a muscle to see its weekly progress. Each logged workout counts once per trained muscle.").font(.subheadline).foregroundStyle(Palette.muted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], spacing: 12) {
                ForEach(MuscleGroup.allCases) { muscle in
                    let count = GymProgress.sessions(muscle, logs: store.workoutLogs, today: store.today, planning: store.planning)
                    Button { selected = muscle; dismiss() } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Text(muscle.title).font(.subheadline.bold()); Spacer(); if planned.contains(muscle) { Circle().fill(store.profile.theme.accent).frame(width: 6, height: 6) } }
                            Text("\(count) / \(store.gymSettings.target(muscle)) sessions").font(.caption.monospacedDigit()).foregroundStyle(Palette.muted)
                            Meter(value: Double(count) / Double(store.gymSettings.target(muscle)), height: 4)
                        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).buttonTarget()
                            .background(selected == muscle ? store.profile.theme.deep : Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).accessibilityLabel("\(muscle.title), \(count) of \(store.gymSettings.target(muscle)) sessions\(planned.contains(muscle) ? ", planned today" : "")")
                }
            }
        }.navigationTitle("Muscle progress")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.buttonStyle(TargetButton()) } }
    }
}
struct WorkoutPlansView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var route: GymRoute?
    @State private var deleting: WorkoutPlan?
    @State private var selectedDay = 2
    @State private var creating = false
    var body: some View {
        PageScroll {
            Text("Choose a day, then add a workout with exercises and muscle groups. Scheduled workouts appear in that day’s quests automatically.").foregroundStyle(Palette.muted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 65))], spacing: 8) {
                ForEach([2,3,4,5,6,7,1], id: \.self) { day in
                    Button { selectedDay = day } label: {
                        VStack(spacing: 6) {
                            Text(store.planning.calendar.shortWeekdaySymbols[day - 1]).font(.headline)
                            Text("\(store.workoutPlans.filter { $0.weekdays.contains(day) }.count) workouts").font(.caption2)
                        }.frame(maxWidth: .infinity).padding(8).buttonTarget()
                            .background(selectedDay == day ? store.profile.theme.deep : Palette.surface, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).accessibilityAddTraits(selectedDay == day ? .isSelected : [])
                }
            }
            Text(store.planning.calendar.weekdaySymbols[selectedDay - 1]).font(.title2.bold())
            Button { creating = true } label: { Label("Add workout to this day", systemImage: "plus") }.buttonStyle(AccentButton(color: store.profile.theme.accent))
            if !store.workoutPlans.contains(where: { $0.weekdays.contains(selectedDay) }) {
                Text("Rest day · add a workout whenever you’re ready.").foregroundStyle(Palette.muted)
            }
            ForEach(store.workoutPlans.filter { $0.weekdays.contains(selectedDay) || $0.weekdays.isEmpty }) { plan in
                Card {
                    Text(plan.name).font(.title3.bold())
                    Text(scheduleTitle(plan)).font(.caption).foregroundStyle(store.profile.theme.accent)
                    ForEach(plan.exercises) { exercise in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(exercise.name).font(.subheadline.bold())
                            Text("\(exercise.sets) sets · \(exercise.prescription)").font(.caption).foregroundStyle(Palette.muted)
                            Text(exercise.muscles.sorted { $0.title < $1.title }.map(\.title).joined(separator: " · ")).font(.caption).foregroundStyle(Palette.muted)
                        }
                    }
                    Button("Log this workout") { route = .log(plan) }.buttonStyle(AccentButton(color: store.profile.theme.accent))
                    HStack {
                        Button("Edit plan") { route = .edit(plan) }.buttonStyle(TargetButton())
                        Spacer()
                        Button("Delete", role: .destructive) { deleting = plan }.buttonStyle(TargetButton())
                    }
                }
            }
        }.navigationTitle("Weekly workout plan")
            .onAppear { selectedDay = store.planning.calendar.component(.weekday, from: store.clockNow) }
            .sheet(isPresented: $creating) { NavigationStack { WorkoutEditor(original: nil, initialDay: selectedDay) }.editorFrame().preferredColorScheme(.dark) }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.buttonStyle(TargetButton()) } }
            .sheet(item: $route) { route in
                NavigationStack {
                    switch route {
                    case .edit(let plan): WorkoutEditor(original: plan)
                    case .log(let plan): WorkoutLogView(plan: plan)
                    default: EmptyView()
                    }
                }.editorFrame().preferredColorScheme(.dark)
            }
            .confirmationDialog("Delete this workout plan?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete plan", role: .destructive) { if let plan = deleting { store.perform { try store.delete(kind: .workoutPlan, id: plan.id) } }; deleting = nil }
            } message: { Text("Future workout quests will stop. Completed quests, logged workouts and muscle progress stay in your history.") }
    }
    func scheduleTitle(_ plan: WorkoutPlan) -> String {
        let weekdays = [2,3,4,5,6,7,1].filter { plan.weekdays.contains($0) }
        return weekdays.isEmpty ? "On demand" : weekdays.map { store.planning.calendar.weekdaySymbols[$0 - 1] }.joined(separator: ", ")
    }
}
struct WorkoutEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var original: WorkoutPlan?
    @State private var plan: WorkoutPlan
    @State private var validation: String?
    init(original: WorkoutPlan?, initialDay: Int? = nil) {
        self.original = original
        var draft = original ?? WorkoutPlan()
        if original == nil, let initialDay { draft.weekdays = [initialDay] }
        _plan = State(initialValue: draft)
    }
    var body: some View {
        PageScroll {
            Card {
                TextField("Workout name", text: $plan.name).textFieldStyle(.roundedBorder).frame(minHeight: 44)
                Text("Training days").font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 55))], spacing: 8) {
                    ForEach([2,3,4,5,6,7,1], id: \.self) { day in
                        Button { if !plan.weekdays.insert(day).inserted { plan.weekdays.remove(day) } } label: {
                            Text(store.planning.calendar.shortWeekdaySymbols[day - 1]).font(.caption.bold()).frame(maxWidth: .infinity).buttonTarget()
                                .background(plan.weekdays.contains(day) ? store.profile.theme.deep : Palette.background, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain).accessibilityAddTraits(plan.weekdays.contains(day) ? .isSelected : [])
                    }
                }
                Text("Each selected day gets this workout in quests automatically. Create separate workouts for different exercises on different days. Leave all days off for an on-demand workout.").font(.caption).foregroundStyle(Palette.muted)
            }
            ForEach($plan.exercises) { $exercise in
                ExerciseEditor(exercise: $exercise) {
                    plan.exercises.removeAll { $0.id == exercise.id }
                }
            }
            Button { plan.exercises.append(WorkoutExercise()) } label: { Label("Add exercise", systemImage: "plus.circle") }.buttonStyle(TargetButton()).disabled(plan.exercises.count >= 30)
            if let validation { Text(validation).foregroundStyle(.orange).font(.subheadline) }
            Button("Save workout") {
                do { try store.saveWorkoutPlan(plan); dismiss() }
                catch { validation = error.localizedDescription }
            }.buttonStyle(AccentButton(color: store.profile.theme.accent))
        }.navigationTitle(original == nil ? "Create workout" : "Edit workout")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.buttonStyle(TargetButton()) } }
    }
}
private struct ExerciseEditor: View {
    @Environment(AppStore.self) private var store
    @Binding var exercise: WorkoutExercise
    var remove: () -> Void
    var body: some View {
        Card {
            HStack { Text("Exercise").font(.headline); Spacer(); Button(action: remove) { Image(systemName: "trash") }.buttonStyle(TargetButton()).accessibilityLabel("Remove exercise") }
            TextField("Exercise name, e.g. chest press", text: $exercise.name).textFieldStyle(.roundedBorder).frame(minHeight: 44)
            Stepper("\(exercise.sets) sets", value: $exercise.sets, in: 1...30).frame(minHeight: 44)
            TextField("Reps, minutes or distance", text: $exercise.prescription).textFieldStyle(.roundedBorder).frame(minHeight: 44)
            Text("Muscles trained · select at least one").font(.subheadline.bold())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 8) {
                ForEach(MuscleGroup.allCases) { muscle in
                    Button {
                        if !exercise.muscles.insert(muscle).inserted { exercise.muscles.remove(muscle) }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: exercise.muscles.contains(muscle) ? "checkmark.circle.fill" : "circle")
                            Text(muscle.title).font(.caption.weight(.medium))
                            Spacer(minLength: 0)
                        }.padding(.horizontal, 9).frame(maxWidth: .infinity).buttonTarget()
                            .foregroundStyle(exercise.muscles.contains(muscle) ? store.profile.theme.accent : Palette.muted)
                            .background(Palette.background, in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain).accessibilityAddTraits(exercise.muscles.contains(muscle) ? .isSelected : [])
                }
            }
        }
    }
}
struct WorkoutLogView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var plan: WorkoutPlan
    @State private var exercises: [WorkoutExercise]
    @State private var included: Set<String>
    @State private var logID = UUID().uuidString
    @State private var validation: String?
    init(plan: WorkoutPlan) {
        self.plan = plan; _exercises = State(initialValue: plan.exercises); _included = State(initialValue: Set(plan.exercises.map(\.id)))
    }
    var body: some View {
        PageScroll {
            ScreenHeader(eyebrow: "Log today’s training", title: plan.name, subtitle: "Confirm the exercises you actually completed. Only those muscle groups receive progress.")
            ForEach($exercises) { $exercise in
                Card {
                    Toggle(exercise.name, isOn: Binding(get: { included.contains(exercise.id) }, set: { if $0 { included.insert(exercise.id) } else { included.remove(exercise.id) } })).frame(minHeight: 44)
                    if included.contains(exercise.id) {
                        Stepper("\(exercise.sets) completed sets", value: $exercise.sets, in: 1...30).frame(minHeight: 44)
                        TextField("Reps, minutes or distance completed", text: $exercise.prescription).textFieldStyle(.roundedBorder).frame(minHeight: 44)
                    }
                    Text(exercise.muscles.sorted { $0.title < $1.title }.map(\.title).joined(separator: " · ")).font(.caption).foregroundStyle(Palette.muted)
                }
            }
            if let validation { Text(validation).foregroundStyle(.orange) }
            Button("Save completed workout") {
                var completed = plan; completed.exercises = exercises.filter { included.contains($0.id) }
                var log = WorkoutLog(plan: completed, day: store.planning.day(Date()), loggedAt: Date()); log.id = logID
                do { try store.logWorkout(log); dismiss() } catch { validation = error.localizedDescription }
            }.buttonStyle(AccentButton(color: store.profile.theme.accent)).disabled(included.isEmpty)
            Text("Logging all exercises also completes today’s scheduled quest. Partial workouts update only muscle progress. Checking a quest alone does not create a workout log.").font(.caption).foregroundStyle(Palette.muted)
        }.navigationTitle("Log workout")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.buttonStyle(TargetButton()) } }
    }
}
struct GymSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var settings = GymSettings()
    var body: some View {
        PageScroll {
            Text("Choose the number of sessions that fills each muscle this week. Targets are personal tracking goals, not training recommendations.").foregroundStyle(Palette.muted)
            Card {
                ForEach(MuscleGroup.allCases) { muscle in
                    Stepper("\(muscle.title) · \(settings.target(muscle))", value: Binding(get: { settings.target(muscle) }, set: { settings.targets[muscle] = $0 }), in: 1...14).frame(minHeight: 44)
                }
            }
            Button("Save targets") {
                do { try store.saveGymSettings(settings); dismiss() } catch { store.error = error.localizedDescription }
            }.buttonStyle(AccentButton(color: store.profile.theme.accent))
        }.onAppear { settings = store.gymSettings }.navigationTitle("Weekly muscle targets")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.buttonStyle(TargetButton()) } }
    }
}
struct WorkoutHistoryView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var deleting: WorkoutLog?
    var body: some View {
        PageScroll {
            if store.workoutLogs.isEmpty { EmptyCard(icon: "dumbbell", title: "Your training starts here", message: "Logged workouts will appear here and fill your weekly muscle progress.") }
            ForEach(store.workoutLogs) { log in
                Card {
                    HStack { Text(log.name).font(.headline); Spacer(); Text(log.day).font(.caption.monospacedDigit()).foregroundStyle(Palette.muted) }
                    ForEach(log.exercises) { exercise in Text("\(exercise.name) · \(exercise.sets) sets · \(exercise.prescription)").font(.subheadline) }
                    Text(log.muscles.sorted { $0.title < $1.title }.map(\.title).joined(separator: " · ")).font(.caption).foregroundStyle(Palette.muted)
                    Button("Remove logged workout", role: .destructive) { deleting = log }.buttonStyle(TargetButton())
                }
            }
        }.navigationTitle("Workout history")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.buttonStyle(TargetButton()) } }
            .confirmationDialog("Remove this workout from your history?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Remove workout", role: .destructive) { if let log = deleting { store.perform { try store.delete(kind: .workoutLog, id: log.id) } }; deleting = nil }
            } message: { Text("Its muscle progress will be recalculated.") }
    }
}
