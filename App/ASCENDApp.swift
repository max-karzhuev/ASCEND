import SwiftUI
import EventKit

enum Destination: String, CaseIterable, Identifiable {
    case overview, chat, puzzles, quests, goals, brain, activity, settings
    var id: String { rawValue }
    var title: String { switch self { case .overview: "Overview"; case .brain: "Brainmaxing"; case .chat: "AI Chat"; default: rawValue.capitalized } }
    var icon: String { switch self { case .overview: "square.grid.2x2"; case .quests: "checklist"; case .goals: "scope"; case .brain: "brain.head.profile"; case .chat: "bubble.left.and.bubble.right"; case .puzzles: "puzzlepiece.extension"; case .activity: "chart.bar.xaxis"; case .settings: "slider.horizontal.3" } }
}
enum SheetRoute: Identifiable {
    case newQuest, quest(Quest), occurrence(Occurrence), newGoal, goalEdit(Goal), goal(Goal), day(String), session(LearningSession, index: Int = 0), activity, chat, calendar
    var id: String {
        switch self {
        case .newQuest: "newQuest"; case .quest(let q): "edit\(q.id)"; case .occurrence(let o): "occurrence\(o.id)"
        case .newGoal: "newGoal"; case .goalEdit(let g): "editGoal\(g.id)"; case .goal(let g): "goal\(g.id)"
        case .day(let d): "day\(d)"; case .session(let s, let index): "session\(s.id)-\(index)"; case .activity: "activity"; case .chat: "chat"; case .calendar: "calendar"
        }
    }
}
@MainActor @Observable final class NavigationState {
    var destination: Destination = .overview
    var sheet: SheetRoute?
}

