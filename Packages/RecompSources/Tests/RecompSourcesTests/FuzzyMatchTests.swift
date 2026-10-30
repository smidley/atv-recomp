import Testing
@testable import RecompSources

private let titles = ["The Legend of Zelda: Ocarina of Time", "Mario Kart 64", "Star Fox 64", "Super Mario 64",
                      "Paper Mario", "Banjo-Kazooie", "Pokémon Stadium"]

private func best(_ query: String) -> String? {
    FuzzyMatch.rank(query, titles, by: { $0 }).first
}

@Test func searchFindsAbbreviationsTyposAndWordsInAnyOrder() {
    #expect(best("sm64") == "Super Mario 64")
    #expect(best("oot") == "The Legend of Zelda: Ocarina of Time")
    #expect(best("zelda") == "The Legend of Zelda: Ocarina of Time")
    #expect(best("kart mario") == "Mario Kart 64")
    #expect(best("mraio kart") == "Mario Kart 64")
    #expect(best("zeldaa") == "The Legend of Zelda: Ocarina of Time")
    #expect(best("starfox") == "Star Fox 64")
    #expect(best("banjo kazooie") == "Banjo-Kazooie")
    #expect(best("pokemon") == "Pokémon Stadium")
    #expect(FuzzyMatch.rank("xyz", titles, by: { $0 }).isEmpty)
}

@Test func searchRanksWholeWordsAboveScatteredLetters() {
    // "mario" starts one title and a later word in two others, the shorter title first.
    #expect(FuzzyMatch.rank("mario", titles, by: { $0 }) == ["Mario Kart 64", "Paper Mario", "Super Mario 64"])
    // An empty query keeps the library's own order.
    #expect(FuzzyMatch.rank("  ", titles, by: { $0 }) == titles)
}

@Test func searchStaysFastForLargeLibraries() {
    let genres = ["Adventure", "Racing", "Puzzle", "Quest", "Party", "Sports"]
    let library = (0..<10_000).map { "Game \($0) \(genres[$0 % genres.count]) Deluxe" } + ["Super Mario 64"]
    // The index is built once per library; each keystroke only ranks.
    let search = FuzzySearch(library, title: { $0 })
    let clock = ContinuousClock()
    var results = [String]()
    let elapsed = clock.measure { for query in ["s", "sm", "sm6", "sm64"] { results = search.rank(query) } }
    #expect(results.first == "Super Mario 64")
    #if DEBUG
    let budget = Duration.seconds(3) // unoptimized test builds run many times slower than the app
    #else
    let budget = Duration.milliseconds(100)
    #endif
    #expect(elapsed < budget, "four keystrokes over 10,000 titles took \(elapsed)")
}
