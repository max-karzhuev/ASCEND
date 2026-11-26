import SwiftUI
import Observation
#if os(iOS)
import HealthKit
#endif

@MainActor @Observable final class HealthService {
    var enabled = false
    var busy = false
    var updatedAt: Date?
    var status = "Connect Apple Health to see your daily movement and sleep."
    var values: [String: Double] = [:]
    var hidden: Set<String> = []
    private var refreshID = UUID()
    #if os(iOS)
    private let healthStore = HKHealthStore()
    var available: Bool { HKHealthStore.isHealthDataAvailable() }
    #else
    var available: Bool { false }
    #endif
    func configure(store: AppStore) {
        enabled = store.metadataString("healthEnabled") == "true"
        hidden = []
        if let data = store.metadata("healthHidden"), let saved = try? JSONDecoder().decode(Set<String>.self, from: data) { hidden = saved }
    }
    func connect(store: AppStore) async {
        guard available, !busy else { return }
        busy = true
        #if os(iOS)
        do {
            let types: Set<HKObjectType> = [HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned), HKQuantityType(.distanceWalkingRunning), HKCategoryType(.sleepAnalysis)]
            try await healthStore.requestAuthorization(toShare: [], read: types)
            // Completion means the permission sheet finished, not that read access was granted.
            try store.setMetadata("healthEnabled", string: "true"); enabled = true; busy = false
            await refresh(store: store)
        } catch { busy = false; status = "Couldn’t connect: \(error.localizedDescription)" }
        #else
        busy = false
        #endif
    }
    func disconnect(store: AppStore) {
        do {
            try store.setMetadata("healthEnabled", string: "false")
            refreshID = UUID(); enabled = false; busy = false; values = [:]; updatedAt = nil
            status = "Disconnected in ASCEND. You can also revoke access in the Health app."
        } catch { store.error = error.localizedDescription }
    }
    func toggleMetric(_ key: String, store: AppStore) {
        var next = hidden
        if !next.insert(key).inserted { next.remove(key) }
        do { try store.setMetadata("healthHidden", data: JSONEncoder().encode(next)); hidden = next }
        catch { store.error = error.localizedDescription }
    }
    func refresh(store: AppStore) async {
        guard enabled, available, !busy else { return }
        busy = true; let id = UUID(); refreshID = id
        #if os(iOS)
        let now = Date(), start = store.planning.calendar.startOfDay(for: Date())
        var result: [String: Double] = [:], failures: [String] = []
        let quantities: [(String, HKQuantityTypeIdentifier, HKUnit)] = [
            ("steps", .stepCount, .count()), ("energy", .activeEnergyBurned, .kilocalorie()),
            ("distance", .distanceWalkingRunning, .meter())
        ]
        for (key, type, unit) in quantities {
            do { result[key] = try await quantity(type, unit: unit, start: start, end: now) }
            catch { failures.append(key) }
        }
        do { result["sleep"] = try await sleep(start: now.addingTimeInterval(-24 * 3600), end: now) }
        catch { failures.append("sleep") }
        guard id == refreshID, enabled else { return }
        values = result; updatedAt = now; busy = false
        status = failures.isEmpty ? "Missing values may mean there’s no data or read access is off. Manage access in the Health app." : "Couldn’t refresh \(failures.joined(separator: ", ")). Unlock your device and retry."
        #else
        busy = false
        #endif
    }
    #if os(iOS)
    private func quantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date) async throws -> Double? {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: HKQuantityType(identifier), quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate), options: .cumulativeSum) { _, statistics, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: unit)) }
            }
            healthStore.execute(query)
        }
    }
    private func sleep(start: Date, end: Date) async throws -> Double? {
        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKCategoryType(.sleepAnalysis), predicate: HKQuery.predicateForSamples(withStart: start, end: end), limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples as? [HKCategorySample] ?? []) }
            }
            healthStore.execute(query)
        }
        let asleep = Set([HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, HKCategoryValueSleepAnalysis.asleepCore.rawValue, HKCategoryValueSleepAnalysis.asleepDeep.rawValue, HKCategoryValueSleepAnalysis.asleepREM.rawValue])
        let intervals = samples.filter { asleep.contains($0.value) }.map { DateInterval(start: $0.startDate, end: $0.endDate) }
        guard !intervals.isEmpty else { return nil }
        return HealthIntervals.duration(intervals, within: DateInterval(start: start, end: end)) / 3600
    }
    #endif
}
struct HealthCard: View {
    @Environment(AppStore.self) private var store
    @Environment(HealthService.self) private var health
    @State private var showingSettings = false
    var body: some View {
        Card {
            HStack {
                Label("Apple Health", systemImage: "heart.fill").font(.title3.bold())
                Spacer()
                Button { showingSettings = true } label: { Image(systemName: "slider.horizontal.3") }.buttonStyle(TargetButton()).accessibilityLabel("Customize health widget")
            }
            if health.available {
                if health.enabled {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 115))], spacing: 12) {
                        if !health.hidden.contains("steps") { metric("Steps", key: "steps", icon: "figure.walk", unit: "today") }
                        if !health.hidden.contains("sleep") { metric("Sleep", key: "sleep", icon: "moon.zzz", unit: "hours · last 24h") }
                        if !health.hidden.contains("energy") { metric("Active energy", key: "energy", icon: "flame", unit: "kcal · today") }
                        if !health.hidden.contains("distance") { metric("Distance", key: "distance", icon: "point.topleft.down.to.point.bottomright.curvepath", unit: "km · today") }
                    }
                    if health.hidden.count >= 4 { Text("Choose metrics in the widget settings.").font(.subheadline).foregroundStyle(Palette.muted) }
                    HStack {
                        if let updated = health.updatedAt { Text("Updated \(updated, style: .time)").font(.caption).foregroundStyle(Palette.muted) }
                        Spacer()
                        Button { Task { await health.refresh(store: store) } } label: { Label("Refresh", systemImage: "arrow.clockwise") }.buttonStyle(TargetButton()).disabled(health.busy)
                    }
                    Text(health.status).font(.caption).foregroundStyle(Palette.muted)
                } else {
                    Text("Bring your steps, sleep, active energy and walking/running distance into your day.").font(.subheadline).foregroundStyle(Palette.muted)
                    Button { Task { await health.connect(store: store) } } label: { Label("Connect Apple Health", systemImage: "heart").frame(maxWidth: .infinity) }.buttonStyle(AccentButton(color: store.profile.theme.accent)).disabled(health.busy)
                    if health.status.hasPrefix("Couldn’t") { Text(health.status).font(.caption).foregroundStyle(.orange) }
                }
                if health.busy { ProgressView("Reading Health…").font(.caption) }
                Text("Apple Watch and other compatible devices sync through Apple Health. Health values stay on this device and aren’t sent to chat or ASCEND’s sync history.").font(.caption).foregroundStyle(Palette.muted)
            } else {
                Image(systemName: "applewatch").font(.system(size: 36, weight: .light)).foregroundStyle(store.profile.theme.accent).frame(maxWidth: .infinity)
                Text("Connect on your iPhone").font(.headline)
                Text("Open this widget in ASCEND on iPhone and allow Apple Health access. Your Apple Watch shares steps and sleep through the Health app. Apple Health readings aren’t available in the Mac app.").font(.subheadline).foregroundStyle(Palette.muted)
            }
        }.sheet(isPresented: $showingSettings) {
            NavigationStack {
                PageScroll {
                    Card {
                        Text("Choose the metrics you see").font(.headline)
                        ForEach(["steps", "sleep", "energy", "distance"], id: \.self) { key in
                            Toggle(key == "energy" ? "Active energy" : key.capitalized, isOn: Binding(get: { !health.hidden.contains(key) }, set: { _ in health.toggleMetric(key, store: store) })).frame(minHeight: 44)
                        }
                    }
                    if health.enabled {
                        Button("Disconnect from ASCEND") { health.disconnect(store: store) }.buttonStyle(TargetButton())
                        Text("To change or revoke permissions, open Health → your profile → Apps → ASCEND. Read permissions are managed by Apple Health.").font(.caption).foregroundStyle(Palette.muted)
                    }
                }.navigationTitle("Health widget")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingSettings = false }.buttonStyle(TargetButton()) } }
            }.editorFrame().preferredColorScheme(.dark)
        }
    }
    func metric(_ title: String, key: String, icon: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(Palette.muted)
            Text(formatted(key)).font(.title2.bold().monospacedDigit()).foregroundStyle(store.profile.theme.accent)
            Text(unit).font(.caption2).foregroundStyle(Palette.muted)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(13).background(Palette.background, in: RoundedRectangle(cornerRadius: 12))
    }
    func formatted(_ key: String) -> String {
        guard let value = health.values[key] else { return "—" }
        if key == "distance" { return (value / 1000).formatted(.number.precision(.fractionLength(1))) }
        if key == "sleep" { return value.formatted(.number.precision(.fractionLength(1))) }
        return value.formatted(.number.precision(.fractionLength(0)))
    }
}
