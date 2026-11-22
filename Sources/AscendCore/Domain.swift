import Foundation

public enum Difficulty: String, Codable, CaseIterable, Sendable { case easy, medium, hard
    public var xp: Int { switch self { case .easy: 10; case .medium: 25; case .hard: 50 } }
}
public enum Schedule: String, Codable, CaseIterable, Sendable { case once, daily, weekdays, weekly }
public enum GoalKind: String, Codable, CaseIterable, Sendable { case numeric, milestones }
public enum QuestionKind: String, Codable, CaseIterable, Sendable { case multipleChoice, numerical, conceptual, proof, programming }
public enum SessionMode: String, Codable, CaseIterable, Sendable { case practice, assessment }

public struct Profile: Codable, Equatable, Sendable {
    public var name = ""
    public var theme: Theme = .shadow
    public var timeZone = TimeZone.current.identifier
    public var startedDay = ""
    public var onboarded = false
    public var reducedMotion = false
    public var reminderDevice = ""
    public var dailyCheckIn = false
    public var brainReminder = false
    public var subjects = ["Mathematics", "Statistics", "Macroeconomics", "Physics", "Programming"]
    public init() {}
}
public struct Category: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var archived = false
    public init(id: String = UUID().uuidString, name: String) { self.id = id; self.name = name }
    public static let defaults = ["Knowledge", "Strength", "Discipline", "Craft"].map { Category(id: $0.lowercased(), name: $0) }
}
public struct Quest: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID().uuidString
    public var title = ""
    public var notes = ""
    public var category = "knowledge"
    public var difficulty: Difficulty = .medium
    public var schedule: Schedule = .daily
    public var weekdays: [Int] = [2, 3, 4, 5, 6]
    public var weeklyTarget = 3
    public var startDay = ""
    public var deadline = ""
    public var reminderMinutes: Int? = nil
    public var goalID = ""
    public var contribution: Double = 1
    public var archived = false
    public init() {}
}
public struct QuestRevision: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID().uuidString
    public var quest: Quest
    public var effectiveDay: String
    public var changedFields: [String: String]?
    public init(quest: Quest, effectiveDay: String, changedFields: [String: String]? = nil) { self.quest = quest; self.effectiveDay = effectiveDay; self.changedFields = changedFields }
}
public struct Occurrence: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var templateID: String
    public var day: String
    public var timeZone: String
    public var quest: Quest
    public var planned: Bool
    public var available: Bool
    public var weeklySlot: Int?
    public init(quest: Quest, day: String, timeZone: String, planned: Bool, available: Bool, weeklySlot: Int? = nil, week: String? = nil) {
        templateID = quest.id; self.day = day; self.timeZone = timeZone; self.quest = quest
        self.planned = planned; self.available = available; self.weeklySlot = weeklySlot
        if let weeklySlot { id = "\(quest.id)|week|\(week ?? day)|\(weeklySlot)" }
        else if quest.schedule == .once { id = "\(quest.id)|once" }
        else { id = "\(quest.id)|day|\(day)" }
    }
}
public struct Completion: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var active: Bool
    public var occurrenceID: String
    public var day: String
    public var xp: Int
    public var category: String
    public var goalID: String
    public var amount: Double
    public var title: String
    public init(occurrence: Occurrence, active: Bool = true, day: String? = nil) {
        id = occurrence.id; occurrenceID = occurrence.id; self.active = active
        self.day = day ?? occurrence.day; xp = occurrence.quest.difficulty.xp
        category = occurrence.quest.category; goalID = occurrence.quest.goalID
        amount = occurrence.quest.contribution; title = occurrence.quest.title
    }
}
public struct Milestone: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID().uuidString
    public var title: String
    public var weight: Double = 1
    public init(title: String, weight: Double = 1) { self.title = title; self.weight = weight }
}
public struct Goal: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID().uuidString
    public var title = ""
    public var notes = ""
    public var category = "discipline"
    public var kind: GoalKind = .numeric
    public var target: Double = 40
    public var unit = "sessions"
    public var targetDay = ""
    public var milestones: [Milestone] = []
    public var archived = false
    public init() {}
}
public struct Contribution: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID().uuidString
    public var goalID: String
    public var amount: Double
    public var day: String
    public var note: String
    public init(goalID: String, amount: Double, day: String, note: String) {
        self.goalID = goalID; self.amount = amount; self.day = day; self.note = note
    }
}
public struct MilestoneCheck: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var goalID: String
    public var done: Bool
}
public struct TimeZoneTransition: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID().uuidString
    public var timeZone: String
    public var effectiveAt: Date
    public init(timeZone: String, effectiveAt: Date) { self.timeZone = timeZone; self.effectiveAt = effectiveAt }
}
public struct LearningConfig: Codable, Equatable, Sendable {
    public var subject = "Mathematics"
    public var subtopic = ""
    public var ability = "Foundations"
    public var difficulty: Difficulty = .medium
    public var count = 5
    public var mode: SessionMode = .practice
    public init() {}
}
public struct Question: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: QuestionKind
    public var prompt: String
    public var options: [String]
    public var answer: String
    public var tolerance: Double
    public var hints: [String]
    public var explanation: String
    public var topic: String
}
public struct LearningSession: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID().uuidString
    public var config: LearningConfig
    public var questions: [Question]
    public var day: String
    public var provider: String
    public var model: String
    public init(config: LearningConfig, questions: [Question], day: String, provider: String, model: String) {
        self.config = config; self.questions = questions; self.day = day; self.provider = provider; self.model = model
    }
}
public struct Attempt: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var sessionID: String
    public var questionID: String
    public var answer = ""
    public var hintsUsed = 0
    public var submitted = false
    public var correct: Bool? = nil
    public var feedback = ""
    public var pendingGrade = false
    public var reported = false
    public var report = ""
    public var day: String
    public var mode: SessionMode
    public init(session: LearningSession, question: Question, day: String) {
        id = "\(session.id)|\(question.id)"; sessionID = session.id; questionID = question.id
        self.day = day; mode = session.config.mode
    }
}
