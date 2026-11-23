import SwiftUI

private func drillDuration(_ seconds: Int) -> String {
    seconds.isMultiple(of: 60) ? "\(seconds / 60) min" : "\(seconds) sec"
}

struct MentalMathCard: View {
    @Environment(AppStore.self) private var store
    @Environment(NavigationState.self) private var nav

    var body: some View {
        let record = store.mentalMath
        Card(padding: 16) {
            HStack {
                Label("Mental math", systemImage: "plus.forwardslash.minus").font(.title3.bold())
                Spacer()
                Button { nav.sheet = .mentalMath(quickStart: false) } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(.plain).accessibilityLabel("Configure mental math").help("Configure drill")
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Menu(record.settings.difficultyName) {
                        ForEach(Difficulty.allCases, id: \.self) { level in
                            Button(level.rawValue.capitalized) {
                                var settings = store.mentalMath.settings
                                settings.apply(level)
                                store.perform { try store.saveMentalMath(settings: settings) }
                            }
                        }
                        Button("Customize ranges…") { nav.sheet = .mentalMath(quickStart: false) }
                    }.fixedSize().accessibilityLabel("Difficulty, \(record.settings.difficultyName)")
                    Text("\(drillDuration(record.settings.seconds))   ·   \(record.settings.symbols)").font(.headline)
                    if let last = record.last {
                        Text("Last round · \(last.score) correct in \(drillDuration(last.seconds))").font(.caption).foregroundStyle(Palette.muted)
                    }
                }
                Spacer(minLength: 0)
                Button("Start drill") { nav.sheet = .mentalMath(quickStart: true) }
                    .buttonStyle(AccentButton(color: store.profile.theme.accent))
            }
        }
    }
}

private struct RangeDraft {
    var low: String
    var high: String
    init(_ bounds: OperandBounds) { low = String(bounds.low); high = String(bounds.high) }
    var bounds: OperandBounds? {
        guard let low = Int(low), let high = Int(high) else { return nil }
        return OperandBounds(low: low, high: high)
    }
}

