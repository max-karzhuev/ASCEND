import SwiftUI
import Charts

struct ActivityView: View {
    @Environment(AppStore.self) private var store
    var days: [DaySummary] { (-13...0).map { Progression.day(store.planning.adding($0, to: store.today), ledger: store.ledger, today: store.today) } }
    var body: some View {
        PageScroll {
            ScreenHeader(eyebrow: "Look how far you’ve come", title: "Your activity", subtitle: "Every point has a story. Every day is another opportunity.")
            Card {
                HStack { VStack(alignment: .leading, spacing: 8) { Eyebrow(text: "Lifetime activity"); Text("\(store.progress.lifetime) XP").font(.system(.largeTitle, design: .rounded, weight: .bold)).foregroundStyle(store.profile.theme.accent) }; Spacer(); VStack(alignment: .trailing, spacing: 8) { Eyebrow(text: "Consistency"); Text("\(Progression.streak(ledger: store.ledger, now: Date())) days").font(.title2.bold()) } }
                Chart(days, id: \.day) { day in BarMark(x: .value("Day", String(day.day.suffix(5))), y: .value("XP", day.xp)).foregroundStyle(store.profile.theme.accent.gradient).cornerRadius(4) }.frame(height: 180).chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) }.accessibilityLabel("Activity XP for the last fourteen days")
            }
            Card {
                Text("Growth by category").font(.title3.bold())
                ForEach(store.categories) { c in HStack { Text(c.name); Spacer(); Text("\(Progression.categoryXP(c.id, ledger: store.ledger)) XP").font(.subheadline.monospacedDigit()).foregroundStyle(store.profile.theme.accent) } }
                let attempts = store.ledger.attempts.filter(\.submitted)
                Divider()
                Text("Brainmaxing").font(.headline)
                Text("\(attempts.count) questions submitted · \(attempts.reduce(0) { $0 + $1.hintsUsed }) hints used").font(.subheadline).foregroundStyle(Palette.muted)
                let graded = attempts.filter { $0.correct != nil && $0.mode == .assessment }
                if !graded.isEmpty { Text("\(Int(Double(graded.filter { $0.correct == true }.count) / Double(graded.count) * 100))% recorded accuracy across \(graded.count) assessed answers").font(.subheadline) }
                Text("Practice: \(attempts.filter { $0.mode == .practice }.reduce(0) { $0 + LearningRules.xp($1) }) XP · Assessment: \(attempts.filter { $0.mode == .assessment }.reduce(0) { $0 + LearningRules.xp($1) }) XP").font(.caption).foregroundStyle(Palette.muted)
                Text("AI-assisted scores are fallible. Activity credit is not a measure of real-world competence.").font(.caption).foregroundStyle(Palette.muted)
            }
            CalendarCard()
        }
    }
}
struct DayDetail: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var day: String
    var body: some View {
        let summary = Progression.day(day, ledger: store.ledger, today: store.today)
        PageScroll {
            ScreenHeader(eyebrow: "A day in your story", title: day, subtitle: summary.isFuture ? "Your upcoming plan" : summary.planned == 0 ? "A planned rest day" : "\(summary.completed) of \(summary.planned) planned quests complete")
            Card {
                HStack { Label("\(summary.xp) XP", systemImage: "sparkle"); Spacer(); if let rate = summary.ratio { Text("\(Int(rate * 100))% complete").foregroundStyle(store.profile.theme.accent) } else { Text("No planned daily quests").font(.caption).foregroundStyle(Palette.muted) } }
                let occurrences = store.occurrences(on: day)
                if occurrences.isEmpty { Text("Rest is part of the journey.").foregroundStyle(Palette.muted) }
                ForEach(occurrences) { occurrence in QuestRow(occurrence: occurrence) }
            }
            Card {
                Text("Extra activity").font(.headline)
                let extras = store.ledger.completions.filter { completion in completion.day == day && !(store.ledger.occurrences.first { o in o.id == completion.occurrenceID }?.planned ?? false) }
                if extras.isEmpty { Text("No extra activity recorded.").font(.subheadline).foregroundStyle(Palette.muted) }
                ForEach(extras) { c in HStack { Text(c.title); Spacer(); Text("+\(c.xp) XP").foregroundStyle(store.profile.theme.accent) } }
                Text("Extra activities earn XP without changing your planned daily completion rate.").font(.caption).foregroundStyle(Palette.muted)
            }
            Card {
                Text("Brainmaxing").font(.headline)
                Text("\(summary.brainSessions) sessions with submitted answers").foregroundStyle(Palette.muted)
                ForEach(store.ledger.sessions.filter { $0.day == day }) { session in Text("\(session.config.subject) · \(session.config.mode.rawValue.capitalized)").font(.subheadline) }
            }
        }.navigationTitle("Day detail").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}
