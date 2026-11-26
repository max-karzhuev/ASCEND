import SwiftUI

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: String
    let content: String

    var payload: [String: String] { ["role": role, "content": content] }
}

@MainActor @Observable final class ChatSession {
    var draft = ""
    var planningMode = false
    var proposal: AIPlanProposal?
    private(set) var history: [ChatMessage] = []
    private(set) var pending: ChatMessage?
    private(set) var error: String?
    @ObservationIgnored private var task: Task<Void, Never>?

    func send(using ai: AIClient, store: AppStore) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pending == nil, ai.configured, !text.isEmpty, text.utf16.count <= 4000 else { return }
        let appContext: Data?
        do {
            store.clockNow = Date()
            appContext = planningMode ? try store.planningContext() : nil
        } catch { self.error = error.localizedDescription; return }
        let baselineLedger = store.ledger, day = store.today, planning = store.planning, actor = store.actor
        let message = ChatMessage(role: "user", content: text)
        var context = Array(history.suffix(14)).map(\.payload) + [message.payload]
        // Drop complete older turns until the JSON fits, including escaped and multibyte text.
        while context.count > 1, ((try? JSONEncoder().encode(context).count) ?? .max) > (appContext == nil ? 60_000 : 12_000) {
            context.removeFirst(2)
        }
        draft = ""
        error = nil
        pending = message
        proposal = nil
        task = Task {
            guard !Task.isCancelled, pending?.id == message.id else { return }
            do {
                let reply: String
                if let appContext {
                    let plan = try await ai.generatePlan(messages: context, context: appContext)
                    let id = UUID().uuidString
                    _ = try plan.transaction(ledger: baselineLedger, actor: actor, day: day, planning: planning, proposalID: id)
                    guard pending?.id == message.id else { return }
                    proposal = AIPlanProposal(id: id, plan: plan, baseline: appContext, generation: baselineLedger.generation)
                    reply = plan.summary
                } else { reply = try await ai.chatReply(to: context) }
                guard pending?.id == message.id else { return }
                history += [message, ChatMessage(role: "assistant", content: reply)]
            } catch {
                guard pending?.id == message.id else { return }
                self.error = error.localizedDescription
                draft = message.content
            }
            pending = nil
            task = nil
        }
    }

    func stop() {
        if let pending { draft = pending.content }
        pending = nil
        task?.cancel()
        task = nil
    }

    func clear() {
        stop()
        history = []
        proposal = nil
        draft = ""
        error = nil
    }
}

struct ChatView: View {
    var isSheet = false
    var embedded = false
    @Environment(AIClient.self) private var ai
    @Environment(AppStore.self) private var store
    @Environment(NavigationState.self) private var navigation
    @State private var confirmClear = false
    @State private var reviewingPlan = false
    private var accent: Color { store.profile.theme.accent }

