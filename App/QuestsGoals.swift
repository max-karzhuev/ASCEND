import SwiftUI

struct QuestsView: View {
    @Environment(AppStore.self) private var store
    @Environment(NavigationState.self) private var nav
    @State private var filter = "Today"
    @State private var category = "all"
    @State private var removal: QuestRemoval?
    @State private var weeklyDraft: Occurrence?
    let filters = ["Today", "Upcoming", "Completed", "Missed", "Routines"]
    var filtered: [Occurrence] {
        let p = store.planning
        let list: [Occurrence]
        switch filter {
        case "Upcoming": list = (1...7).flatMap { store.occurrences(on: p.adding($0, to: store.today)) }
        case "Completed": list = store.ledger.occurrences.filter { store.ledger.completion($0.id)?.active == true }.sorted { $0.day > $1.day }
        case "Missed": list = store.ledger.occurrences.filter { $0.day < store.today && store.ledger.completion($0.id)?.active != true && $0.weeklySlot == nil }.sorted { $0.day > $1.day }
        default: list = store.todayQuests
        }
        return list.filter { category == "all" || $0.quest.category == category }.map(store.displayOccurrence)
    }
    var body: some View {
        PageScroll {
            HStack { ScreenHeader(eyebrow: "One step at a time", title: "Your quests", subtitle: "Build a rhythm. Make room for what matters."); Spacer(); Button { nav.sheet = .newQuest } label: { Image(systemName: "plus") }.buttonStyle(AccentButton(color: store.profile.theme.accent)).accessibilityLabel("New quest") }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack { ForEach(filters, id: \.self) { name in Button(name) { filter = name }.buttonStyle(.bordered).tint(filter == name ? store.profile.theme.accent : Palette.muted) } }
            }
            Picker("Category", selection: $category) { Text("All categories").tag("all"); ForEach(store.categories) { Text($0.name).tag($0.id) } }.frame(maxWidth: 260)
            if filter == "Routines" {
                Card {
                    Text("Templates").font(.headline)
                    let quests = store.ledger.quests.filter { !$0.id.hasPrefix("override|") && $0.workoutPlanID == nil && (category == "all" || $0.category == category) }.sorted { $0.title < $1.title }
                    if quests.isEmpty { EmptyCard(icon: "repeat", title: "Design your daily rhythm", message: "Create a routine to start building consistency.") }
                    ForEach(quests) { q in
                        HStack {
                            VStack(alignment: .leading, spacing: 5) { Text(q.title).font(.headline); Text(q.archived ? "Archived · history preserved" : q.schedule.rawValue.capitalized).font(.caption).foregroundStyle(Palette.muted) }
                            Spacer()
                            Button("Edit") { nav.sheet = .quest(q) }.buttonStyle(.bordered)
                            Button(role: .destructive) { removal = .routine(q) } label: { Image(systemName: "trash") }.accessibilityLabel("Delete \(q.title)")
                            if q.archived { Button("Restore") { var restored = q; restored.archived = false; store.perform { try store.saveQuest(restored, old: q) } } }
                        }.padding(.vertical, 6)
                    }
                }
            } else {
                Card {
                    if filter == "Missed" { Text("A missed day is information, not a verdict. Resume whenever you’re ready.").font(.subheadline).foregroundStyle(Palette.muted) }
                    if filtered.isEmpty { EmptyCard(icon: filter == "Completed" ? "checkmark.seal" : "leaf", title: filter == "Today" ? "Space for a fresh start" : "Nothing here yet", message: filter == "Today" ? "Create your first quest, or enjoy a planned rest day." : "Your quests will appear here as your journey unfolds.") }
                    ForEach(Array(filtered.prefix(200))) { o in
                        VStack(alignment: .leading, spacing: 0) { if filter != "Today" { Text(o.day).font(.caption2.monospaced()).foregroundStyle(Palette.muted) }; QuestRow(occurrence: o); Divider().overlay(Palette.border) }
                    }
                }
            }
            if filter == "Today" { weeklyCard }
            if filter == "Upcoming" { AgendaCard() }
        }.modifier(QuestRemovalConfirmation(removal: $removal)).sheet(item: $weeklyDraft) { draft in NavigationStack { WeeklySessionEditor(occurrence: draft) }.editorFrame() }
    }
    var weeklyCard: some View {
        let weekly = store.ledger.quests.compactMap { Recurrence.revision(for: $0.id, day: store.today, ledger: store.ledger) }.filter { $0.schedule == .weekly && !$0.archived && (category == "all" || $0.category == category) }
        return Group {
            if !weekly.isEmpty {
                Card {
                    HStack { Text("This week").font(.title3.bold()); Spacer(); Text("Sessions, at your pace").font(.caption).foregroundStyle(Palette.muted) }
                    ForEach(weekly) { template in
                        let quest = Recurrence.revision(for: template.id, day: store.today, ledger: store.ledger) ?? template
                        let slots = Recurrence.loggedSessions(templateID: quest.id, day: store.today, zone: store.planning.zone, ledger: store.ledger)
                        let count = slots.filter { store.ledger.completion($0.id)?.active == true }.count
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { Text(quest.title).font(.headline); Spacer(); Text("\(count) / \(quest.weeklyTarget)").font(.caption.monospacedDigit()).foregroundStyle(store.profile.theme.accent) }
                            Meter(value: Double(count) / Double(quest.weeklyTarget))
                            HStack {
                                Button("Log a session · +\(quest.difficulty.xp) XP") { weeklyDraft = Recurrence.weeklySession(quest: quest, day: store.today, zone: store.planning.zone, sessionID: UUID().uuidString) }.buttonStyle(.bordered)
                                Spacer()
                                Menu("History") {
                                    ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                                        Button("\(store.ledger.completion(slot.id)?.active == true ? "Undo" : "Restore") session \(index + 1) · \(slot.day)") { store.toggle(slot) }
                                    }
                                    Button("Edit future weeks") { nav.sheet = .quest(template) }
                                    Button("Delete entire routine…", role: .destructive) { removal = .routine(template) }
                                    if !slots.isEmpty {
                                        Menu("Delete a session…") {
                                            ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                                                Button("Session \(index + 1) · \(slot.day)", role: .destructive) { removal = .occurrence(slot) }
                                            }
                                        }
                                    }
                                }
                            }.font(.caption)
                            if count >= quest.weeklyTarget { Label("Weekly target reached", systemImage: "checkmark.seal").font(.caption).foregroundStyle(store.profile.theme.accent) }
                        }.padding(.vertical, 8)
                    }
                }
            }
        }
    }
}

