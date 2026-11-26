import EventKit
import SwiftUI

struct AgendaItem: Identifiable {
    var id: String
    var title: String
    var date: Date
    var allDay: Bool
    var calendar: String
}

@MainActor @Observable final class CalendarAgenda {
    private let events = EKEventStore()
    private let defaults = UserDefaults.standard
    private let selectionKey = "agenda.calendarIDs"
    private(set) var selected: Set<String>
    private(set) var calendars: [EKCalendar] = []
    private(set) var items: [AgendaItem] = []
    private(set) var authorization = EKEventStore.authorizationStatus(for: .event)
    var message: String?
    var requesting = false

    init() {
        selected = Set(defaults.stringArray(forKey: selectionKey) ?? [])
    }

    func connect() async {
        guard !requesting else { return }
        requesting = true
        defer { requesting = false; refresh() }
        do { _ = try await events.requestFullAccessToEvents(); message = nil }
        catch { message = error.localizedDescription }
    }

    func select(_ id: String, enabled: Bool) {
        if enabled { selected.insert(id) } else { selected.remove(id) }
        defaults.set(selected.sorted(), forKey: selectionKey)
        refresh()
    }

    func disconnect() {
        selected.removeAll()
        defaults.removeObject(forKey: selectionKey)
        items.removeAll()
    }

    func refresh(now: Date = Date()) {
        authorization = EKEventStore.authorizationStatus(for: .event)
        guard authorization == .fullAccess else { items = []; calendars = []; return }
        calendars = events.calendars(for: .event).sorted {
            ($0.source.title, $0.title) < ($1.source.title, $1.title)
        }
        let included = calendars.filter { selected.contains($0.calendarIdentifier) }
        guard !included.isEmpty else { items = []; return }
        let cal = Calendar.autoupdatingCurrent
        let start = cal.startOfDay(for: now)
        guard let end = cal.date(byAdding: .day, value: 30, to: start) else { return }
        let query = events.predicateForEvents(withStart: start, end: end, calendars: included)
        items = events.events(matching: query)
            .filter { $0.status != .canceled && ($0.endDate > now || $0.startDate >= now) }
            .map { event in
                AgendaItem(id: "\(event.calendar.calendarIdentifier)|\(event.calendarItemIdentifier)|\(event.startDate.timeIntervalSinceReferenceDate)",
                           title: event.title ?? "Untitled event", date: event.startDate,
                           allDay: event.isAllDay, calendar: event.calendar.title)
            }.sorted { ($0.date, $0.title, $0.id) < ($1.date, $1.title, $1.id) }
    }
}

struct CalendarConnections: View {
    @Environment(CalendarAgenda.self) private var agenda
    @State private var setup = false
    var body: some View {
        Card {
            Label("Connected calendars", systemImage: "calendar").font(.title3.bold())
            Text("Show upcoming events from calendars you choose on this device. ASCEND reads their dates and titles for your agenda.")
                .font(.callout)
            if agenda.authorization == .fullAccess {
                ForEach(agenda.calendars, id: \.calendarIdentifier) { calendar in
                    Toggle(isOn: Binding(get: { agenda.selected.contains(calendar.calendarIdentifier) },
                                         set: { agenda.select(calendar.calendarIdentifier, enabled: $0) })) {
                        VStack(alignment: .leading) {
                            Text(calendar.title)
                            Text(calendar.source.title).foregroundStyle(.secondary).font(.caption)
                        }
                    }
                }
                if agenda.calendars.isEmpty { Text("Add a calendar account or subscription on this device, then refresh.") }
                HStack {
                    Button("Refresh calendars") { agenda.refresh() }
                    if !agenda.selected.isEmpty { Button("Disconnect all") { agenda.disconnect() } }
                }
            } else if agenda.authorization == .denied || agenda.authorization == .restricted {
                Text("Allow full calendar access for ASCEND in System Settings or Settings → Privacy & Security → Calendars.")
            } else {
                Button("Connect Apple Calendar") { Task { await agenda.connect() } }
                    .buttonStyle(.borderedProminent).disabled(agenda.requesting)
            }
            if let message = agenda.message { Text(message).font(.caption) }
            DisclosureGroup("Connect Canvas or Google Calendar", isExpanded: $setup) {
                VStack(alignment: .leading, spacing: 12) {
                    #if os(macOS)
                    Text("Canvas: In your school’s Canvas, open Calendar → Calendar Feed and copy the private link. In the Mac Calendar app, choose File → New Calendar Subscription and paste it.")
                    Text("Google: In the Mac Calendar app, choose Calendar → Add Account → Google, sign in, and enable Calendars.")
                    #else
                    Text("Canvas: Copy Calendar → Calendar Feed from your school’s Canvas. In Apple Calendar, open Calendars → Add Calendar → Add Subscription Calendar and paste the link.")
                    Text("Google: In Settings, add Google under Calendar accounts and enable Calendars for the account.")
                    #endif
                    Text("Return here, refresh, and select the new calendar. Canvas supplies assignments, quizzes, and exams that your instructor has published with a calendar date.")
                }.font(.callout).padding(.top, 6)
            }
        }.onAppear { agenda.refresh() }
    }
}

struct AgendaCard: View {
    @Environment(CalendarAgenda.self) private var agenda
    @Environment(NavigationState.self) private var navigation
    var compact = false
    @State private var showAll = false
    var body: some View {
        Card {
            Label("Upcoming calendar events", systemImage: "calendar.badge.clock").font(.title3.bold())
            if agenda.authorization != .fullAccess || agenda.selected.isEmpty {
                Button("Choose calendars in Settings") { navigation.destination = .settings }.buttonStyle(TargetButton())
            } else {
                if agenda.items.isEmpty {
                    Text("No upcoming events in the next 30 days from your selected calendars.").foregroundStyle(.secondary)
                }
                let limit = compact ? 3 : (showAll ? agenda.items.count : 15)
                ForEach(agenda.items.prefix(limit)) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title).font(.headline)
                        Text(item.date.formatted(date: .abbreviated, time: item.allDay ? .omitted : .shortened)
                             + (item.allDay ? " · All day" : "") + " · " + item.calendar)
                            .font(.caption).foregroundStyle(.secondary)
                    }.privacySensitive()
                }
                if !compact {
                    HStack {
                        if agenda.items.count > 15 {
                            Button(showAll ? "Show fewer" : "Show all \(agenda.items.count) events") { showAll.toggle() }
                        }
                        Button("Refresh") { agenda.refresh() }
                    }
                }
            }
        }
    }
}
