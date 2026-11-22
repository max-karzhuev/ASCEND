import CloudKit
import Observation

@MainActor @Observable final class CloudSync {
    var status = "Local mode · saved on this device"
    var working = false
    var lastExchange: Date?
    var pendingCount = 0
    private var observer: NSObjectProtocol?
    private var scheduled: Task<Void, Never>?
    private let store: AppStore
    private let zoneID = CKRecordZone.ID(zoneName: "ASCENDHistory", ownerName: CKCurrentUserDefaultName)
    var containerID: String { Bundle.main.object(forInfoDictionaryKey: "ASCENDCloudContainer") as? String ?? "" }
    var configured: Bool { containerID.hasPrefix("iCloud.") }
    init(store: AppStore) {
        self.store = store
        if let date = store.metadataString("lastExchange").flatMap(Double.init) { lastExchange = Date(timeIntervalSince1970: date) }
        observer = NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.scheduled?.cancel()
                self?.status = "Apple Account changed · sync paused; reconnect in Settings"
                self?.store.perform { try self?.store.setMetadata("syncEnabled", string: "false") }
            }
        }
    }
    func changed() {
        pendingCount = (try? store.pending().count) ?? 0
        guard store.syncEnabled, !working else { return }
        if pendingCount > 0 { status = "\(pendingCount) changes waiting for cloud exchange" }
        scheduled?.cancel(); scheduled = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }; await self?.sync()
        }
    }
    func enable() async {
        guard configured else { status = "iCloud is not configured in this build. See the signing guide."; return }
        store.perform { try store.setMetadata("syncEnabled", string: "true") }
        await sync()
    }
    func disable() { scheduled?.cancel(); store.perform { try store.setMetadata("syncEnabled", string: "false") }; status = "Local mode · cloud exchange paused" }
    func sync() async {
        guard configured, store.syncEnabled, !working else { return }
        working = true; status = "Checking Apple Account…"
        defer { working = false; pendingCount = (try? store.pending().count) ?? 0 }
        let container = CKContainer(identifier: containerID), database = CKContainer(identifier: containerID).privateCloudDatabase
        do {
            guard try await container.accountStatus() == .available else { throw DataError.invalid("iCloud unavailable. Your changes remain saved locally.") }
            let account = try await container.userRecordID().recordName
            if let bound = store.metadataString("cloudAccount"), bound != account {
                try store.setMetadata("syncEnabled", string: "false")
                throw DataError.invalid("A different Apple Account is signed in. This history stays isolated. Export it, then use Clear local data before connecting the new account.")
            }
            let firstConnection = store.metadataString("cloudAccount") == nil
            if firstConnection {
                _ = try await database.save(CKRecordZone(zoneID: zoneID))
                try store.setMetadata("cloudAccount", string: account)
            }
            status = "Receiving cloud changes…"
            var token = try store.metadata("cloudToken").flatMap { try NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0) }
            var incoming: [Change] = []
            var retriedToken = false
            while true {
                do {
                    let page = try await database.recordZoneChanges(inZoneWith: zoneID, since: token, resultsLimit: 200)
                    guard page.deletions.isEmpty else { throw DataError.invalid("Cloud history was changed outside ASCEND. Sync is paused to prevent restoring removed records. Export local data before recovery.") }
                    for result in page.modificationResultsByID.values {
                        let record = try result.get().record
                        guard record.recordType == "AscendOperation", let data = record["payload"] as? Data, data.count <= 250_000 else { throw DataError.invalid("Unsupported cloud record") }
                        let change = try JSONDecoder().decode(Change.self, from: data)
                        guard change.id == record.recordID.recordName else { throw DataError.invalid("Cloud identity mismatch") }
                        incoming.append(change)
                    }
                    token = page.changeToken
                    if !page.moreComing { break }
                } catch let error as CKError where error.code == .changeTokenExpired && !retriedToken {
                    token = nil; incoming = []; retriedToken = true
                }
            }
            guard try await container.userRecordID().recordName == account, store.syncEnabled else { throw DataError.invalid("Account changed during exchange; no incoming data was applied") }
            if let token { try store.receive(incoming, token: NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)) }
            try store.reconcile()
            let pending = try store.pending()
            status = "Sending \(pending.count) changes…"
            for start in stride(from: 0, to: pending.count, by: 100) {
                try Task.checkCancellation()
                guard store.syncEnabled, try await container.userRecordID().recordName == account else { throw DataError.invalid("Account changed; uploads paused") }
                let batch = Array(pending[start..<min(start + 100, pending.count)])
                let records = batch.map { row -> CKRecord in
                    let r = CKRecord(recordType: "AscendOperation", recordID: CKRecord.ID(recordName: row.id, zoneID: zoneID))
                    r["payload"] = row.payload as CKRecordValue; return r
                }
                let result = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: false)
                var uploaded = Set<String>()
                var failure: Error?
                for (id, outcome) in result.saveResults {
                    switch outcome {
                    case .success: uploaded.insert(id.recordName)
                    case .failure(let error):
                        if let e = error as? CKError, e.code == .serverRecordChanged,
                           let server = e.serverRecord, let remote = server["payload"] as? Data,
                           let local = batch.first(where: { $0.id == id.recordName }),
                           try JSONDecoder().decode(Change.self, from: remote) == JSONDecoder().decode(Change.self, from: local.payload) {
                            uploaded.insert(id.recordName)
                        } else { failure = error }
                    }
                }
                try store.markUploaded(uploaded)
                if let failure { throw failure }
            }
            lastExchange = Date(); try store.setMetadata("lastExchange", string: String(lastExchange!.timeIntervalSince1970))
            status = "Cloud exchange complete · other devices update on their next exchange"
        } catch {
            if let e = error as? CKError, e.code == .zoneNotFound || e.code == .userDeletedZone {
                store.perform { try store.setMetadata("syncEnabled", string: "false") }
                status = "Cloud zone was removed. Sync paused to prevent stale restoration. Export before clearing local data."
            } else { status = "Sync paused · \(error.localizedDescription)" }
        }
    }
}
