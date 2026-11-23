import XCTest
@testable import AscendCore

final class HomePuzzleTests: XCTestCase {
    func testAllOfflineQuestionsArePlayableAndStableAcrossDays() throws {
        let sets = HomePuzzles.generalSets(day: "2026-11-24")
        let tomorrow = HomePuzzles.generalSets(day: "2026-11-25")
        XCTAssertEqual(sets.map(\.id), tomorrow.map(\.id))
        XCTAssertEqual(sets.map(\.questions), tomorrow.map(\.questions))
        XCTAssertEqual(Set(sets.map(\.id)).count, 4)
        let questions = sets.flatMap(\.questions)
        XCTAssertEqual(Set(questions.map(\.id)).count, 12)
        for set in sets {
            try LearningRules.validate(set.questions, count: set.config.count)
            for question in set.questions {
                XCTAssertEqual(LearningRules.deterministic(question, answer: question.answer), true)
                XCTAssertEqual(LearningRules.deterministic(question, answer: "unrelated"), false)
            }
        }
    }

    func testCustomSubjectUsedForFeedAndOldSessionsDecode() throws {
        let config = HomePuzzles.topicConfig("Music theory")
        XCTAssertEqual(config.subject, "Music theory")
        XCTAssertEqual(config.count, 3)
        let original = try XCTUnwrap(HomePuzzles.generalSets(day: "2026-11-24").first)
        let data = try JSONEncoder().encode(original)
        let dictionary = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(dictionary["isHomePuzzleSet"])
        XCTAssertNil(try JSONDecoder().decode(LearningSession.self, from: data).isHomePuzzleSet)
    }
}