@main struct ASCENDApp: App {
    @State private var store: AppStore?
    @State private var startupError: String?
    init() {
        do { _store = State(initialValue: try AppStore(validation: ProcessInfo.processInfo.arguments.contains("--validation"))) }
        catch { _startupError = State(initialValue: error.localizedDescription) }
    }
    var body: some Scene {
        WindowGroup {
            if let store { AppContainer(store: store) }
            else {
                VStack(spacing: 18) {
                    Image(systemName: "externaldrive.badge.exclamationmark").font(.largeTitle)
                    Text("Your history could not be opened").font(.title2)
                    Text(startupError ?? "Unknown storage error").textSelection(.enabled)
                    Text("ASCEND has not replaced or erased your database. Reopen the app after resolving disk access.").foregroundStyle(.secondary)
                }.padding(40).frame(maxWidth: 600)
            }
        }
        #if os(macOS)
        .defaultSize(width: 1240, height: 850)
        .windowResizability(.contentMinSize)
        #endif
    }
}
struct AppContainer: View {
    @State var store: AppStore
    @State private var sync: CloudSync
    @State private var ai = AIClient()
    @State private var navigation = NavigationState()
    @State private var agenda = CalendarAgenda()
    @State private var reminders = ReminderService()
    @Environment(\.scenePhase) private var phase
    init(store: AppStore) { self.store = store; _sync = State(initialValue: CloudSync(store: store)) }
    var body: some View {
        RootView().environment(store).environment(sync).environment(ai).environment(navigation).environment(reminders).environment(agenda)
            .onOpenURL { url in
                guard url.scheme == "ascend", url.host == "widget" else { return }
                if url.path == "/tasks" { navigation.destination = .quests }
                if url.path == "/calendar" { navigation.destination = .overview }
            }
            .preferredColorScheme(.dark).tint(store.profile.theme.accent)
            .task {
                store.didChange = {
                    sync.changed()
                    Task { await reminders.refresh(store: store) }
                }
                store.perform { try store.reconcile() }; await sync.sync(); await reminders.refresh(store: store)
            }
            .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged).receive(on: RunLoop.main)) { _ in agenda.refresh() }
            .task { agenda.refresh() }
            .onChange(of: phase) { _, phase in
                if phase == .active { agenda.refresh(); store.perform { try store.reconcile() }; Task { await sync.sync(); await reminders.refresh(store: store) } }
            }
            .task {
                #if os(macOS)
                store.publishWidget(refreshExisting: true)
                #endif
                var previous = store.today
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    guard !Task.isCancelled else { return }
                    store.clockNow = Date()
                    if store.today != previous {
                        #if os(macOS)
                        store.publishWidget()
                        #endif
                        previous = store.today; store.perform { try store.reconcile() }; await reminders.refresh(store: store); await sync.sync() }
                }
            }
    }
}
struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(NavigationState.self) private var navigation
    @Environment(CloudSync.self) private var sync
    var body: some View {
        @Bindable var store = store
        @Bindable var navigation = navigation
        Group {
            if !store.profile.onboarded { OnboardingView() }
            else {
                #if os(macOS)
                NavigationSplitView {
                    ScrollView { sidebar }.background(Palette.surface.opacity(0.6)).navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 240)
                } detail: {
                    screen(navigation.destination)
                        .toolbar {
                            ToolbarItem { Button { navigation.sheet = .newQuest } label: { Label("New quest", systemImage: "plus") }.keyboardShortcut("n", modifiers: .command) }
                            ToolbarItem { Button { Task { await sync.sync() } } label: { Label("Exchange with iCloud", systemImage: "arrow.triangle.2.circlepath") }.disabled(!store.syncEnabled || sync.working).keyboardShortcut("r", modifiers: [.command, .shift]) }
                        }
                }.navigationSplitViewStyle(.balanced).frame(minWidth: 700, minHeight: 560)
                #else
                TabView(selection: $navigation.destination) {
                    ForEach([Destination.overview, .quests, .goals, .brain, .settings]) { destination in
                        NavigationStack { screen(destination).navigationTitle(destination == .overview ? "ASCEND" : destination.title).navigationBarTitleDisplayMode(.inline)
                            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { navigation.sheet = .chat } label: { Label("AI Chat", systemImage: Destination.chat.icon) } } } }
                            .tabItem { Label(destination == .overview ? "Home" : destination == .brain ? "Brain" : destination.title, systemImage: destination.icon) }.tag(destination)
                    }
                }
                #endif
            }
        }
        .background(Palette.background)
        .sheet(item: $navigation.sheet) { route in
            NavigationStack {
                switch route {
                case .newQuest: QuestEditor()
                case .quest(let quest): QuestEditor(original: quest)
                case .occurrence(let occurrence): QuestEditor(original: occurrence.quest, occurrence: occurrence)
                case .newGoal: GoalEditor()
                case .goalEdit(let goal): GoalEditor(original: goal)
                case .goal(let goal): GoalDetail(goalID: goal.id)
                case .day(let day): DayDetail(day: day)
                case .session(let session, let index): SessionView(sessionID: session.id, initialIndex: index)
                case .activity: ActivityView()
                case .chat: ChatView(isSheet: true)
                case .calendar:
                    PageScroll { CalendarCard() }
                        .navigationTitle("Consistency calendar")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { navigation.sheet = nil } } }
                }
            }.editorFrame().tint(store.profile.theme.accent).preferredColorScheme(.dark)
        }
        .alert("Couldn’t complete that action", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
        .overlay(alignment: .bottom) {
            if let toast = store.toast {
                Label(toast, systemImage: "sparkle").font(.subheadline.bold()).padding(14)
                    .background(Palette.raised, in: Capsule()).overlay(Capsule().stroke(store.profile.theme.accent.opacity(0.5)))
                    .padding(.bottom, 75).allowsHitTesting(false)
                    .task(id: toast) { try? await Task.sleep(for: .seconds(3)); if store.toast == toast { store.toast = nil } }
            }
        }
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 30) {
            Brand().padding(.top, 25).padding(.horizontal, 22)
            VStack(spacing: 7) {
                ForEach(Destination.allCases.filter { $0 != .settings }) { item in navButton(item) }
                Rectangle().fill(Palette.border).frame(height: 1).padding(.vertical, 16).padding(.horizontal, 10)
                navButton(.settings)
            }.padding(.horizontal, 12)
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "The only way is up")
                Text("Small steps.\nExtraordinary change.").font(.caption).foregroundStyle(Palette.muted)
                StatusLabel(text: store.syncEnabled ? "iCloud enabled" : "Local mode", icon: store.syncEnabled ? "icloud" : "externaldrive")
            }.padding(22)
        }.background(Palette.surface.opacity(0.6))
    }
    func navButton(_ item: Destination) -> some View {
        Button { navigation.destination = item } label: {
            HStack(spacing: 13) {
                Image(systemName: item.icon).font(.system(size: 17)).frame(width: 22)
                Text(item.title).font(.subheadline.weight(navigation.destination == item ? .semibold : .regular))
                Spacer()
                if navigation.destination == item { Capsule().fill(store.profile.theme.accent).frame(width: 3, height: 16) }
            }.padding(.horizontal, 14).padding(.vertical, 14)
                .foregroundStyle(navigation.destination == item ? Color.white : Palette.muted)
                .background(navigation.destination == item ? store.profile.theme.deep : .clear, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).accessibilityAddTraits(navigation.destination == item ? .isSelected : [])
    }
    @ViewBuilder func screen(_ destination: Destination) -> some View {
        switch destination {
        case .overview: OverviewView()
        case .quests: QuestsView()
        case .goals: GoalsView()
        case .brain: BrainView()
        case .puzzles: PageScroll { PuzzleFeedCard() }
        case .chat: ChatView()
        case .activity: ActivityView()
        case .settings: SettingsView()
        }
    }
}