struct MentalMathView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var typing: Bool
    let quickStart: Bool
    @State private var settings: MentalMathSettings
    @State private var addLeft: RangeDraft
    @State private var addRight: RangeDraft
    @State private var factorLeft: RangeDraft
    @State private var factorRight: RangeDraft
    @State private var round: MentalMathRound?
    @State private var finishedScore: Int?
    @State private var endedEarly = false
    @State private var unsavedRound: MentalMathCompletion?
    @State private var saveError: String?
    @State private var answer = ""
    @State private var appeared = false

    init(settings: MentalMathSettings, quickStart: Bool) {
        self.quickStart = quickStart
        _settings = State(initialValue: settings)
        _addLeft = State(initialValue: RangeDraft(settings.addLeft))
        _addRight = State(initialValue: RangeDraft(settings.addRight))
        _factorLeft = State(initialValue: RangeDraft(settings.factorLeft))
        _factorRight = State(initialValue: RangeDraft(settings.factorRight))
    }

    private var usesSums: Bool { !settings.operations.isDisjoint(with: [.addition, .subtraction]) }
    private var usesFactors: Bool { !settings.operations.isDisjoint(with: [.multiplication, .division]) }
    private var selection: MentalMathSettings? {
        var chosen = settings
        if usesSums {
            guard let left = addLeft.bounds, let right = addRight.bounds else { return nil }
            chosen.addLeft = left
            chosen.addRight = right
        }
        if usesFactors {
            guard let left = factorLeft.bounds, let right = factorRight.bounds else { return nil }
            chosen.factorLeft = left
            chosen.factorRight = right
        }
        return chosen.isValid ? chosen : nil
    }
    private var accent: Color { store.profile.theme.accent }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let round {
                    play(round)
                } else if let finishedScore {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(endedEarly ? "Round ended early" : "Time’s up").font(.title2.bold())
                        Text("\(finishedScore) correct").font(.system(.largeTitle, design: .rounded, weight: .bold)).foregroundStyle(accent)
                        Text("\(settings.difficultyName) · \(drillDuration(settings.seconds)) · \(settings.symbols)").foregroundStyle(Palette.muted)
                    }
                    if let saveError {
                        Text(saveError).foregroundStyle(.orange)
                        Button("Retry saving round") { saveReward() }
                    } else if !endedEarly {
                        Label("+\(MentalMathCompletion.xp) XP", systemImage: "sparkles").foregroundStyle(accent)
                    }
                    Button("Play again") { start() }.buttonStyle(AccentButton(color: accent))
                    Button("Change settings") { self.finishedScore = nil }
                } else {
                    setup
                }
            }.padding(22).frame(maxWidth: 620, alignment: .leading).frame(maxWidth: .infinity)
        }
        .background(Palette.background).navigationTitle("Mental math")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if round == nil { Button("Done") { dismiss() } }
            }
        }
        .interactiveDismissDisabled(round != nil)
        .onAppear {
            guard !appeared else { return }
            appeared = true
            if quickStart { start() }
        }
        .task(id: round?.deadline) {
            guard let deadline = round?.deadline else { return }
            do { try await ContinuousClock().sleep(until: deadline) } catch { return }
            if round?.deadline == deadline { finish() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && round?.remaining() == 0 { finish() }
        }
    }

    private var setup: some View {
        Group {
            Text("Solve as many as you can before time runs out. A correct answer advances immediately.")
                .foregroundStyle(Palette.muted)
            VStack(alignment: .leading, spacing: 8) {
                Text("Difficulty").font(.headline)
                HStack {
                    ForEach(Difficulty.allCases, id: \.self) { level in
                        Button(level.rawValue.capitalized) { applyPreset(level) }
                            .buttonStyle(.bordered)
                            .tint(selection?.difficulty == level ? accent : Palette.muted)
                            .accessibilityAddTraits(selection?.difficulty == level ? .isSelected : [])
                    }
                }
                Text("\(selection?.difficultyName ?? "Custom") ranges · Finish the timer to earn \(MentalMathCompletion.xp) XP.")
                    .font(.caption).foregroundStyle(Palette.muted)
            }
            Picker("Duration", selection: $settings.seconds) {
                ForEach(MentalMathSettings.durations, id: \.self) { Text(drillDuration($0)).tag($0) }
            }
            Text("Operations").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), alignment: .leading)], alignment: .leading) {
                ForEach(ArithmeticOperation.allCases, id: \.self) { op in
                    Toggle(op.name, isOn: Binding(get: { settings.operations.contains(op) }, set: { enabled in
                        if enabled { settings.operations.insert(op) } else { settings.operations.remove(op) }
                    }))
                }
            }
            if usesSums { ranges("Addends", first: $addLeft, second: $addRight) }
            if usesFactors { ranges("Factors", first: $factorLeft, second: $factorRight) }
            if selection == nil {
                Text(settings.operations.isEmpty ? "Select at least one operation." : "Use ordered whole-number ranges within 0–999 for addends and 1–999 for factors.")
                    .font(.callout).foregroundStyle(.orange)
            }
            Button("Start drill") { start() }.buttonStyle(AccentButton(color: accent)).disabled(selection == nil)
        }
    }

    private func ranges(_ title: String, first: Binding<RangeDraft>, second: Binding<RangeDraft>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            rangeRow("First", first, group: title)
            rangeRow("Second", second, group: title)
        }
    }

    private func rangeRow(_ label: String, _ range: Binding<RangeDraft>, group: String) -> some View {
        HStack {
            Text(label).frame(minWidth: 50, alignment: .leading)
            TextField("Min", text: range.low).accessibilityLabel("\(group), \(label) minimum")
            Text("to").foregroundStyle(Palette.muted)
            TextField("Max", text: range.high).accessibilityLabel("\(group), \(label) maximum")
        }.textFieldStyle(.roundedBorder)
        #if os(iOS)
        .keyboardType(.numberPad)
        #endif
    }

    private func play(_ current: MentalMathRound) -> some View {
        VStack(spacing: 24) {
            HStack {
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    let left = current.remaining()
                    Label(String(format: "%d:%02d", left / 60, left % 60), systemImage: "timer")
                        .accessibilityLabel("\(left) seconds remaining")
                }
                Spacer()
                Text("\(current.score) correct")
            }.font(.headline.monospacedDigit()).foregroundStyle(accent)
            let p = current.problem
            Text("\(String(p.left)) \(p.operation.rawValue) \(String(p.right))")
                .font(.system(size: 52, weight: .semibold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.55)
                .accessibilityLabel("\(p.left), \(p.operation.name), \(p.right)")
            TextField("Answer", text: $answer)
                .accessibilityLabel("Your answer").multilineTextAlignment(.center)
                .font(.title2.monospacedDigit()).textFieldStyle(.roundedBorder)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .frame(maxWidth: 200).focused($typing)
                .task { typing = true }
                .onChange(of: answer) { _, input in
                    guard var active = round else { return }
                    let now = ContinuousClock.now
                    if now >= active.deadline { finish(); return }
                    if active.accept(input, at: now) { round = active; answer = "" }
                }
            Text("Type the answer to advance.").font(.caption).foregroundStyle(Palette.muted)
            Button("End round") { finish() }.buttonStyle(.bordered)
        }.padding(.vertical, 8)
    }

    private func applyPreset(_ difficulty: Difficulty) {
        settings.apply(difficulty)
        addLeft = RangeDraft(settings.addLeft)
        addRight = RangeDraft(settings.addRight)
        factorLeft = RangeDraft(settings.factorLeft)
        factorRight = RangeDraft(settings.factorRight)
    }

    private func start() {
        guard let chosen = selection, let fresh = MentalMathRound(settings: chosen) else { return }
        store.perform { try store.saveMentalMath(settings: chosen) }
        settings = chosen
        finishedScore = nil
        unsavedRound = nil
        saveError = nil
        endedEarly = false
        answer = ""
        round = fresh
    }

    private func finish() {
        guard let active = round else { return }
        endedEarly = active.remaining() > 0
        round = nil
        typing = false
        finishedScore = active.score
        if !endedEarly {
            unsavedRound = MentalMathCompletion(id: active.id, day: store.planning.day(Date()),
                seconds: active.settings.seconds, score: active.score, difficulty: active.settings.difficulty)
            saveReward()
        }
    }

    private func saveReward() {
        guard let unsavedRound else { return }
        do {
            try store.finishMentalMath(unsavedRound)
            self.unsavedRound = nil
            saveError = nil
        } catch {
            saveError = "Couldn’t save the round. \(error.localizedDescription)"
        }
    }
}
