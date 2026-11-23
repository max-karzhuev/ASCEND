import Foundation

enum HomePuzzles {
    static func topicConfig(_ subject: String) -> LearningConfig {
        var config = LearningConfig()
        config.subject = subject
        config.subtopic = "Short, self-contained reasoning puzzles with a surprising inference and a worked solution. Use multiple-choice or numerical answers."
        config.ability = "Curious learner with basic subject knowledge"
        config.count = 3
        return config
    }

    // Permanent set and question IDs let offline practice reuse the normal attempt and XP history.
    static func generalSets(day: String) -> [LearningSession] {
        sets.enumerated().map { offset, questions in
            var config = LearningConfig()
            config.subject = "General puzzles"
            config.subtopic = "Collection \(offset + 1)"
            config.count = questions.count
            var session = LearningSession(config: config, questions: questions, day: day, provider: "ASCEND", model: "Built-in")
            session.id = "ascend.general.v1.\(offset + 1)"
            return session
        }
    }

    private static func puzzle(_ id: String, _ topic: String, _ prompt: String, _ answer: String,
                               _ hint: String, _ explanation: String, options: [String] = []) -> Question {
        Question(id: id, kind: options.isEmpty ? .numerical : .multipleChoice, prompt: prompt,
                 options: options, answer: answer, tolerance: 0, hints: [hint], explanation: explanation, topic: topic)
    }

    private static let sets = [
        [
            puzzle("clock", "Time", "At 3:30, how many degrees are in the smaller angle between the clock hands?", "75", "The hour hand keeps moving between 3 and 4.", "The minute hand points at 180°. The hour hand is halfway between 90° and 120°, at 105°. Their difference is 75°."),
            puzzle("labels", "Deduction", "Three boxes are labeled Tea, Cocoa, and Mixed. Every label is wrong. Which box should you sample once to identify all three?", "Mixed", "Start with a label that rules out both drinks being present.", "The box labeled Mixed must contain just one drink, which your sample identifies. The box labeled with the other drink cannot contain that drink, so it must be mixed. The last box holds the remaining drink.", options: ["Tea", "Cocoa", "Mixed"]),
            puzzle("paths", "Counting", "Walk from one corner of a 3-by-2 block grid to the opposite corner using only east and north steps. How many routes are there?", "10", "Every route is a five-letter word with two N’s.", "Choose two of five positions for the north steps. There are 5 × 4 ÷ 2 = 10 choices.")
        ], [
            puzzle("socks", "Guarantees", "A drawer contains six socks of each of three colors. Drawing blind, how many socks guarantee three of the same color?", "7", "How many can you draw while still having only pairs?", "You could draw two of each color in six draws. Any seventh sock makes a triple."),
            puzzle("fold", "Spatial reasoning", "A cube is painted on all six faces, then cut into 27 equal cubes. How many small cubes have exactly two painted faces?", "12", "Think about the centers of the edges.", "Exactly two painted faces occur on an edge away from a corner. Each of the cube’s 12 edges contributes one small cube."),
            puzzle("coins", "Probability", "Two fair coins are tossed. You learn that at least one is heads. What is the probability both are heads?", "1/3", "List ordered outcomes before crossing out the impossible one.", "HH, HT, and TH remain equally likely. Only HH has two heads.", options: ["1/4", "1/3", "1/2", "2/3"])
        ], [
            puzzle("meeting", "Rates", "One cyclist rides a 12 km loop in 30 minutes. Another rides it in 20. Starting together in the same direction, in how many minutes does the faster rider first lap the other?", "60", "Work in laps per minute.", "The faster cyclist gains 1/20 − 1/30 = 1/60 of a lap each minute. Gaining a full lap takes 60 minutes."),
            puzzle("order", "Deduction", "Four runners finish with no ties. Noor beats Ari, Ari beats Lin, and Bo beats Noor. Who finishes third?", "Ari", "Put Bo and Lin at opposite ends of the ordering.", "The order is Bo, Noor, Ari, Lin. Ari finishes third.", options: ["Lin", "Ari", "Bo", "Noor"]),
            puzzle("pages", "Digits", "Number the pages of a booklet from 1 to 40. How many times do you write the digit 3?", "14", "Count tens positions separately from ones positions.", "There are ten 3s in the tens place on pages 30–39, and four in the ones place on 3, 13, 23, and 33. Both digits of 33 count.")
        ], [
            puzzle("tiles", "Geometry", "A rectangular garden has perimeter 26 m. Its sides have whole-number lengths. What is its largest possible area in square metres?", "42", "The two different side lengths add up to 13.", "With a fixed sum, moving the lengths closer together increases the product. The closest whole numbers are 6 and 7, giving 42 m²."),
            puzzle("cards", "Logic", "A card has a letter on one side and a number on the other. To test “Every vowel has an even number behind it,” which visible cards must you turn over: A, K, 4, 7?", "A and 7", "Look for a vowel paired with an odd number.", "Check A for an odd number and 7 for a vowel. K cannot break the rule, and 4 is allowed behind either kind of letter.", options: ["A only", "A and 4", "A and 7", "K and 7"]),
            puzzle("bridge", "Strategy", "Four hikers take 1, 2, 7, and 10 minutes to cross a bridge. At most two cross at once, at the slower person’s pace. Every crossing needs their single torch. What is the minimum total time in minutes?", "17", "Compare sending the two slow hikers together with escorting each separately.", "Send 1 and 2 (2 min), return 1 (1), send 7 and 10 (10), return 2 (2), then send 1 and 2 (2). Total 17. Sending the slow hikers separately with the fastest escort would take 21.")
        ]
    ]
}
