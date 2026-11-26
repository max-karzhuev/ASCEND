import SwiftUI

struct HomeCustomizationView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false
    var body: some View {
        List {
            Section {
                Text("Arrange your home in the order that works for you. Move cards with the arrows or drag the rows. Full-width cards span both columns on larger screens.")
                    .font(.subheadline).foregroundStyle(Palette.muted).listRowBackground(Color.clear)
            }
            Section("On your home screen") {
                ForEach(store.homeLayout.visible) { widget in
                    VStack(alignment: .leading, spacing: 8) {
                        Label(widget.title, systemImage: widget.icon).font(.headline)
                        HStack(spacing: 8) {
                            Button { update { $0.move(widget, by: -1) } } label: { Image(systemName: "arrow.up") }
                                .disabled(store.homeLayout.visible.first == widget).accessibilityLabel("Move \(widget.title) up")
                            Button { update { $0.move(widget, by: 1) } } label: { Image(systemName: "arrow.down") }
                                .disabled(store.homeLayout.visible.last == widget).accessibilityLabel("Move \(widget.title) down")
                            Button(store.homeLayout.wide.contains(widget) ? "Full width" : "Standard") {
                                update { if !$0.wide.insert(widget).inserted { $0.wide.remove(widget) } }
                            }.font(.caption).accessibilityLabel("\(widget.title) width").accessibilityValue(store.homeLayout.wide.contains(widget) ? "Full width" : "Standard")
                            Spacer(minLength: 0)
                            Button { update { $0.hidden.insert(widget) } } label: { Image(systemName: "minus.circle") }
                                .accessibilityLabel("Hide \(widget.title)")
                        }.buttonStyle(TargetButton())
                    }.padding(.vertical, 6).listRowBackground(Palette.surface)
                }
                .onMove { from, to in
                    var layout = store.homeLayout
                    var visible = layout.visible; visible.move(fromOffsets: from, toOffset: to)
                    layout.order = visible + layout.order.filter { layout.hidden.contains($0) }
                    store.perform { try store.saveHomeLayout(layout) }
                }
            }
            Section("Add widgets") {
                if store.homeLayout.hidden.isEmpty { Text("All widgets are on your home screen.").foregroundStyle(Palette.muted) }
                ForEach(store.homeLayout.order.filter { store.homeLayout.hidden.contains($0) }) { widget in
                    Button { update { $0.hidden.remove(widget); $0.order.removeAll { $0 == widget }; $0.order.append(widget) } } label: {
                        HStack { Label(widget.title, systemImage: widget.icon); Spacer(); Image(systemName: "plus.circle.fill") }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(TargetButton()).listRowBackground(Palette.surface)
                }
            }
            Section {
                Text("Your layout is saved on this device. Hiding a widget keeps its history.").font(.caption).foregroundStyle(Palette.muted)
                Button("Restore default layout") { confirmReset = true }.buttonStyle(TargetButton())
            }
        }
            #if os(iOS)
            .environment(\.editMode, .constant(.active))
            #endif
            .scrollContentBackground(.hidden).background(Palette.background)
            .navigationTitle("Customize home")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.buttonStyle(TargetButton()) } }
            .confirmationDialog("Restore the default widget order and show every widget?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Restore layout") { store.perform { try store.saveHomeLayout(HomeLayout()) } }
            }
    }
    func update(_ mutation: (inout HomeLayout) -> Void) {
        var layout = store.homeLayout; mutation(&layout); store.perform { try store.saveHomeLayout(layout) }
    }
}

struct AchievementStreakCard: View {
    @Environment(AppStore.self) private var store
    @Environment(NavigationState.self) private var nav
    var body: some View {
        let streak = Progression.streakStatus(ledger: store.ledger, now: store.clockNow)
        Card {
            Label("Achievement streak", systemImage: "flame").font(.title3.bold())
            HStack(alignment: .firstTextBaseline) {
                Text("\(streak.count)").font(.system(size: 44, weight: .bold, design: .rounded)).foregroundStyle(store.profile.theme.accent)
                Text("active days").foregroundStyle(Palette.muted)
            }
            StreakStatusView(status: streak, action: "Complete a quest")
            Text("Quests, submitted answers, finished drills and goal progress count. Two missed days can be frozen; they don’t add to your total.").font(.caption).foregroundStyle(Palette.muted)
            Button { nav.destination = .quests } label: { Label("Go to quests", systemImage: "arrow.right") }.buttonStyle(TargetButton())
        }
    }
}
struct StreakStatusView: View {
    var status: StreakStatus
    var action: String
    var body: some View {
        if status.frozen, let deadline = status.recoverBy {
            Label("Streak frozen · \(action) by the end of \(deadline) to save it.", systemImage: "snowflake")
                .font(.subheadline).foregroundStyle(.cyan).fixedSize(horizontal: false, vertical: true)
        } else if status.completedToday {
            Label("Today is complete", systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(.green)
        } else if status.expired {
            Text("The recovery window ended. \(action) to begin again.").font(.subheadline).foregroundStyle(Palette.muted)
        } else {
            Text(status.count == 0 ? "\(action) to start your streak." : "\(action) today to keep going.").font(.subheadline).foregroundStyle(Palette.muted)
        }
    }
}

struct HomeWidgetGallery: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        PageScroll {
            Text("Choose what belongs on your home screen. Remove widgets with Edit widgets or their context menu. Your history stays saved.")
                .foregroundStyle(Palette.muted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: 14) {
                ForEach(HomeWidget.allCases) { widget in
                    let added = !store.homeLayout.hidden.contains(widget)
                    Card {
                        Label(widget.title, systemImage: widget.icon).font(.headline)
                        Text(widget.summary).font(.caption).foregroundStyle(Palette.muted).frame(minHeight: 40, alignment: .top)
                        Button {
                            var layout = store.homeLayout
                            layout.hidden.remove(widget); layout.order.removeAll { $0 == widget }; layout.order.append(widget)
                            store.perform { try store.saveHomeLayout(layout) }
                        } label: { Label(added ? "Added" : "Add widget", systemImage: added ? "checkmark" : "plus") }
                            .buttonStyle(TargetButton()).disabled(added)
                    }
                }
            }
        }.navigationTitle("Add widgets")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.buttonStyle(TargetButton()) } }
    }
}
