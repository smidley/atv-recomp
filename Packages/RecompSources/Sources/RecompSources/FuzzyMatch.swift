import Foundation

/// Ranks game titles against what someone types on a TV keyboard. Case, accents and punctuation
/// are ignored. Best first: the phrase at the start of the title, at the start of a later word, or
/// anywhere (spaces ignored); then every typed word at the start of a title word, allowing one typo
/// in words of four letters or more; then abbreviations whose letters start words in order ("sm64", "oot").
public struct FuzzySearch<Item> {
    private let entries: [(item: Item, title: Prepared)]

    /// Prepares every title once, so each query only compares.
    public init(_ items: [Item], title: (Item) -> String) {
        entries = items.map { ($0, Prepared(title($0))) }
    }

    /// Items whose title matches QUERY, best first; ties keep their order. An empty query keeps all.
    public func rank(_ query: String) -> [Item] {
        let typed = Query(query)
        guard !typed.words.isEmpty else { return entries.map(\.item) }
        return entries.enumerated()
            .compactMap { offset, entry in typed.score(entry.title).map { (item: entry.item, score: $0, offset: offset) } }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.offset < $1.offset }
            .map(\.item)
    }
}

public enum FuzzyMatch {
    /// ITEMS ranked by FuzzySearch; prepare a FuzzySearch instead to search one list repeatedly.
    public static func rank<T>(_ query: String, _ items: [T], by title: (T) -> String) -> [T] {
        FuzzySearch(items, title: title).rank(query)
    }

    /// Whether TITLE matches QUERY at all; an empty query matches everything.
    public static func matches(_ query: String, _ title: String) -> Bool {
        let typed = Query(query)
        return typed.words.isEmpty || typed.score(Prepared(title)) != nil
    }
}

// Titles and queries are compared as UTF-8 after folding case and accents: the same answers as
// comparing characters, and much cheaper.
private typealias Bytes = [UInt8]
private let space = UInt8(ascii: " ")

private func normalizedWords(_ text: String) -> [String] {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        .split { !$0.isLetter && !$0.isNumber }.map(String.init)
}

/// A title split into lowercase words, ready to compare.
private struct Prepared {
    let words: [Bytes]
    let text: Bytes
    let compact: Bytes

    init(_ title: String) {
        let parts = normalizedWords(title)
        words = parts.map { Array($0.utf8) }
        text = Array(parts.joined(separator: " ").utf8)
        compact = Array(parts.joined().utf8)
    }
}

private struct Query {
    let words: [Bytes]
    let phrase: Bytes
    let laterWord: Bytes
    let compact: Bytes

    init(_ query: String) {
        let parts = normalizedWords(query)
        words = parts.map { Array($0.utf8) }
        phrase = Array(parts.joined(separator: " ").utf8)
        laterWord = [space] + phrase
        compact = Array(parts.joined().utf8)
    }

    /// Higher is better; nil when the title doesn't match.
    func score(_ title: Prepared) -> Int? {
        let tier: Int
        if title.text.starts(with: phrase) {
            tier = 5
        } else if contains(title.text, laterWord) {
            tier = 4
        } else if contains(title.compact, compact) {
            tier = 3
        } else if words.allSatisfy({ typed in title.words.contains { $0.starts(with: typed) || typo(typed, $0) } }) {
            tier = 2
        } else if abbreviates(title.text) {
            tier = 1
        } else {
            return nil
        }
        // Within a tier, a shorter title is more of what was typed.
        return tier * 10_000 - min(title.text.count, 9_999)
    }

    /// One inserted, missing, wrong or swapped letter, compared with the whole word or, while the
    /// rest is still untyped, with its start.
    private func typo(_ typed: Bytes, _ word: Bytes) -> Bool {
        guard typed.count >= 4 else { return false }
        if abs(typed.count - word.count) <= 1, distance(typed, word) <= 1 { return true }
        return word.count > typed.count && distance(typed, Array(word[0..<typed.count])) <= 1
    }

    /// Each letter starts a later word of TEXT or continues the word of the letter before it.
    private func abbreviates(_ text: Bytes) -> Bool {
        let letters = compact
        guard !letters.isEmpty, letters.count <= 16 else { return false }
        func match(_ index: Int, _ position: Int) -> Bool {
            if index == letters.count { return true }
            if index > 0, position < text.count, text[position] == letters[index], match(index + 1, position + 1) {
                return true
            }
            var start = position
            while start < text.count {
                if text[start] == letters[index], start == 0 || text[start - 1] == space, match(index + 1, start + 1) {
                    return true
                }
                start += 1
            }
            return false
        }
        return match(0, 0)
    }
}

private func contains(_ text: Bytes, _ part: Bytes) -> Bool {
    guard !part.isEmpty else { return true }
    guard part.count <= text.count else { return false }
    search: for start in 0...(text.count - part.count) {
        for offset in 0..<part.count where text[start + offset] != part[offset] { continue search }
        return true
    }
    return false
}

/// Edit distance counting a swap of neighboring letters as one edit (optimal string alignment).
private func distance(_ a: Bytes, _ b: Bytes) -> Int {
    guard !a.isEmpty, !b.isEmpty else { return max(a.count, b.count) }
    let width = b.count + 1
    var rows = [Int](repeating: 0, count: (a.count + 1) * width)
    for i in 0...a.count { rows[i * width] = i }
    for j in 0...b.count { rows[j] = j }
    for i in 1...a.count {
        for j in 1...b.count {
            let cost = a[i - 1] == b[j - 1] ? 0 : 1
            var best = min(rows[(i - 1) * width + j] + 1, rows[i * width + j - 1] + 1, rows[(i - 1) * width + j - 1] + cost)
            if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                best = min(best, rows[(i - 2) * width + j - 2] + 1)
            }
            rows[i * width + j] = best
        }
    }
    return rows[a.count * width + b.count]
}