struct WeeklySessionEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var occurrence: Occurrence
    @State private var saved = false
    var body: some View {
        Form {
            Section("Log one completed session") {
                Text(occurrence.quest.title).font(.headline)
                Text("\(occurrence.day) · +\(occurrence.quest.difficulty.xp) XP")
                Text("Each session is recorded once. Sessions logged independently on another device are kept separately.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).navigationTitle("Weekly session").toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Log session") {
                guard !saved else { return }; saved = true
                do { try store.complete(occurrence); dismiss() } catch { saved = false; store.error = error.localizedDescription }
            }.disabled(saved) }
        }
    }
}

struct QuestEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(ReminderService.self) private var reminders
    @Environment(\.dismiss) private var dismiss
    var original: Quest? = nil
    var occurrence: Occurrence? = nil
    @State private var quest = Quest()
    @State private var startDate = Date()
    @State private var deadline = Date()
    @State private var hasDeadline = false
    @State private var reminder = false
    @State private var reminderTime = Calendar.current.date(from: DateComponents(hour: 18)) ?? Date()
    @State private var loaded = false
    @State private var saving = false
    var body: some View {
        Form {
            Section("The quest") {
                TextField("What will you do?", text: $quest.title)
                TextField("Notes (optional)", text: $quest.notes, axis: .vertical).lineLimit(3...6)
                Picker("Category", selection: $quest.category) { ForEach(store.categories.filter { !$0.archived || $0.id == quest.category }) { Text($0.name).tag($0.id) } }
                Picker("Difficulty", selection: $quest.difficulty) { ForEach(Difficulty.allCases, id: \.self) { Text("\($0.rawValue.capitalized) · \($0.xp) XP").tag($0) } }
            }
            if occurrence == nil {
                Section("Schedule") {
                    Picker("Repeats", selection: $quest.schedule) {
                        Text("One time").tag(Schedule.once); Text("Daily").tag(Schedule.daily)
                        Text("Selected weekdays").tag(Schedule.weekdays); Text("Weekly session target").tag(Schedule.weekly)
                    }
                    if quest.schedule == .weekdays {
                        ForEach([2,3,4,5,6,7,1], id: \.self) { day in
                            Toggle(Calendar.current.weekdaySymbols[day - 1], isOn: Binding(get: { quest.weekdays.contains(day) }, set: { enabled in if enabled { quest.weekdays.append(day) } else { quest.weekdays.removeAll { $0 == day } } }))
                        }
                    }
                    if quest.schedule == .weekly { Stepper("\(quest.weeklyTarget) sessions per week", value: $quest.weeklyTarget, in: 1...20) }
                    if original == nil { DatePicker("Starts", selection: $startDate, in: store.planning.calendar.startOfDay(for: Date())..., displayedComponents: .date).environment(\.timeZone, store.planning.calendar.timeZone) }
                    Toggle("Deadline", isOn: $hasDeadline)
                    if hasDeadline { DatePicker("Due", selection: $deadline, displayedComponents: .date).environment(\.timeZone, store.planning.calendar.timeZone) }
                    if original != nil { Text(quest.schedule == .weekly ? "Changes apply next Monday. Existing sessions and rewards stay intact." : "Routine changes apply tomorrow. To change today only, choose Edit this occurrence.").font(.caption).foregroundStyle(.secondary) }
                }
            } else {
                Section { Text("Editing only \(occurrence!.day). Its planned status and any earned reward stay unchanged. Future occurrences keep the routine’s settings.").font(.caption).foregroundStyle(.secondary) }
            }
            Section("A bigger purpose") {
                Picker("Linked goal", selection: $quest.goalID) { Text("None").tag(""); ForEach(store.activeGoals.filter { $0.kind == .numeric }) { Text($0.title).tag($0.id) } }
                if !quest.goalID.isEmpty { TextField("Contribution per completion", value: $quest.contribution, format: .number) }
            }
            Section("Reminder") {
                Toggle("Remind me on this device", isOn: $reminder)
                if reminder { DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute); Text("Uses your shared planning timezone. Reminders are delivered only by the selected device.").font(.caption).foregroundStyle(.secondary) }
            }
        }.formStyle(.grouped).scrollContentBackground(.hidden).background(Palette.background)
            .navigationTitle(occurrence != nil ? "Edit occurrence" : original == nil ? "New quest" : "Edit routine")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(quest.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving || (quest.schedule == .weekdays && quest.weekdays.isEmpty)) }
            }
            .onAppear {
                guard !loaded else { return }; loaded = true
                quest = original ?? Quest(); startDate = store.planning.date(quest.startDay.isEmpty ? store.today : quest.startDay)
                hasDeadline = !quest.deadline.isEmpty; if hasDeadline { deadline = store.planning.date(quest.deadline) }
                reminder = quest.reminderMinutes != nil
                if let minutes = quest.reminderMinutes { reminderTime = Calendar.current.date(from: DateComponents(hour: minutes / 60, minute: minutes % 60))! }
            }
    }
    func save() {
        saving = true
        Task {
            do {
                quest.title = quest.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if original == nil { quest.startDay = store.planning.day(startDate) }
                quest.deadline = hasDeadline ? store.planning.day(deadline) : ""
                if reminder {
                    try await reminders.requestPermission()
                    let time = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
                    quest.reminderMinutes = (time.hour ?? 18) * 60 + (time.minute ?? 0)
                    var profile = store.profile; profile.reminderDevice = store.actor; try store.saveProfile(profile)
                } else { quest.reminderMinutes = nil }
                if let occurrence { try store.editOccurrence(occurrence, quest: quest) }
                else { try store.saveQuest(quest, old: original) }
                await reminders.refresh(store: store); dismiss()
            } catch { store.error = error.localizedDescription }
            saving = false
        }
    }
}

