import SwiftUI

struct BrainView: View {
    @Environment(AppStore.self) private var store
    @Environment(AIClient.self) private var ai
    @Environment(NavigationState.self) private var nav
    @State private var config = LearningConfig()
    @State private var generation: Task<Void, Never>?
    @State private var generating = false
    var body: some View {
        PageScroll {
            ScreenHeader(eyebrow: "Sharpen your mind", title: "Brainmaxing", subtitle: "Curiosity is a skill. Give it a daily practice.")
            Card {
                HStack { Text("Build a session").font(.title3.bold()); Spacer(); Image(systemName: "brain.head.profile").foregroundStyle(store.profile.theme.accent) }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack { ForEach(store.profile.subjects, id: \.self) { subject in Button(subject) { config.subject = subject }.buttonStyle(.bordered).tint(config.subject == subject ? store.profile.theme.accent : Palette.muted) } }
                }
                VStack(alignment: .leading, spacing: 16) {
                    TextField("Subtopic (optional)", text: $config.subtopic).textFieldStyle(.roundedBorder)
                    TextField("Ability or course level", text: $config.ability).textFieldStyle(.roundedBorder)
                    Picker("Difficulty", selection: $config.difficulty) { ForEach(Difficulty.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                    Picker("Mode", selection: $config.mode) { Text("Practice").tag(SessionMode.practice); Text("Assessment").tag(SessionMode.assessment) }.pickerStyle(.segmented)
                    Stepper("\(config.count) questions", value: $config.count, in: 1...10)
                    Text(config.mode == .practice ? "Practice earns 5 activity XP per submitted question. Explore hints freely." : "Assessment earns 10 XP for a correct unhinted answer, or 5 with hints. AI feedback can be mistaken.").font(.caption).foregroundStyle(Palette.muted)
                }
                if generating {
                    HStack { ProgressView().controlSize(.small); Text("Preparing your challenge…").font(.subheadline); Spacer(); Button("Cancel") { generation?.cancel(); generating = false } }
                } else if ai.configured {
                    Button { generate() } label: { Label("Generate challenge", systemImage: "sparkles") }.buttonStyle(AccentButton(color: store.profile.theme.accent))
                } else {
                    StatusLabel(text: "AI is unconfigured. Connect a private gateway to generate challenges.", icon: "link.badge.plus")
                    Button("Set up AI") { nav.destination = .settings }.buttonStyle(.bordered)
                }
            }
            let sessions = store.ledger.sessions.sorted { $0.day > $1.day }
            if sessions.isEmpty { Card { EmptyCard(icon: "books.vertical", title: "A library of your own", message: "Generated sessions are saved here for offline practice. Your history stays with you when you switch providers.") } }
            else {
                Card {
                    Text("Your sessions").font(.title3.bold())
                    ForEach(sessions) { session in
                        let attempts = store.ledger.attempts.filter { $0.sessionID == session.id && $0.submitted }
                        Button { nav.sheet = .session(session) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "book.closed").foregroundStyle(store.profile.theme.accent).frame(width: 30)
                                VStack(alignment: .leading, spacing: 5) { Text(session.config.subject).font(.headline); Text("\(session.config.subtopic.isEmpty ? session.config.ability : session.config.subtopic) · \(session.day)").font(.caption).foregroundStyle(Palette.muted) }
                                Spacer(); Text("\(attempts.count)/\(session.questions.count)").font(.caption.monospacedDigit()); Image(systemName: "chevron.right").font(.caption)
                            }.padding(.vertical, 8)
                        }.buttonStyle(TargetButton())
                    }
                }
                Card {
                    Text("Revisit & reinforce").font(.title3.bold())
                    let review = reviewTopics(sessions)
                    if review.isEmpty { Text("Topics to revisit will appear after feedback or hinted attempts.").font(.subheadline).foregroundStyle(Palette.muted) }
                    ForEach(review, id: \.self) { topic in Button { config.subtopic = topic } label: { Label(topic, systemImage: "arrow.counterclockwise") }.buttonStyle(TargetButton()).foregroundStyle(store.profile.theme.accent) }
                }
            }
        }.onAppear { if !store.profile.subjects.contains(config.subject) { config.subject = store.profile.subjects.first ?? "Mathematics" } }
    }
    func reviewTopics(_ sessions: [LearningSession]) -> [String] {
        Set(store.ledger.attempts.filter { $0.correct == false || $0.hintsUsed > 0 || $0.reported }.compactMap { a in sessions.first { $0.id == a.sessionID }?.questions.first { $0.id == a.questionID }?.topic }).sorted()
    }
    func generate() {
        generating = true
        generation = Task {
            defer { generating = false }
            do {
                let session = try await ai.generate(config, day: store.today)
                try Task.checkCancellation(); try store.put(session, kind: .session, id: session.id)
                nav.sheet = .session(session)
            } catch is CancellationError {} catch { if !Task.isCancelled { store.error = error.localizedDescription } }
        }
    }
}

