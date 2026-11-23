import SwiftUI

struct OverviewView: View {
    @Environment(AppStore.self) private var store
    @Environment(NavigationState.self) private var nav
    @Environment(CalendarAgenda.self) private var agenda
    @Environment(CloudSync.self) private var sync
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        GeometryReader { geometry in
            PageScroll {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center) { greeting; Spacer(minLength: 24); newQuest }
                    VStack(alignment: .leading, spacing: 18) { greeting; newQuest }
                }
                if geometry.size.width >= 315 && !typeSize.isAccessibilitySize {
                    HStack(alignment: .center, spacing: 12) {
                        CalendarCard(compact: true).frame(width: geometry.size.width >= 680 ? 178 : 132)
                        PlayerCard(compact: geometry.size.width < 680)
                    }
                } else {
                    PlayerCard(compact: true)
                    Button { nav.sheet = .calendar } label: { Label("Open glow calendar", systemImage: "calendar") }
                }
                if geometry.size.width >= 780 && !typeSize.isAccessibilitySize {
                    HStack(alignment: .top, spacing: 18) {
                        VStack(spacing: 18) {
                            todaysQuests
                            goalsCard
                            if !agenda.selected.isEmpty { AgendaCard(compact: true) }
                        }.frame(maxWidth: .infinity)
                        VStack(spacing: 18) {
                            PuzzleFeedCard()
                            MentalMathCard()
                            homeChat
                        }.frame(maxWidth: .infinity)
                    }
                } else {
                    todaysQuests
                    PuzzleFeedCard()
                    MentalMathCard()
                    homeChat
                    goalsCard
                    if !agenda.selected.isEmpty { AgendaCard(compact: true) }
                }
                HStack {
                    Label("\(Progression.streak(ledger: store.ledger, now: Date())) day streak", systemImage: "flame.fill").font(.headline).foregroundStyle(store.profile.theme.accent)
                    Spacer()
                    Button { nav.sheet = .activity } label: { Label("Activity", systemImage: "arrow.up.right") }.buttonStyle(.plain).font(.subheadline)
                }.padding(.vertical, 2)
                StatusLabel(text: sync.status, icon: store.syncEnabled ? "icloud" : "externaldrive")
            }
        }
    }
    var greeting: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(store.clockNow, format: .dateTime.weekday(.wide).month(.wide).day())
                .environment(\.timeZone, store.planning.calendar.timeZone)
                .font(.subheadline).foregroundStyle(Palette.muted)
            Text("Rise again\(store.profile.name.isEmpty ? "" : ", \(store.profile.name)").")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
        }
    }
    var newQuest: some View {
        Button { nav.sheet = .newQuest } label: { Label("New quest", systemImage: "plus") }.buttonStyle(AccentButton(color: store.profile.theme.accent))
    }
    var todaysQuests: some View {
        Card {
            HStack {
                Text("Today’s quests").font(.title3.bold()); Spacer()
                Text("\(store.todayQuests.filter { store.ledger.completion($0.id)?.active == true }.count)/\(store.todayQuests.count)").font(.caption.monospacedDigit()).foregroundStyle(store.profile.theme.accent)
            }
            if store.todayQuests.isEmpty { EmptyCard(icon: "checklist", title: "Begin with one small step", message: "A daily ritual or a one-time ambition. Make it a quest.", actionTitle: "Create a quest") { nav.sheet = .newQuest } }
            else {
                VStack(spacing: 0) { ForEach(Array(store.todayQuests.prefix(5))) { occurrence in QuestRow(occurrence: occurrence); if occurrence.id != store.todayQuests.prefix(5).last?.id { Divider().overlay(Palette.border) } } }
                if store.todayQuests.count > 5 { Button("View all quests") { nav.destination = .quests }.buttonStyle(.plain).foregroundStyle(store.profile.theme.accent) }
            }
        }
    }
    var goalsCard: some View {
        Card {
            HStack { Text("Long-term goals").font(.title3.bold()); Spacer(); Button { nav.sheet = .newGoal } label: { Image(systemName: "plus") }.buttonStyle(.plain).accessibilityLabel("New goal") }
            if store.activeGoals.isEmpty { EmptyCard(icon: "scope", title: "Give your effort a direction", message: "Connect everyday actions to something that matters.", actionTitle: "Set a goal") { nav.sheet = .newGoal } }
            else { ForEach(Array(store.activeGoals.prefix(3))) { goal in GoalSummaryRow(goal: goal) } }
        }
    }
    var homeChat: some View {
        ChatView(embedded: true)
            .clipShape(RoundedRectangle(cornerRadius: Palette.radius))
            .overlay(RoundedRectangle(cornerRadius: Palette.radius).stroke(Palette.border))
    }
}
struct PlayerCard: View {
    var compact = false
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @State private var celebrating = false
    var body: some View {
        let player = store.progress
        Card(padding: compact ? 12 : 22) {
            HStack(spacing: 22) {
                if !compact {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18).fill(store.profile.theme.deep).rotationEffect(.degrees(45)).frame(width: 52, height: 52)
                        Image(systemName: "shield").font(.system(size: 58, weight: .ultraLight)).foregroundStyle(store.profile.theme.accent)
                        AscendMark().fill(store.profile.theme.accent, style: FillStyle(eoFill: true)).frame(width: 21, height: 23)
                    }.frame(width: 72, height: 76).scaleEffect(celebrating ? 1.12 : 1).shadow(color: store.profile.theme.accent.opacity(celebrating ? 0.5 : 0), radius: 12).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(compact ? "LVL" : "Level").font(.caption.weight(.semibold)).foregroundStyle(Palette.muted)
                        Text("\(player.level)").font(.system(compact ? .title2 : .largeTitle, design: .rounded, weight: .bold)).foregroundStyle(store.profile.theme.accent)
                        Text("RANK \(player.rank)").font(.system(.caption2, design: .monospaced, weight: .bold)).tracking(1).padding(.horizontal, 9).padding(.vertical, 5).background(Color.white.opacity(0.07), in: Capsule())
                        Spacer(minLength: 0)
                    }
                    Meter(value: Double(player.intoLevel) / Double(player.required), height: 10)
                    HStack { Text("\(player.intoLevel) / \(player.required) XP"); if !compact { Spacer(); Text("\(player.required - player.intoLevel) to level \(player.level + 1)") } }.font(.caption.monospacedDigit()).foregroundStyle(Palette.muted)
                }
            }
        }.accessibilityElement(children: .combine).onChange(of: player.level) { old, new in
            guard new > old, !reducedMotion, !store.profile.reducedMotion else { return }
            withAnimation(.spring(duration: 0.25)) { celebrating = true }
            Task { try? await Task.sleep(for: .milliseconds(350)); withAnimation(.easeOut(duration: 0.25)) { celebrating = false } }
        }
    }
}
struct CalendarCard: View {
    var compact = false
    @Environment(AppStore.self) private var store
    @Environment(NavigationState.self) private var nav
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var month = Date()
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        let p = store.planning
        if compact {
            Button { nav.sheet = .calendar } label: {
                VStack(spacing: 5) {
                    HStack {
                        Text(monthTitle).font(.caption.weight(.semibold))
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(Palette.muted)
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                        ForEach(p.monthDays(containing: store.clockNow), id: \.self) { day in
                            let summary = Progression.day(day, ledger: store.ledger, today: store.today)
                            CalendarDateSquare {
                                Text(String(Int(day.suffix(2)) ?? 1))
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .underline(day == store.today).foregroundStyle(ink(for: summary))
                            }
                            .background { glow(for: summary) }
                            .opacity(day.prefix(7) == store.today.prefix(7) ? 1 : 0.22)
                        }
                    }
                }.padding(9).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain).accessibilityLabel("Open full consistency calendar for \(monthTitle)")
        } else {
            Card(padding: 18) {
                ViewThatFits(in: .horizontal) {
                    HStack { Text("Your consistency").font(.title3.bold()); Spacer(); monthControls }
                    VStack(alignment: .leading, spacing: 12) { Text("Your consistency").font(.title3.bold()); monthControls }
                }
                if textSize.isAccessibilitySize {
                    VStack(spacing: 12) {
                        ForEach(p.monthDays(containing: month).filter { $0.prefix(7) == p.day(month).prefix(7) }, id: \.self) { day in
                            let summary = Progression.day(day, ledger: store.ledger, today: store.today)
                            Button { nav.sheet = .day(day) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(day).font(.headline)
                                    Text(summary.isFuture ? "Upcoming" : summary.planned == 0 ? "Rest day · \(summary.extras) extra activities" : "\(summary.completed) of \(summary.planned) complete").font(.subheadline)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                                    .foregroundStyle(ink(for: summary))
                                    .background { glow(for: summary) }
                            }.buttonStyle(.plain)
                        }
                    }
                } else { VStack(spacing: 7) {
                    HStack(spacing: 7) { ForEach(["M", "T", "W", "T", "F", "S", "S"].indices, id: \.self) { i in Text(["M", "T", "W", "T", "F", "S", "S"][i]).font(.caption2).foregroundStyle(Palette.muted).frame(maxWidth: .infinity) } }.accessibilityHidden(true)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 7), spacing: 7) {
                        ForEach(p.monthDays(containing: month), id: \.self) { day in tile(day) }
                    }
                }
                .frame(maxWidth: 350) // Seven 44-point dates plus six 7-point gaps.
                .frame(maxWidth: .infinity)
                }
                HStack(spacing: 6) {
                    Text("Less").font(.caption2).foregroundStyle(Palette.muted)
                    Capsule().fill(LinearGradient(colors: [Color(white: 0.095), store.profile.theme.accent],
                                                  startPoint: .leading, endPoint: .trailing))
                        .frame(width: 72, height: 7)
                    Text("More").font(.caption2).foregroundStyle(Palette.muted)
                    Spacer()
                    Label("Rest", systemImage: "square.dashed").font(.caption2).foregroundStyle(Palette.muted)
                }.accessibilityElement(children: .ignore).accessibilityLabel("Brightness increases with each planned quest completed. Underlined date is today. Dashed cells are rest days. Dots mark extra activity.")
            }
        }
    }
    var monthControls: some View {
        HStack(spacing: 14) {
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous month")
            Text(monthTitle).font(.subheadline).monospacedDigit()
            Button { shift(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Next month")
        }.buttonStyle(.plain)
    }
    func shift(_ amount: Int) { month = store.planning.calendar.date(byAdding: .month, value: amount, to: month)! }
    var monthTitle: String { let formatter = DateFormatter(); formatter.timeZone = store.planning.calendar.timeZone; formatter.dateFormat = "MMM yyyy"; return formatter.string(from: compact ? store.clockNow : month) }
    func glow(for summary: DaySummary) -> some View {
        CalendarGlow(intensity: summary.intensity, accent: store.profile.theme.accent, cornerRadius: compact ? 3 : 7)
            .animation(systemReduceMotion || store.profile.reducedMotion ? nil : .easeInOut(duration: 0.48),
                       value: summary.intensity)
    }
    func ink(for summary: DaySummary) -> Color {
        if summary.isFuture { return Palette.muted }
        return summary.intensity >= 0.53 ? .black : .white
    }
    func tile(_ day: String) -> some View {
        let summary = Progression.day(day, ledger: store.ledger, today: store.today)
        let inMonth = day.prefix(7) == store.planning.day(month).prefix(7)
        return Button { nav.sheet = .day(day) } label: {
            CalendarDateSquare {
                Text(String(Int(day.suffix(2)) ?? 1))
                    .font(.system(.caption, design: .rounded, weight: summary.intensity > 0 ? .semibold : .regular))
                    .underline(day == store.today)
                    .foregroundStyle(ink(for: summary))
            }
            .background { glow(for: summary) }
            .overlay(alignment: .bottom) {
                if !summary.isFuture && (summary.extras > 0 || summary.brainSessions > 0 || summary.mathRounds > 0) {
                    Circle().fill(summary.intensity > 0 ? ink(for: summary) : store.profile.theme.accent)
                        .frame(width: 4, height: 4).padding(.bottom, 3)
                }
            }
            .overlay {
                if summary.rest {
                    RoundedRectangle(cornerRadius: 7).strokeBorder(Color.white.opacity(0.10),
                        style: StrokeStyle(lineWidth: 0.7, dash: [2, 2]))
                }
            }
            .contentShape(Rectangle())
            .opacity(inMonth ? 1 : 0.28)
        }.buttonStyle(.plain).accessibilityLabel("\(day == store.today ? "Today, " : "")\(day), \(summary.isFuture ? "future" : summary.planned == 0 ? "rest day" : "\(summary.completed) of \(summary.planned) planned quests completed"), \(summary.extras) extra activities, \(summary.xp) XP")
    }
}
struct QuestRow: View {
    @Environment(AppStore.self) private var store
    @Environment(NavigationState.self) private var nav
    var occurrence: Occurrence
    @State private var removal: QuestRemoval?
    var body: some View {
        let completed = store.ledger.completion(occurrence.id)?.active == true
        HStack(spacing: 12) {
            Button { store.toggle(occurrence) } label: {
                Image(systemName: completed ? "checkmark.square.fill" : "square").font(.system(size: 25, weight: .light))
                    .foregroundStyle(completed ? store.profile.theme.accent : Palette.muted).frame(width: 38, height: 44)
            }.buttonStyle(.plain).disabled(occurrence.day > store.today)
                .accessibilityLabel("\(completed ? "Undo" : "Complete") \(occurrence.quest.title)")
            VStack(alignment: .leading, spacing: 4) {
                Text(occurrence.quest.title).font(.subheadline.weight(.medium)).strikethrough(completed).foregroundStyle(completed ? Palette.muted : .white)
                HStack(spacing: 7) {
                    Text(store.categories.first { $0.id == occurrence.quest.category }?.name ?? occurrence.quest.category.capitalized)
                    Text("·")
                    Text("\(store.ledger.completion(occurrence.id)?.xp ?? occurrence.quest.difficulty.xp) XP")
                }.font(.caption2).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 4)
            Menu {
                Button("Edit this occurrence") { nav.sheet = .occurrence(occurrence) }
                if occurrence.quest.schedule != .once {
                    Button("Delete this occurrence…", role: .destructive) { removal = .occurrence(occurrence) }
                }
                if let q = store.ledger.quests.first(where: { $0.id == occurrence.templateID }) {
                    Button("Edit future occurrences") { nav.sheet = .quest(q) }
                    Button("Archive routine") { store.perform { try store.archiveQuest(q) } }
                    Button(q.schedule == .once ? "Delete quest…" : "Delete entire routine…", role: .destructive) { removal = .routine(q) }
                }
            } label: { Image(systemName: "ellipsis").frame(width: 24, height: 35).foregroundStyle(Palette.muted) }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Options for \(occurrence.quest.title)")
        }.padding(.vertical, 6).modifier(QuestRemovalConfirmation(removal: $removal))
    }
}
struct GoalSummaryRow: View {
    @Environment(AppStore.self) private var store
    @Environment(NavigationState.self) private var nav
    var goal: Goal
    var body: some View {
        Button { nav.sheet = .goal(goal) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack { Text(goal.title).font(.subheadline.weight(.medium)); Spacer(); Text("\(Int(Progression.goalRatio(goal, ledger: store.ledger) * 100))%").font(.caption.monospacedDigit()).foregroundStyle(Palette.muted) }
                Meter(value: Progression.goalRatio(goal, ledger: store.ledger), height: 6)
            }.padding(.vertical, 5)
        }.buttonStyle(.plain)
    }
}