struct GoalsView: View {
    @Environment(AppStore.self) private var store
    @Environment(NavigationState.self) private var nav
    @State private var archived = false
    var body: some View {
        PageScroll {
            HStack { ScreenHeader(eyebrow: "See the bigger picture", title: "Long-term goals", subtitle: "Meaningful progress, one real contribution at a time."); Spacer(); Button { nav.sheet = .newGoal } label: { Image(systemName: "plus") }.buttonStyle(AccentButton(color: store.profile.theme.accent)).accessibilityLabel("New goal") }
            Toggle("Show archived goals", isOn: $archived).font(.subheadline)
            let goals = store.ledger.goals.filter { $0.archived == archived }.sorted { $0.title < $1.title }
            if goals.isEmpty { Card { EmptyCard(icon: "scope", title: "Choose your next horizon", message: "Track a quantity or break an ambition into milestones.", actionTitle: "Create a goal") { nav.sheet = .newGoal } } }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 18)], spacing: 18) {
                ForEach(goals) { g in
                    Card {
                        Eyebrow(text: g.kind == .numeric ? g.unit : "Milestones")
                        GoalSummaryRow(goal: g)
                        Text("\(Progression.goalValue(g, ledger: store.ledger).formatted()) / \(Progression.goalTarget(g).formatted()) \(g.kind == .numeric ? g.unit : "weighted points")").font(.caption).foregroundStyle(Palette.muted)
                        if !g.targetDay.isEmpty { Label("Target \(g.targetDay)", systemImage: "calendar").font(.caption).foregroundStyle(Palette.muted) }
                        Button("View progress →") { nav.sheet = .goal(g) }.buttonStyle(TargetButton()).foregroundStyle(store.profile.theme.accent).font(.subheadline)
                    }
                }
            }
        }
    }
}
struct GoalEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var original: Goal? = nil
    @State private var goal = Goal()
    @State private var targetDate = Date()
    @State private var hasTargetDate = false
    @State private var loaded = false
    var body: some View {
        Form {
            Section("Your ambition") {
                TextField("Goal title", text: $goal.title)
                TextField("Why it matters", text: $goal.notes, axis: .vertical).lineLimit(3...6)
                Picker("Category", selection: $goal.category) { ForEach(store.categories) { Text($0.name).tag($0.id) } }
                Picker("Track by", selection: $goal.kind) { Text("A quantity").tag(GoalKind.numeric); Text("Milestones").tag(GoalKind.milestones) }.disabled(original != nil)
            }
            Section("Progress") {
                if goal.kind == .numeric {
                    TextField("Target", value: $goal.target, format: .number)
                    TextField("Unit (workouts, hours, chapters…)", text: $goal.unit)
                } else {
                    ForEach($goal.milestones) { $m in
                        HStack { TextField("Milestone", text: $m.title); TextField("Weight", value: $m.weight, format: .number).frame(width: 60); Button { goal.milestones.removeAll { $0.id == m.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(TargetButton()).accessibilityLabel("Remove milestone") }
                    }
                    Button("Add milestone", systemImage: "plus") { goal.milestones.append(Milestone(title: "")) }
                    Text("Weights describe relative effort. Equal weights count each milestone equally.").font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Target date", isOn: $hasTargetDate)
                if hasTargetDate { DatePicker("Aim for", selection: $targetDate, displayedComponents: .date).environment(\.timeZone, store.planning.calendar.timeZone) }
            }
        }.formStyle(.grouped).scrollContentBackground(.hidden).background(Palette.background)
            .navigationTitle(original == nil ? "New goal" : "Edit goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    store.perform {
                        guard goal.target > 0, goal.target.isFinite, goal.kind != .milestones || (!goal.milestones.isEmpty && goal.milestones.allSatisfy({ !$0.title.isEmpty && $0.weight > 0 && $0.weight.isFinite })) else { throw DataError.invalid("Enter a positive target or at least one named, positively weighted milestone") }
                        goal.targetDay = hasTargetDate ? store.planning.day(targetDate) : ""
                        try store.put(goal, kind: .goal, id: goal.id, old: original); dismiss()
                    }
                }.disabled(goal.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }.onAppear { guard !loaded else { return }; loaded = true; goal = original ?? Goal(); hasTargetDate = !goal.targetDay.isEmpty; if hasTargetDate { targetDate = store.planning.date(goal.targetDay) } }
    }
}
struct GoalDetail: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var goalID: String
    @State private var editing = false
    @State private var contribution: Contribution?
    var goal: Goal? { store.ledger.goals.first { $0.id == goalID } }
    var body: some View {
        PageScroll {
            if let goal {
                ScreenHeader(eyebrow: "Your horizon", title: goal.title, subtitle: goal.notes)
                Card {
                    HStack { Text("\(Progression.goalValue(goal, ledger: store.ledger).formatted()) / \(Progression.goalTarget(goal).formatted()) \(goal.kind == .numeric ? goal.unit : "points")").font(.headline); Spacer(); Text("\(Int(Progression.goalRatio(goal, ledger: store.ledger) * 100))%").foregroundStyle(store.profile.theme.accent) }
                    Meter(value: Progression.goalRatio(goal, ledger: store.ledger), height: 12)
                    if goal.kind == .milestones {
                        ForEach(goal.milestones) { milestone in
                            let check = store.ledger.value(MilestoneCheck.self, kind: .milestone, id: milestone.id)
                            Toggle(isOn: Binding(get: { check?.done ?? false }, set: { done in store.perform { try store.put(MilestoneCheck(id: milestone.id, goalID: goal.id, done: done), kind: .milestone, id: milestone.id) } })) { Text("\(milestone.title) · \(milestone.weight.formatted())") }
                        }
                        if let next = goal.milestones.first(where: { store.ledger.value(MilestoneCheck.self, kind: .milestone, id: $0.id)?.done != true }) { Label("Next: \(next.title)", systemImage: "arrow.right").font(.subheadline).foregroundStyle(Palette.muted) }
                    } else {
                        Text("Next: record a contribution or complete a linked quest.").font(.subheadline).foregroundStyle(Palette.muted)
                        Button("Add a contribution", systemImage: "plus") { contribution = Contribution(goalID: goal.id, amount: 1, day: store.today, note: "") }.buttonStyle(AccentButton(color: store.profile.theme.accent))
                    }
                }
                if goal.kind == .numeric {
                    Card {
                        Text("Contribution history").font(.headline)
                        let manual = store.ledger.values(Contribution.self, kind: .contribution).filter { $0.goalID == goal.id }.sorted { $0.day > $1.day }
                        let linked = store.ledger.completions.filter { $0.goalID == goal.id }.sorted { $0.day > $1.day }
                        if manual.isEmpty && linked.isEmpty { Text("Your first contribution starts the story.").foregroundStyle(Palette.muted) }
                        ForEach(manual) { c in HStack { VStack(alignment: .leading) { Text(c.note.isEmpty ? "Manual contribution" : c.note); Text(c.day).font(.caption).foregroundStyle(Palette.muted) }; Spacer(); Text("+\(c.amount.formatted())").foregroundStyle(store.profile.theme.accent); Button("Edit") { contribution = c } } }
                        ForEach(linked) { c in HStack { VStack(alignment: .leading) { Text(c.title); Text("\(c.day) · linked quest").font(.caption).foregroundStyle(Palette.muted) }; Spacer(); Text("+\(c.amount.formatted())").foregroundStyle(store.profile.theme.accent) } }
                    }
                }
                HStack { Button("Edit goal") { editing = true }; Spacer(); Button(goal.archived ? "Restore goal" : "Archive goal") { var next = goal; next.archived.toggle(); store.perform { try store.put(next, kind: .goal, id: goal.id, old: goal) } } }.buttonStyle(.bordered)
            } else { EmptyCard(icon: "archivebox", title: "Goal unavailable", message: "This goal is no longer in the current history.") }
        }.navigationTitle("Goal progress").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $editing) { if let goal { NavigationStack { GoalEditor(original: goal) }.editorFrame() } }
            .sheet(item: $contribution) { c in NavigationStack { ContributionEditor(value: c) }.editorFrame() }
    }
}
struct ContributionEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var value: Contribution
    @State private var date = Date()
    var body: some View {
        Form {
            TextField("Quantity", value: $value.amount, format: .number)
            TextField("Note", text: $value.note)
            DatePicker("Date", selection: $date, in: ...store.planning.date(store.today), displayedComponents: .date).environment(\.timeZone, store.planning.calendar.timeZone)
            if store.ledger.value(Contribution.self, kind: .contribution, id: value.id) != nil {
                Button("Remove contribution", role: .destructive) { store.perform { try store.delete(kind: .contribution, id: value.id); dismiss() } }
            }
        }.formStyle(.grouped).navigationTitle("Contribution").toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { store.perform { value.day = store.planning.day(date); try store.put(value, kind: .contribution, id: value.id, old: store.ledger.value(Contribution.self, kind: .contribution, id: value.id)); dismiss() } }.disabled(value.amount <= 0 || !value.amount.isFinite) }
        }.onAppear { date = store.planning.date(value.day) }
    }
}

enum QuestRemoval {
    case occurrence(Occurrence)
    case routine(Quest)
    var title: String {
        switch self {
        case .occurrence(let o): return "Delete “\(o.quest.title)” for \(o.day)?"
        case .routine(let q): return "Delete “\(q.title)”?"
        }
    }
    var message: String {
        switch self {
        case .occurrence: return "This removes this occurrence and its XP and goal credit. Other dates stay on your schedule."
        case .routine: return "This removes the quest from all dates, including its completed history, XP, and linked goal credit. To keep history, use Archive instead."
        }
    }
}
struct QuestRemovalConfirmation: ViewModifier {
    @Environment(AppStore.self) private var store
    @Binding var removal: QuestRemoval?
    func body(content: Content) -> some View {
        content.alert(removal?.title ?? "Delete quest?", isPresented: Binding(get: { removal != nil },
                      set: { if !$0 { removal = nil } }), presenting: removal) { item in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                store.perform {
                    switch item {
                    case .occurrence(let o): try store.delete(kind: .occurrence, id: o.id)
                    case .routine(let q): try store.delete(kind: .quest, id: q.id)
                    }
                }
            }
        } message: { Text($0.message) }
    }
}