    var body: some View {
        @Bindable var chat = ai.chat
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label("AI Chat", systemImage: Destination.chat.icon).font(.title2.bold())
                    Text(ai.configured ? "\(ai.provider.capitalized) · \(ai.model)" : "Connect your AI in Settings → AI connection")
                        .font(.caption).foregroundStyle(Palette.muted)
                }
                Spacer()
                if !chat.history.isEmpty || chat.pending != nil || !chat.draft.isEmpty {
                    Button { confirmClear = true } label: { Label("Clear chat", systemImage: "trash").labelStyle(.iconOnly) }
                        .help("Clear chat")
                }
                if embedded {
                    Button { navigation.sheet = .chat } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }.accessibilityLabel("Expand AI Chat")
                }
                if isSheet { Button("Done") { navigation.sheet = nil } }
            }.buttonStyle(TargetButton()).padding()
            Divider()
            if !embedded || ai.configured {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if chat.history.isEmpty && chat.pending == nil {
                            Text("What would you like to work on?").font(.title3.weight(.semibold))
                            if !embedded { Text("Turn on Plan with my app to build goals, workouts and routines you can apply in ASCEND.")
                                .font(.callout).foregroundStyle(Palette.muted) }
                        }
                        ForEach(chat.history) { message in bubble(message) }
                        if let message = chat.pending {
                            bubble(message)
                            ProgressView("Waiting for reply…").font(.caption)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }.frame(maxWidth: .infinity, alignment: .leading).padding()
                }
                .onChange(of: chat.history.count) { proxy.scrollTo("end", anchor: .bottom) }
                .onChange(of: chat.pending?.id) { proxy.scrollTo("end", anchor: .bottom) }
                .onAppear { proxy.scrollTo("end", anchor: .bottom) }
            }.frame(height: embedded ? 118 : nil)
            Divider()
            }
            VStack(alignment: .leading, spacing: 10) {
                if ai.configured {
                    if let proposal = chat.proposal, proposal.plan.changeCount > 0 {
                        Button { reviewingPlan = true } label: {
                            Label(proposal.applied ? "View applied plan" : "Review AI plan · \(proposal.plan.changeCount) changes", systemImage: "list.bullet.clipboard")
                        }.buttonStyle(TargetButton())
                    }
                    Toggle("Plan with my app", isOn: $chat.planningMode).disabled(chat.pending != nil)
                    if chat.planningMode {
                        Text("Shares your goals, quests, workouts, quitting goals and planning preferences. Review the AI’s changes before applying them.").font(.caption).foregroundStyle(Palette.muted)
                    }
                    if let error = chat.error { Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
                    TextField("Message your AI…", text: $chat.draft, axis: .vertical)
                        .lineLimit(1...5).textFieldStyle(.plain).padding(10)
                        .background(Palette.raised, in: RoundedRectangle(cornerRadius: 10))
                        .disabled(chat.pending != nil)
                    HStack {
                        Button { addQuests() } label: { Label("Add today’s quests", systemImage: "plus") }
                            .disabled(chat.pending != nil || store.todayQuests.isEmpty)
                        Spacer()
                        if chat.pending != nil { Button("Stop") { chat.stop() } }
                        else {
                            Button { chat.send(using: ai, store: store) } label: { Label("Send", systemImage: "arrow.up.circle.fill") }
                                .keyboardShortcut(.return, modifiers: .command)
                                .disabled(chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chat.draft.utf16.count > 4000)
                        }
                    }
                    if chat.draft.utf16.count > 4000 { Text("Shorten your message to 4,000 characters.").font(.caption).foregroundStyle(.orange) }
                    Text("Sending shares your message and recent chat with your AI. Chat stays in this window until you close or clear it.")
                        .font(.caption).foregroundStyle(Palette.muted)
                } else {
                    Button("Open Settings") { navigation.sheet = nil; navigation.destination = .settings }
                }
            }.controlSize(.large).padding()
        }
        .frame(maxWidth: .infinity, maxHeight: embedded ? nil : .infinity, alignment: .topLeading)
        .background(embedded ? Palette.surface : Palette.background).tint(accent)
        .sheet(isPresented: $reviewingPlan) {
            if let proposal = chat.proposal { NavigationStack { AIPlanReview(proposal: proposal) }.editorFrame().preferredColorScheme(.dark) }
        }
        .confirmationDialog("Clear this conversation?", isPresented: $confirmClear) {
            Button("Clear chat", role: .destructive) { chat.clear() }
        }
    }

    private func bubble(_ message: ChatMessage) -> some View {
        let mine = message.role == "user"
        return VStack(alignment: .leading, spacing: 5) {
            Text(mine ? "You" : ai.model).font(.caption.weight(.semibold)).foregroundStyle(mine ? accent : Palette.muted)
            Text(verbatim: message.content).textSelection(.enabled)
        }.padding(12)
            .background(mine ? accent.opacity(0.13) : Palette.raised, in: RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }

    private func addQuests() {
        let lines = store.todayQuests.map {
            let status = store.ledger.completion($0.id)?.active == true ? "Done" : "Open"
            return "• \(status) — \($0.quest.title)"
        }
        let summary = "My quests for \(store.today)\n" + lines.joined(separator: "\n")
        ai.chat.draft += (ai.chat.draft.isEmpty ? "" : "\n\n") + summary
    }
}
