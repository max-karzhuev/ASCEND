import SwiftUI

struct PuzzleRequest: Hashable {
    let day: String
    let subject: String
    let provider: String
    let model: String
    let endpoint: String

    func saved(in ledger: Ledger) -> [LearningSession] {
        ledger.sessions.filter {
            $0.isHomePuzzleSet == true && $0.config.subject == subject && $0.provider == provider && $0.model == model && $0.day <= day
        }.sorted { ($0.day, $0.id) > ($1.day, $1.id) }
    }
}

@MainActor @Observable final class HomePuzzleLoader {
    private(set) var running = Set<PuzzleRequest>()
    private(set) var errors: [PuzzleRequest: String] = [:]

    func load(_ request: PuzzleRequest, store: AppStore, ai: AIClient, retry: Bool = false) {
        guard ai.configured, !store.isValidation, store.profile.subjects.contains(request.subject),
              !request.saved(in: store.ledger).contains(where: { $0.day == request.day }),
              retry || errors[request] == nil, running.insert(request).inserted else { return }
        errors[request] = nil
        let actor = store.actor
        let generation = store.ledger.generation
        Task {
            defer { running.remove(request) }
            do {
                var session = try await ai.generate(HomePuzzles.topicConfig(request.subject), day: request.day)
                guard store.actor == actor, store.ledger.generation == generation,
                      store.profile.subjects.contains(request.subject), ai.provider == request.provider,
                      ai.model == request.model, ai.endpoint == request.endpoint,
                      !request.saved(in: store.ledger).contains(where: { $0.day == request.day }) else { return }
                session.isHomePuzzleSet = true
                try store.put(session, kind: .session, id: session.id)
            } catch {
                errors[request] = error.localizedDescription
            }
        }
    }
}

struct PuzzleFeedCard: View {
    @Environment(AppStore.self) private var store
    @Environment(AIClient.self) private var ai
    @Environment(NavigationState.self) private var nav
    @SceneStorage("puzzleFeed.preferTopics") private var preferTopics: Bool?
    @SceneStorage("puzzleFeed.subject") private var chosenSubject: String?
    @State private var collection = 0

    private var wantsTopics: Bool { preferTopics ?? (ai.configured && !store.profile.subjects.isEmpty) }
    private var request: PuzzleRequest? {
        let subjects = store.profile.subjects
        guard wantsTopics, !subjects.isEmpty else { return nil }
        let rotation = max(0, (Int(store.today.suffix(2)) ?? 1) - 1) % subjects.count
        let subject = chosenSubject.flatMap { subjects.contains($0) ? $0 : nil } ?? subjects[rotation]
        return PuzzleRequest(day: store.today, subject: subject, provider: ai.provider, model: ai.model, endpoint: ai.endpoint)
    }

    var body: some View {
        let batch = request.flatMap { $0.saved(in: store.ledger).first }
        let general = HomePuzzles.generalSets(day: store.today)
        let session = batch ?? general[collection]
        Card(padding: 16) {
            HStack {
                Label("Puzzle feed", systemImage: "puzzlepiece.extension").font(.title3.bold())
                Spacer()
                Menu {
                    Button("General puzzles") { preferTopics = false }
                    ForEach(store.profile.subjects, id: \.self) { subject in
                        Button(subject) { chosenSubject = subject; preferTopics = true }
                    }
                    if store.profile.subjects.isEmpty {
                        Button("Choose Brainmaxing subjects") { nav.destination = .settings }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(request?.subject ?? "General").lineLimit(1)
                        Image(systemName: "chevron.down").font(.caption2)
                    }.font(.caption.weight(.semibold)).foregroundStyle(store.profile.theme.accent).buttonTarget()
                }.menuStyle(.borderlessButton).fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Choose puzzle topic")
            }
            if let request {
                if store.homePuzzles.running.contains(request) {
                    HStack { ProgressView().controlSize(.small); Text("Preparing \(request.subject) puzzles…") }.font(.caption)
                } else if let error = store.homePuzzles.errors[request], ai.configured {
                    Text(error).font(.caption).foregroundStyle(Palette.muted)
                    Button("Retry topic puzzles") { store.homePuzzles.load(request, store: store, ai: ai, retry: true) }
                } else if !ai.configured && batch == nil {
                    Button("Connect AI for topic puzzles") { nav.destination = .settings }.font(.caption)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(session.questions.enumerated()), id: \.element.id) { index, question in
                    if index > 0 { Divider() }
                    let done = store.ledger.value(Attempt.self, kind: .attempt, id: "\(session.id)|\(question.id)")?.submitted == true
                    Button { open(session, index: index) } label: {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(question.topic.isEmpty ? session.config.subject : question.topic)
                                    .font(.caption.weight(.semibold)).foregroundStyle(store.profile.theme.accent)
                                Text(question.prompt).font(.subheadline).lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: done ? "checkmark.circle.fill" : "chevron.right")
                                .foregroundStyle(done ? store.profile.theme.accent : Palette.muted).font(.caption)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 9).contentShape(Rectangle())
                    }.buttonStyle(TargetButton()).accessibilityValue(done ? "Answered" : "Open puzzle")
                }
            }
            if batch == nil {
                HStack {
                    Text("Offline collection \(collection + 1) of \(general.count)").foregroundStyle(Palette.muted)
                    Spacer()
                    Button("Previous", systemImage: "chevron.left") { collection -= 1 }.disabled(collection == 0)
                    Button("Next", systemImage: "chevron.right") { collection += 1 }.disabled(collection + 1 == general.count)
                }.font(.caption).labelStyle(.iconOnly).buttonStyle(TargetButton())
            } else if let batch {
                Label("\(batch.model) · \(batch.day)", systemImage: "sparkles").font(.caption).foregroundStyle(Palette.muted)
            }
        }
        .task(id: ai.configured ? request : nil) {
            if let request { store.homePuzzles.load(request, store: store, ai: ai) }
        }
    }

    private func open(_ session: LearningSession, index: Int) {
        store.perform {
            if store.ledger.value(LearningSession.self, kind: .session, id: session.id) == nil {
                try store.put(session, kind: .session, id: session.id)
            }
            nav.sheet = .session(session, index: index)
        }
    }
}
