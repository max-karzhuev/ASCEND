import Foundation

enum ArithmeticOperation: String, Codable, CaseIterable {
    case addition = "+", subtraction = "−", multiplication = "×", division = "÷"

    var name: String {
        switch self {
        case .addition: "Addition"
        case .subtraction: "Subtraction"
        case .multiplication: "Multiplication"
        case .division: "Division"
        }
    }
}

struct OperandBounds: Codable, Equatable {
    var low: Int
    var high: Int

    func fits(_ bounds: ClosedRange<Int>) -> Bool {
        bounds.contains(low) && bounds.contains(high) && low <= high
    }
}

struct MentalMathSettings: Codable, Equatable {
    static let durations = [5, 10, 15, 30, 60, 120, 300, 600]
    var seconds = 120
    var operations = Set(ArithmeticOperation.allCases)
    var addLeft = OperandBounds(low: 2, high: 100)
    var addRight = OperandBounds(low: 2, high: 100)
    var factorLeft = OperandBounds(low: 2, high: 12)
    var factorRight = OperandBounds(low: 2, high: 100)

    var isValid: Bool {
        Self.durations.contains(seconds) && !operations.isEmpty &&
        addLeft.fits(0...999) && addRight.fits(0...999) &&
        factorLeft.fits(1...999) && factorRight.fits(1...999)
    }

    var symbols: String { ArithmeticOperation.allCases.filter(operations.contains).map(\.rawValue).joined(separator: "  ") }
}

struct MentalMathProblem: Equatable {
    let left: Int
    let operation: ArithmeticOperation
    let right: Int
    let solution: Int

    fileprivate static func draw(_ settings: MentalMathSettings) -> Self {
        // The round validates the immutable settings before its first draw.
        let op = settings.operations.randomElement()!
        let additive = op == .addition || op == .subtraction
        let first = additive ? settings.addLeft : settings.factorLeft
        let second = additive ? settings.addRight : settings.factorRight
        let a = Int.random(in: first.low...first.high)
        let b = Int.random(in: second.low...second.high)
        switch op {
        case .addition: return Self(left: a, operation: op, right: b, solution: a + b)
        case .subtraction: return Self(left: a + b, operation: op, right: a, solution: b)
        case .multiplication: return Self(left: a, operation: op, right: b, solution: a * b)
        case .division: return Self(left: a * b, operation: op, right: a, solution: b)
        }
    }
}

struct MentalMathRound {
    let settings: MentalMathSettings
    let deadline: ContinuousClock.Instant
    private(set) var problem: MentalMathProblem
    private(set) var score = 0

    init?(settings: MentalMathSettings, now: ContinuousClock.Instant = .now) {
        guard settings.isValid else { return nil }
        self.settings = settings
        deadline = now.advanced(by: .seconds(settings.seconds))
        problem = .draw(settings)
    }

    func remaining(at now: ContinuousClock.Instant = .now) -> Int {
        guard now < deadline else { return 0 }
        let parts = now.duration(to: deadline).components
        return min(settings.seconds, Int(parts.seconds) + (parts.attoseconds > 0 ? 1 : 0))
    }

    mutating func accept(_ input: String, at now: ContinuousClock.Instant = .now) -> Bool {
        guard now < deadline, !input.isEmpty, input.utf8.allSatisfy({ (48...57).contains($0) }),
              Int(input) == problem.solution else { return false }
        score += 1
        problem = .draw(settings)
        return true
    }
}

struct MentalMathRecord: Codable {
    struct Result: Codable {
        let score: Int
        let seconds: Int
    }
    var settings = MentalMathSettings()
    var last: Result?
}
