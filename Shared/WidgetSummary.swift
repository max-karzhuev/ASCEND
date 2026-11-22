#if os(macOS)
import Foundation
import Darwin

struct WidgetSummary: Codable, Equatable {
    static let kind = "ASCEND.Today"
    static let tasksKind = "ASCEND.Tasks"
    static let calendarKind = "ASCEND.Calendar"
    static var location: URL? {
        if let group = Bundle.main.object(forInfoDictionaryKey: "ASCENDWidgetGroup") as? String,
              !group.isEmpty {
            return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
                .appendingPathComponent("desktop-summary.json")
        }
        // A locally signed Mac build shares only this folder via narrowly scoped sandbox entitlements.
        guard let home = getpwuid(getuid())?.pointee.pw_dir else { return nil }
        return URL(fileURLWithPath: String(cString: home), isDirectory: true)
            .appendingPathComponent("Library/Application Support/ASCEND Desktop Widget/desktop-summary.json")
    }
    var theme: Theme
    var level: Int
    var xp: Int
    var target: Int
    var planned: Int
    var completed: Int
    var expires: Date
    // Optional so widgets can read summaries written by earlier app versions.
    var pendingTitles: [String]?
    var pendingCount: Int?
    var month: String?
    var days: [Day]?

    struct Day: Codable, Equatable {
        var date: String
        var number: Int
        var planned: Int
        var completed: Int
        var intensity: Double
        var inMonth: Bool
        var isToday: Bool
    }
}
#endif
