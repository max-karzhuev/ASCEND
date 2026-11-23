import SwiftUI
import UniformTypeIdentifiers

struct JSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
struct ThemePicker: View {
    @Binding var selection: Theme
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 12) {
            ForEach(Theme.allCases, id: \.self) { theme in
                Button { selection = theme } label: {
                    VStack(spacing: 10) {
                        ZStack { Circle().fill(theme.accent).frame(width: 25, height: 25); if selection == theme { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.black) } }
                        Text(theme.rawValue.capitalized).font(.caption.weight(.medium)).foregroundStyle(.white)
                    }.frame(maxWidth: .infinity).padding(.vertical, 14).background(selection == theme ? theme.deep : Palette.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(selection == theme ? theme.accent.opacity(0.65) : Palette.border))
                }.buttonStyle(.plain).accessibilityLabel("\(theme.rawValue.capitalized) theme").accessibilityAddTraits(selection == theme ? .isSelected : [])
            }
        }
    }
}
struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @State private var profile = Profile()
    @State private var step = 0
    @State private var firstQuest = ""
    @State private var categories = Set(Category.defaults.map(\.id))
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if store.isValidation { ValidationBanner() }
                HStack { Brand(); Spacer(); Text("\(step + 1) / 3").font(.caption.monospacedDigit()).foregroundStyle(Palette.muted) }
                ScreenHeader(eyebrow: "Welcome to your next chapter", title: step == 0 ? "Great things start small." : step == 1 ? "Make it your own." : "Your first step awaits.", subtitle: step == 0 ? "A little more intentional. A little more consistent. A little more you." : step == 1 ? "Choose the areas you want to grow." : "Start with something achievable. You can change it anytime.")
                Card {
                    if step == 0 {
                        TextField("What should we call you?", text: $profile.name).textFieldStyle(.roundedBorder).font(.title3)
                        Text("Choose your atmosphere").font(.headline)
                        ThemePicker(selection: $profile.theme)
                        Text("Planning timezone").font(.headline)
                        TextField("America/Toronto", text: $profile.timeZone).textFieldStyle(.roundedBorder)
                        Text("One shared timezone keeps your days consistent on Mac and iPhone.").font(.caption).foregroundStyle(Palette.muted)
                    } else if step == 1 {
                        Text("Your focus areas").font(.headline)
                        ForEach(Category.defaults) { category in Toggle(category.name, isOn: Binding(get: { categories.contains(category.id) }, set: { if $0 { categories.insert(category.id) } else { categories.remove(category.id) } })) }
                        Divider()
                        Text("Subjects to explore").font(.headline)
                        ForEach(Profile().subjects, id: \.self) { subject in Toggle(subject, isOn: Binding(get: { profile.subjects.contains(subject) }, set: { if $0 { profile.subjects.append(subject) } else { profile.subjects.removeAll { $0 == subject } } })) }
                        Text("Custom categories, subjects, and subtopics can be added later.").font(.caption).foregroundStyle(Palette.muted)
                    } else {
                        TextField("Your first daily quest (optional)", text: $firstQuest).textFieldStyle(.roundedBorder)
                        Text("Try “Read for 15 minutes” or “Take a walk”. This will be a medium daily quest worth 25 XP.").font(.subheadline).foregroundStyle(Palette.muted)
                        Divider()
                        Label("Start offline", systemImage: "externaldrive").font(.headline)
                        Text("Quests and goals work immediately. You can enable iCloud and connect an AI gateway in Settings whenever you’re ready.").font(.subheadline).foregroundStyle(Palette.muted)
                    }
                }
                HStack {
                    if step > 0 { Button("Back") { step -= 1 }.buttonStyle(.plain) }
                    Spacer()
                    Button(step < 2 ? "Continue →" : "Start ascending →") {
                        if step < 2 { step += 1 }
                        else { guard !store.profile.onboarded else { return }; store.perform { profile.name = String(profile.name.prefix(100)); try store.onboard(profile: profile, firstQuest: firstQuest, selectedCategories: categories) } }
                    }.buttonStyle(AccentButton(color: profile.theme.accent)).disabled(TimeZone(identifier: profile.timeZone) == nil)
                }
                Text("Your history starts at level 1. Every point is yours to earn.").font(.caption).foregroundStyle(Palette.muted)
            }.padding(30).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }.background(Palette.background).tint(profile.theme.accent)
        #if os(macOS)
        .frame(minWidth: 700, minHeight: 600)
        #endif
    }
}
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(CloudSync.self) private var sync
    @Environment(AIClient.self) private var ai
    @Environment(ReminderService.self) private var reminders
    @State private var name = ""
    @State private var zone = ""
    @State private var token = ""
    @State private var newCategory = ""
    @State private var newSubject = ""
    @State private var exporting = false
    @State private var importing = false
    @State private var document = JSONDocument(data: Data())
    @State private var confirmLocal = false
    @State private var confirmShared = false
    @State private var confirmSync = false
    var body: some View {
        @Bindable var ai = ai
        PageScroll {
            ScreenHeader(eyebrow: "Your ascent, your way", title: "Settings", subtitle: "Make space for the way you want to grow.")
            Card {
                Text("Profile & appearance").font(.title3.bold())
                HStack { TextField("Display name", text: $name).textFieldStyle(.roundedBorder); Button("Save") { var p = store.profile; p.name = String(name.prefix(100)); store.perform { try store.saveProfile(p) } }.buttonStyle(.bordered) }
                ThemePicker(selection: Binding(get: { store.profile.theme }, set: { theme in var p = store.profile; p.theme = theme; store.perform { try store.saveProfile(p) } }))
                Toggle("Reduce animations", isOn: profileBinding(\.reducedMotion))
                Text("System Reduce Motion and Dynamic Type settings are also respected.").font(.caption).foregroundStyle(Palette.muted)
            }
            Card {
                Text("Planning timezone").font(.title3.bold())
                StatusLabel(text: "Currently \(store.planning.zone)", icon: "globe")
                HStack { TextField("IANA timezone", text: $zone).textFieldStyle(.roundedBorder); Button("Schedule change") { store.perform { try store.changeTimeZone(zone); store.toast = "Timezone change scheduled for the next planning midnight" } }.buttonStyle(.bordered).disabled(TimeZone(identifier: zone) == nil) }
                Text("Changes take effect at the next midnight in the current planning timezone. Past dates and rewards keep their saved day assignments.").font(.caption).foregroundStyle(Palette.muted)
                ForEach(store.ledger.values(TimeZoneTransition.self, kind: .timezone).filter { $0.effectiveAt > Date() }) { t in StatusLabel(text: "\(t.timeZone) begins \(t.effectiveAt.formatted(date: .abbreviated, time: .shortened))", icon: "clock") }
            }
            #if os(macOS)
            Card {
                Label("Desktop widget", systemImage: "macwindow").font(.title3.bold())
                Text("Control-click your desktop and choose Edit Widgets. Search for ASCEND, then add Tasks to Complete, Calendar Glow, or Today’s Progress.")
            }
            #endif
            CalendarConnections()
            categoriesCard
            Card {
                Text("Brainmaxing subjects").font(.title3.bold())
                ForEach(store.profile.subjects, id: \.self) { subject in
                    HStack { Text(subject); Spacer(); Button { var p = store.profile; p.subjects.removeAll { $0 == subject }; store.perform { try store.saveProfile(p) } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).accessibilityLabel("Remove \(subject)") }
                }
                HStack { TextField("Add a subject", text: $newSubject).textFieldStyle(.roundedBorder); Button("Add") { let subject = newSubject.trimmingCharacters(in: .whitespacesAndNewlines); if !subject.isEmpty && !store.profile.subjects.contains(subject) { var p = store.profile; p.subjects.append(String(subject.prefix(120))); store.perform { try store.saveProfile(p) }; newSubject = "" } }.buttonStyle(.bordered) }
            }
            Card {
                Text("Reminders").font(.title3.bold())
                Toggle("This device delivers reminders", isOn: Binding(get: { store.profile.reminderDevice == store.actor }, set: { enabled in
                    Task { do { if enabled { try await reminders.requestPermission() }; var p = store.profile; p.reminderDevice = enabled ? store.actor : ""; try store.saveProfile(p); await reminders.refresh(store: store) } catch { store.error = error.localizedDescription } }
                }))
                Toggle("Daily check-in · 8:00 PM", isOn: reminderBinding(\.dailyCheckIn))
                Toggle("Brainmaxing · 6:00 PM", isOn: reminderBinding(\.brainReminder))
                StatusLabel(text: reminders.status, icon: "bell")
                Text("Times use your planning timezone. Open ASCEND at least weekly to refresh scheduled reminders. After changing the reminder device, open the old device once to cancel its existing reminders.").font(.caption).foregroundStyle(Palette.muted)
            }
            aiCard
            Card {
                Text("One shared history").font(.title3.bold())
                StatusLabel(text: sync.status, icon: store.syncEnabled ? "icloud" : "externaldrive")
                if let last = sync.lastExchange { Text("Last successful exchange: \(last.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(Palette.muted) }
                if store.syncEnabled {
                    Text("\(sync.pendingCount) local changes awaiting upload").font(.caption).foregroundStyle(Palette.muted)
                    HStack { Button("Exchange now") { Task { await sync.sync() } }.disabled(sync.working); Spacer(); Button("Pause iCloud") { sync.disable() } }.buttonStyle(.bordered)
                } else { Button("Enable private iCloud sync") { confirmSync = true }.buttonStyle(.bordered).disabled(!sync.configured) }
                if !sync.configured { Text("This local build has no CloudKit container configured. Follow Docs/SETUP.md to enable the same private container for Mac and iPhone.").font(.caption).foregroundStyle(Palette.muted) }
                Text("An exchange confirms communication with iCloud. It does not prove that another device has downloaded your changes.").font(.caption).foregroundStyle(Palette.muted)
            }
            Card {
                Text("Your data").font(.title3.bold())
                Text("ASCEND saves your history in a SwiftData database on this device. Enabling iCloud sync also stores it in your private iCloud container.")
                #if os(macOS)
                Button("Show database in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([store.container.configurations.first!.url])
                }
                #endif
                HStack {
                    Button("Export JSON", systemImage: "square.and.arrow.up") { store.perform { document = JSONDocument(data: try Archive(changes: store.ledger.changes).encoded()); exporting = true } }
                    Button("Import JSON", systemImage: "square.and.arrow.down") { importing = true }
                }.buttonStyle(.bordered)
                Text("Exports include your learning answers and history, but no credentials. Imports validate and merge records without duplicating rewards.").font(.caption).foregroundStyle(Palette.muted)
                Divider()
                Button("Clear local data on this device", role: .destructive) { confirmLocal = true }
                Button("Reset shared history everywhere", role: .destructive) { confirmShared = true }
            }
            Text("ASCEND · 1.4\nXP represents activity credit, not certification or real-world competence.").font(.caption).foregroundStyle(Palette.muted)
        }.onAppear { name = store.profile.name; zone = store.planning.zone }
            .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "ASCEND-\(store.today)") { result in if case .failure(let error) = result { store.error = error.localizedDescription } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                store.perform {
                    let url = try result.get(); let accessed = url.startAccessingSecurityScopedResource(); defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    let values = try url.resourceValues(forKeys: [.fileSizeKey]); guard (values.fileSize ?? 0) <= 50_000_000 else { throw DataError.invalid("Archive exceeds 50 MB") }
                    try store.importData(Data(contentsOf: url)); store.toast = "History imported and reconciled"
                }
            }
            .confirmationDialog("Merge this local history with your private iCloud history?", isPresented: $confirmSync, titleVisibility: .visible) { Button("Enable and merge") { Task { await sync.enable() } } } message: { Text("Use the same Apple Account, container, and CloudKit environment on both devices. Local data will be associated with this Apple Account.") }
            .confirmationDialog("Clear this device’s data?", isPresented: $confirmLocal, titleVisibility: .visible) { Button("Clear local data", role: .destructive) { sync.disable(); store.perform { try store.clearLocal() }; Task { await reminders.refresh(store: store) } } } message: { Text("This removes local history and pending changes and disables sync. Cloud history is unchanged and can be downloaded again. Export first if you need unsynced changes.") }
            .confirmationDialog("Reset history on every connected device?", isPresented: $confirmShared, titleVisibility: .visible) { Button("Reset shared history", role: .destructive) { store.perform { try store.resetEverywhere() }; Task { await sync.sync() } } } message: { Text("Progress and learning history will be reset after devices exchange with iCloud. Offline changes from the old history cannot restore it. The underlying change archive is retained for convergence; see the data-deletion guide for physical erasure. Export first if needed.") }
    }
    func profileBinding(_ key: WritableKeyPath<Profile, Bool>) -> Binding<Bool> { Binding(get: { store.profile[keyPath: key] }, set: { value in var p = store.profile; p[keyPath: key] = value; store.perform { try store.saveProfile(p) } }) }
    func reminderBinding(_ key: WritableKeyPath<Profile, Bool>) -> Binding<Bool> {
        Binding(get: { store.profile[keyPath: key] }, set: { value in Task { do { if value { try await reminders.requestPermission() }; var p = store.profile; p[keyPath: key] = value; if value { p.reminderDevice = store.actor }; try store.saveProfile(p); await reminders.refresh(store: store) } catch { store.error = error.localizedDescription } } })
    }
    var categoriesCard: some View {
        Card {
            Text("Categories").font(.title3.bold())
            ForEach(store.categories) { category in CategorySettingsRow(category: category) }
            HStack { TextField("New category", text: $newCategory).textFieldStyle(.roundedBorder); Button("Add") { let name = newCategory.trimmingCharacters(in: .whitespacesAndNewlines); guard !name.isEmpty else { return }; let c = Category(name: String(name.prefix(100))); store.perform { try store.put(c, kind: .category, id: c.id) }; newCategory = "" }.buttonStyle(.bordered) }
        }
    }
    var aiCard: some View {
        @Bindable var ai = ai
        return Card {
            Text("AI connection").font(.title3.bold())
            Text("Use the HTTPS address of your own ASCEND gateway. Its administrator sets the gateway token in ASCEND_AUTH_TOKEN. Provider API keys belong on the gateway.").font(.callout)
            TextField("Gateway URL · https://…", text: $ai.endpoint).textFieldStyle(.roundedBorder).autocorrectionDisabled()
            HStack { SecureField("Gateway authentication token", text: $token).textFieldStyle(.roundedBorder); Button("Save token") { store.perform { try ai.saveToken(token); token = "" } }.buttonStyle(.bordered).disabled(token.isEmpty) }
            Button("Forget gateway token") { store.perform { try KeychainVault.save("", endpoint: ai.endpoint); ai.status = "AI unconfigured · gateway token removed" } }.font(.caption).disabled(ai.endpoint.isEmpty)
            Picker("Provider", selection: $ai.provider) { Text("OpenAI").tag("openai"); Text("Anthropic").tag("anthropic"); Text("Google Gemini").tag("gemini"); Text("OpenAI-compatible").tag("compatible") }
                .onChange(of: ai.provider) { _, provider in ai.model = ai.providers[provider]?.first ?? "" }
            if let models = ai.providers[ai.provider], !models.isEmpty { Picker("Model", selection: $ai.model) { ForEach(models, id: \.self) { Text($0).tag($0) } } }
            else { TextField("Model ID configured on gateway", text: $ai.model).textFieldStyle(.roundedBorder).autocorrectionDisabled() }
            Stepper("Device limit: \(ai.dailyLimit) requests/day", value: $ai.dailyLimit, in: 1...100)
            HStack {
                Button("Load gateway models") { Task { do { try await ai.refreshConfiguration() } catch { ai.status = error.localizedDescription } } }
                Button(ai.testing ? "Testing…" : "Test provider") { Task { await ai.testConnection() } }.disabled(ai.testing)
            }.buttonStyle(.bordered)
            StatusLabel(text: ai.status, icon: ai.status.hasPrefix("Provider connection verified") ? "checkmark.shield" : "link")
            if let usage = ai.usage { Text("Gateway usage: \(usage.used)/\(usage.limit) requests for \(usage.day.isEmpty ? "today" : usage.day)").font(.caption).foregroundStyle(Palette.muted) }
            Text("Generation sends only the selected subject and session settings. Feedback sends only the current question, your answer, hints, and mode. Provider API keys stay on your server; the gateway token stays in this device’s Keychain. Provider API access is billed separately from consumer chatbot subscriptions. Connection tests can incur a small API charge.").font(.caption).foregroundStyle(Palette.muted)
        }
    }
}
struct CategorySettingsRow: View {
    @Environment(AppStore.self) private var store
    var category: Category
    @State private var name = ""
    var body: some View {
        HStack {
            TextField("Category", text: $name).textFieldStyle(.roundedBorder).onSubmit { save() }
            Button("Rename") { save() }.buttonStyle(.bordered)
            Button(category.archived ? "Restore" : "Archive") { var c = category; c.archived.toggle(); store.perform { try store.put(c, kind: .category, id: c.id, old: category) } }.font(.caption)
        }.onAppear { name = category.name }.opacity(category.archived ? 0.6 : 1)
    }
    func save() { guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }; var c = category; c.name = String(name.prefix(100)); store.perform { try store.put(c, kind: .category, id: c.id, old: category) } }
}
