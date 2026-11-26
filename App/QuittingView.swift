import SwiftUI

struct QuittingCard: View {
    @Environment(AppStore.self) private var store
    @State private var showingManager = false
    @State private var checking: QuitHabit?
    var body: some View {
        Card {
            HStack {
                Label("Quitting streaks", systemImage: "leaf").font(.title3.bold())
                Spacer()
                Button { showingManager = true } label: { Image(systemName: "slider.horizontal.3") }.buttonStyle(TargetButton()).accessibilityLabel("Manage quitting goals")
            }
            let habits = store.quitHabits.filter { !$0.archived }
            if habits.isEmpty {
                EmptyCard(icon: "leaf", title: "One day at a time", message: "Choose something to leave behind, then check in each evening.", actionTitle: "Add quitting goal") { showingManager = true }
            } else {
                ForEach(habits) { habit in
                    QuitHabitRow(habit: habit) { checking = habit }
                    if habit.id != habits.last?.id { Divider().overlay(Palette.border) }
                }
            }
            Text("Daily evening check-ins · automatic two-day freeze").font(.caption).foregroundStyle(Palette.muted)
        }
        .sheet(isPresented: $showingManager) { NavigationStack { QuittingManager() }.editorFrame().preferredColorScheme(.dark) }
        .sheet(item: $checking) { habit in NavigationStack { QuitCheckInView(habit: habit) }.editorFrame().preferredColorScheme(.dark) }
    }
}
struct QuitHabitRow: View {
    @Environment(AppStore.self) private var store
    var habit: QuitHabit
    var checkIn: () -> Void
    var body: some View {
        let status = Quitting.status(habit: habit, checkIns: store.quitCheckIns, today: store.today, planning: store.planning)
        let entry = store.quitCheckIns.first { $0.habitID == habit.id && $0.day == store.today }
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(habit.name).font(.headline)
                Spacer()
                Text("\(status.count) days").font(.title2.bold().monospacedDigit()).foregroundStyle(store.profile.theme.accent)
            }
            if entry?.stayedFree == false {
                Text("Today’s setback is recorded. Tomorrow is a new start.").font(.subheadline).foregroundStyle(Palette.muted)
            } else { StreakStatusView(status: status, action: "Check in") }
            Button(action: checkIn) {
                Label(entry == nil ? "Evening check-in" : "Review today’s check-in", systemImage: entry == nil ? "moon" : "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }.buttonStyle(AccentButton(color: store.profile.theme.accent))
                .disabled(!habit.canCheckIn(now: store.clockNow, planning: store.planning))
            Text("Opens at \(habit.checkInHour - 12):00 PM · \(store.planning.zone)").font(.caption).foregroundStyle(Palette.muted)
        }
    }
}
struct QuitCheckInView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var habit: QuitHabit
    var body: some View {
        PageScroll {
            ScreenHeader(eyebrow: "Evening check-in", title: habit.name, subtitle: "How did today go? Record an honest check-in for \(store.today).")
            Card {
                Text("Each successful check-in adds one day. If you missed up to two days, checking in tonight saves your existing streak; those missed days won’t add credit.").foregroundStyle(Palette.muted)
                Button { save(true) } label: { Label("Stayed free today", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity) }.buttonStyle(AccentButton(color: store.profile.theme.accent))
                Button { save(false) } label: { Label("Had a setback today", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity) }.buttonStyle(TargetButton())
                Text("A setback resets this streak. Your earlier check-ins stay in your history, and you can start again tomorrow. You can correct today’s check-in here.").font(.caption).foregroundStyle(Palette.muted)
            }
        }.navigationTitle("Daily check-in")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.buttonStyle(TargetButton()) } }
    }
    func save(_ stayedFree: Bool) {
        do { try store.checkIn(habit, stayedFree: stayedFree); dismiss() }
        catch { store.error = error.localizedDescription }
    }
}
struct QuittingManager: View {
    @Environment(AppStore.self) private var store
    @Environment(ReminderService.self) private var reminders
    @Environment(\.dismiss) private var dismiss
    @State private var selection = "Weed"
    @State private var customName = ""
    @State private var hour = 20
    @State private var removing: QuitHabit?
    var body: some View {
        PageScroll {
            Card {
                Text("Add a quitting goal").font(.title3.bold())
                Picker("What would you like to quit?", selection: $selection) {
                    ForEach(QuitHabit.presets + ["Custom"], id: \.self) { Text($0).tag($0) }
                }.frame(minHeight: 44)
                if selection == "Custom" { TextField("Name your goal", text: $customName).textFieldStyle(.roundedBorder).frame(minHeight: 44) }
                Picker("Evening check-in opens", selection: $hour) {
                    ForEach(18...23, id: \.self) { Text("\($0 - 12):00 PM").tag($0) }
                }.frame(minHeight: 44)
                Text("Times use \(store.planning.zone). Check in once each evening to add a day to your streak.").font(.caption).foregroundStyle(Palette.muted)
                Button("Add goal") {
                    let name = (selection == "Custom" ? customName : selection).trimmingCharacters(in: .whitespacesAndNewlines)
                    var habit = QuitHabit(name: name, startedDay: store.today); habit.checkInHour = hour
                    do { try store.saveQuitHabit(habit); customName = ""; store.toast = "Quitting goal added" } catch { store.error = error.localizedDescription }
                }.buttonStyle(AccentButton(color: store.profile.theme.accent))
                    .disabled(goalName.isEmpty || goalName.count > 100 || store.quitHabits.contains { !$0.archived && $0.name.caseInsensitiveCompare(goalName) == .orderedSame })
            }
            Card {
                Text("Evening reminders").font(.title3.bold())
                Text("Receive a reminder at each goal’s check-in time. Reminder delivery uses the same selected device as your quest reminders.").font(.subheadline).foregroundStyle(Palette.muted)
                Button(store.profile.reminderDevice == store.actor ? "Reminders enabled here" : "Enable reminders here") {
                    Task {
                        do {
                            try await reminders.requestPermission()
                            var profile = store.profile; profile.reminderDevice = store.actor
                            try store.saveProfile(profile); await reminders.refresh(store: store)
                        } catch { store.error = error.localizedDescription }
                    }
                }.buttonStyle(TargetButton()).disabled(store.profile.reminderDevice == store.actor)
                StatusLabel(text: reminders.status, icon: "bell")
            }
            ForEach(store.quitHabits) { habit in
                Card {
                    HStack { Text(habit.name).font(.headline); Spacer(); if habit.archived { Text("Archived").font(.caption).foregroundStyle(Palette.muted) } }
                    Picker("Evening check-in", selection: Binding(get: { habit.checkInHour }, set: { value in
                        var updated = habit; updated.checkInHour = value; store.perform { try store.saveQuitHabit(updated, old: habit) }
                    })) { ForEach(18...23, id: \.self) { Text("\($0 - 12):00 PM").tag($0) } }.frame(minHeight: 44)
                    let entries = store.quitCheckIns.filter { $0.habitID == habit.id }.sorted { $0.day > $1.day }
                    if entries.isEmpty { Text("Your first check-in is waiting.").font(.caption).foregroundStyle(Palette.muted) }
                    ForEach(Array(entries.prefix(7))) { entry in
                        HStack {
                            Text(entry.day).monospacedDigit()
                            Spacer()
                            Label(entry.stayedFree ? "Stayed free" : "Setback", systemImage: entry.stayedFree ? "checkmark.circle" : "arrow.counterclockwise")
                        }.font(.caption).foregroundStyle(Palette.muted)
                    }
                    HStack {
                        Button(habit.archived ? "Restore goal" : "Archive goal") {
                            var updated = habit; updated.archived.toggle(); store.perform { try store.saveQuitHabit(updated, old: habit) }
                        }.buttonStyle(TargetButton())
                        Spacer()
                        Button("Delete", role: .destructive) { removing = habit }.buttonStyle(TargetButton())
                    }
                }
            }
        }.navigationTitle("Quitting goals")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.buttonStyle(TargetButton()) } }
            .confirmationDialog("Delete this quitting goal?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                Button("Delete goal", role: .destructive) { if let habit = removing { store.perform { try store.delete(kind: .quitHabit, id: habit.id) } }; removing = nil }
            } message: { Text("It will be removed from your dashboard. Archive it instead if you want to restore it later.") }
    }
    var goalName: String { (selection == "Custom" ? customName : selection).trimmingCharacters(in: .whitespacesAndNewlines) }
}
