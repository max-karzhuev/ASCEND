import XCTest
@testable import AscendCore

final class MentalMathTests: XCTestCase {
    func testDefaultTwoMinuteMixedRound() throws {
        let settings = MentalMathSettings()
        XCTAssertEqual(settings.seconds, 120)
        XCTAssertEqual(settings.operations, Set(ArithmeticOperation.allCases))
        let start = ContinuousClock.now
        let round = try XCTUnwrap(MentalMathRound(settings: settings, now: start))
        XCTAssertEqual(round.remaining(at: start), 120)
        XCTAssertEqual(round.remaining(at: start + .milliseconds(119_999)), 1)
        XCTAssertEqual(round.remaining(at: start + .seconds(120)), 0)
        XCTAssertEqual(round.remaining(at: start + .seconds(500)), 0)
    }

    func testDirectAndInverseOperationsHonorBothOperandRanges() throws {
        var settings = MentalMathSettings()
        settings.addLeft = .init(low: 8, high: 8)
        settings.addRight = .init(low: 5, high: 5)
        settings.factorLeft = .init(low: 3, high: 3)
        settings.factorRight = .init(low: 7, high: 7)
        for (op, lhs, rhs, result) in [(ArithmeticOperation.addition,8,5,13), (.subtraction,13,8,5), (.multiplication,3,7,21), (.division,21,3,7)] {
            settings.operations = [op]
            let round = try XCTUnwrap(MentalMathRound(settings: settings))
            XCTAssertEqual(round.problem, MentalMathProblem(left: lhs, operation: op, right: rhs, solution: result))
        }
    }

    func testWrongAndIncompleteInputKeepsQuestionAndDeadline() throws {
        var settings = MentalMathSettings()
        settings.operations = [.multiplication]
        settings.factorLeft = .init(low: 9, high: 9)
        settings.factorRight = .init(low: 8, high: 8)
        let start = ContinuousClock.now
        var round = try XCTUnwrap(MentalMathRound(settings: settings, now: start))
        let problem = round.problem
        for input in ["", "7", "70", "72x", "-72", "72.0"] {
            XCTAssertFalse(round.accept(input, at: start))
            XCTAssertEqual(round.problem, problem)
            XCTAssertEqual(round.score, 0)
        }
        XCTAssertTrue(round.accept("72", at: start + .seconds(1)))
        XCTAssertEqual(round.score, 1)
        XCTAssertEqual(round.deadline, start + .seconds(120))
        XCTAssertFalse(round.accept("72", at: round.deadline))
        XCTAssertFalse(round.accept("72", at: start + .seconds(121)))
        XCTAssertEqual(round.score, 1)
    }

    func testInvalidRangesOperationsAndDurationsCannotStart() {
        var settings = MentalMathSettings()
        settings.operations = []
        XCTAssertNil(MentalMathRound(settings: settings))
        settings.operations = [.division]
        settings.factorLeft = .init(low: 0, high: 2)
        XCTAssertNil(MentalMathRound(settings: settings))
        settings.factorLeft = .init(low: 7, high: 6)
        XCTAssertNil(MentalMathRound(settings: settings))
        settings.factorLeft = .init(low: 1, high: .max)
        XCTAssertNil(MentalMathRound(settings: settings))
        settings = MentalMathSettings()
        settings.seconds = -5
        XCTAssertNil(MentalMathRound(settings: settings))
    }

    func testZeroAsARealAnswerAndRestartResetsScore() throws {
        var settings = MentalMathSettings()
        settings.operations = [.subtraction]
        settings.addRight = .init(low: 0, high: 0)
        var round = try XCTUnwrap(MentalMathRound(settings: settings))
        XCTAssertFalse(round.accept(""))
        XCTAssertTrue(round.accept("0"))
        let restarted = try XCTUnwrap(MentalMathRound(settings: settings))
        XCTAssertEqual(restarted.score, 0)
    }
}