struct SessionView: View {
    @Environment(AppStore.self) private var store
    @Environment(AIClient.self) private var ai
    @Environment(\.dismiss) private var dismiss
    var sessionID: String
    @State private var index: Int
    init(sessionID: String, initialIndex: Int = 0) {
        self.sessionID = sessionID
        _index = State(initialValue: initialIndex)
    }
    @State private var draft = ""
    @State private var grading = false
    @State private var gradeTask: Task<Void, Never>?
    @State private var reportText = ""
    @State private var reporting = false
    @State private var gradeError: String?
    @State private var draftSave: Task<Void, Never>?
    var session: LearningSession? { store.ledger.sessions.first { $0.id == sessionID } }
    var question: Question? { session?.questions[safe: index] }
    var attempt: Attempt? { guard let session, let question else { return nil }; return store.ledger.value(Attempt.self, kind: .attempt, id: "\(session.id)|\(question.id)") ?? Attempt(session: session, question: question, day: store.today) }
    var body: some View {
        PageScroll {
            if let session, let question, let attempt {
                HStack { Eyebrow(text: session.config.mode.rawValue); Spacer(); Text("Question \(index + 1) of \(session.questions.count)").font(.caption.monospacedDigit()).foregroundStyle(Palette.muted) }
                Meter(value: Double(store.ledger.attempts.filter { $0.sessionID == session.id && $0.submitted }.count) / Double(session.questions.count))
                ScreenHeader(eyebrow: question.topic, title: session.config.subject, subtitle: "\(session.config.ability) · \(session.config.difficulty.rawValue.capitalized)")
                Card {
                    RichLearningText(text: question.prompt)
                    if question.kind == .multipleChoice {
                        ForEach(question.options, id: \.self) { option in
                            Button { draft = option; saveDraft() } label: {
                                HStack(alignment: .top) { Image(systemName: draft == option ? "largecircle.fill.circle" : "circle"); Text(option); Spacer(minLength: 0) }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(draft == option ? store.profile.theme.deep : Palette.background, in: RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(TargetButton()).disabled(attempt.submitted).accessibilityAddTraits(draft == option ? .isSelected : [])
                        }
                    } else {
                        Text(question.kind == .numerical ? "Your numerical answer (use a decimal point)" : "Your reasoning").font(.caption).foregroundStyle(Palette.muted)
                        TextEditor(text: $draft).font(question.kind == .programming ? .system(.body, design: .monospaced) : .body).frame(minHeight: question.kind == .numerical ? 60 : 150).padding(7).scrollContentBackground(.hidden).background(Palette.background, in: RoundedRectangle(cornerRadius: 10)).disabled(attempt.submitted).accessibilityLabel("Your answer")
                            .onChange(of: draft) { _, _ in
                                draftSave?.cancel()
                                draftSave = Task { try? await Task.sleep(for: .milliseconds(600)); guard !Task.isCancelled else { return }; saveDraft() }
                            }
                    }
                    if !attempt.submitted {
                        HStack {
                            Button("Submit answer") { submit() }.buttonStyle(AccentButton(color: store.profile.theme.accent)).disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.count > 12000)
                            Spacer()
                            if attempt.hintsUsed < question.hints.count { Button("Hint \(attempt.hintsUsed + 1)", systemImage: "lightbulb") { var a = attempt; a.hintsUsed += 1; a.answer = draft; store.perform { try store.put(a, kind: .attempt, id: a.id, atomic: true) } }.buttonStyle(TargetButton()).foregroundStyle(store.profile.theme.accent) }
                        }
                    }
                    ForEach(Array(question.hints.prefix(attempt.hintsUsed).enumerated()), id: \.offset) { item in
                        VStack(alignment: .leading, spacing: 6) { Eyebrow(text: "Hint \(item.offset + 1)"); RichLearningText(text: item.element) }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(store.profile.theme.deep.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                if attempt.submitted {
                    Card {
                        if grading { HStack { ProgressView(); Text("Requesting AI feedback…"); Spacer(); Button("Cancel") { gradeTask?.cancel(); grading = false } } }
                        else if attempt.pendingGrade {
                            Label("Answer saved · awaiting online feedback", systemImage: "clock.badge.checkmark").font(.headline)
                            Text(gradeError ?? "Your answer is safe. Connect your AI gateway to request feedback.").font(.subheadline).foregroundStyle(Palette.muted)
                            Button("Retry feedback") { grade(question, attempt) }.buttonStyle(.bordered).disabled(!ai.configured)
                        } else {
                            Label(attempt.correct == true ? "Well done" : "A chance to deepen understanding", systemImage: attempt.correct == true ? "checkmark.seal" : "book").font(.headline).foregroundStyle(store.profile.theme.accent)
                            RichLearningText(text: attempt.feedback)
                            Divider()
                            Eyebrow(text: "Worked explanation")
                            RichLearningText(text: question.explanation)
                            Text(question.kind == .numerical || question.kind == .multipleChoice ? "Graded locally against the saved answer key. Report a problem if the question or key is wrong." : "AI-assisted feedback can be mistaken. Check important reasoning against your course materials.").font(.caption).foregroundStyle(Palette.muted)
                        }
                        Text("\(LearningRules.xp(attempt)) \(attempt.mode == .practice ? "practice" : "assessment") XP · \(attempt.hintsUsed) hints used").font(.caption).foregroundStyle(Palette.muted)
                    }
                }
                HStack {
                    Button("Previous") { move(-1) }.disabled(index == 0 || grading)
                    Spacer()
                    Button(attempt.reported ? "Problem reported" : "Report a problem", systemImage: "flag") { reportText = attempt.report; reporting = true }.font(.caption)
                    Spacer()
                    Button("Next") { move(1) }.disabled(index + 1 >= session.questions.count || grading)
                }.buttonStyle(TargetButton())
            } else { EmptyCard(icon: "book", title: "Session unavailable", message: "This session is no longer in your history.") }
        }.navigationTitle("Learning session").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { saveDraft(); dismiss() } } }
            .onAppear { draft = attempt?.answer ?? "" }
            .onChange(of: attempt?.answer) { _, answer in if attempt?.submitted == true { draft = answer ?? "" } }
            .onDisappear { draftSave?.cancel(); saveDraft() }
            .sheet(isPresented: $reporting) {
                NavigationStack {
                    Form { Text("Describe what seems incorrect. This report is saved with your learning history; it is not sent to the provider.").font(.subheadline); TextEditor(text: $reportText).frame(minHeight: 150) }
                        .navigationTitle("Report a problem").toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { reporting = false } }
                            ToolbarItem(placement: .confirmationAction) { Button("Save report") { if var a = attempt { a.reported = true; a.report = String(reportText.prefix(4000)); store.perform { try store.put(a, kind: .attempt, id: a.id, atomic: true) } }; reporting = false } }
                        }
                }.editorFrame()
            }
    }
    func saveDraft() {
        guard var a = attempt, !a.submitted, a.answer != draft else { return }
        a.answer = String(draft.prefix(12000)); store.perform { try store.put(a, kind: .attempt, id: a.id, atomic: true) }
    }
    func move(_ offset: Int) { saveDraft(); index += offset; draft = attempt?.answer ?? ""; gradeError = nil }
    func submit() {
        guard let q = question, var a = attempt, !a.submitted else { return }
        a.answer = draft; a.submitted = true; a.day = store.today
        if let correct = LearningRules.deterministic(q, answer: draft) {
            a.correct = correct; a.feedback = correct ? "Your answer matches the saved answer key." : "Your answer doesn’t match the saved answer key. Work through the explanation below."; a.pendingGrade = false
        } else { a.pendingGrade = true }
        do { try store.put(a, kind: .attempt, id: a.id, atomic: true); if a.pendingGrade { grade(q, a) } }
        catch { store.error = error.localizedDescription }
    }
    func grade(_ question: Question, _ saved: Attempt) {
        grading = true; gradeError = nil
        gradeTask = Task {
            defer { grading = false }
            do {
                let result = try await ai.grade(question: question, attempt: saved); try Task.checkCancellation()
                var a = saved; a.correct = result.correct; a.feedback = result.feedback; a.pendingGrade = false
                // Do not attach feedback to an answer replaced by a concurrent device edit.
                guard store.ledger.value(Attempt.self, kind: .attempt, id: a.id)?.answer == a.answer else { return }
                try store.put(a, kind: .attempt, id: a.id, atomic: true)
            } catch { if !Task.isCancelled { gradeError = error.localizedDescription } }
        }
    }
}
struct RichLearningText: View {
    var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(text.components(separatedBy: "```").enumerated()), id: \.offset) { part in
                if part.offset % 2 == 1 {
                    ScrollView(.horizontal) { Text(part.element).font(.system(.body, design: .monospaced)).textSelection(.enabled).padding(14) }.background(Palette.background, in: RoundedRectangle(cornerRadius: 10))
                } else { Text((try? AttributedString(markdown: part.element, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(part.element)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true).lineSpacing(5) }
            }
        }
    }
}
extension Collection { subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil } }
