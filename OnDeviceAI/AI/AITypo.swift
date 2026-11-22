import UIKit

/// Detects a misspelled game name in the prompt ("how to play Uon" while talking about UNO).
/// It never corrects silently: the assistant asks "Did you mean UNO?" and the user taps the right one.
enum GameTypo {
    struct Hit: Equatable { let typo: String; let name: String; let corrected: String }

    /// Levenshtein distance (case-insensitive).
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a.lowercased()), b = Array(b.lowercased())
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var d = Array(0...b.count)
        for i in 1...a.count {
            var prev = d[0]; d[0] = i
            for j in 1...b.count {
                let tmp = d[j]
                d[j] = min(d[j] + 1, d[j - 1] + 1, prev + (a[i - 1] == b[j - 1] ? 0 : 1))
                prev = tmp
            }
        }
        return d[b.count]
    }

    private static func norm(_ s: String) -> String {
        s.lowercased().folding(options: .diacriticInsensitive, locale: nil).filter { $0.isLetter || $0.isNumber }
    }

    /// Correctly spelled English words (e.g. "club") are not treated as typos of a game name.
    @MainActor private static func isRealWord(_ w: String) -> Bool {
        let checker = UITextChecker()
        let r = checker.rangeOfMisspelledWord(in: w, range: NSRange(location: 0, length: (w as NSString).length), startingAt: 0, wrap: false, language: "en_US")
        return r.location == NSNotFound
    }

    /// `focus`: games being discussed (looser threshold). `all`: every game with a guide (strict threshold).
    @MainActor static func find(in text: String, focus: [String], all: [String]) -> Hit? {
        let tokens = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !tokens.isEmpty else { return nil }
        let lowerText = norm(text)
        let allNorm = Set(all.map(norm) + focus.map(norm))

        func scan(_ names: [String], strict: Bool) -> Hit? {
            for name in names {
                let n = norm(name)
                guard n.count >= 3, !lowerText.contains(n) else { continue } // already spelled right
                let words = max(1, name.split(separator: " ").count)
                guard words <= tokens.count else { continue }
                for i in 0...(tokens.count - words) {
                    let chunk = tokens[i..<(i + words)].joined(separator: " ")
                    let c = norm(chunk)
                    guard c.count >= 3, !allNorm.contains(c) else { continue } // another correctly spelled game
                    let d = distance(c, n)
                    let limit = strict ? (n.count >= 9 ? 2 : (n.count >= 5 ? 1 : 0)) : (n.count >= 7 ? 2 : 1)
                    guard d > 0, d <= limit, abs(c.count - n.count) <= limit else { continue }
                    if strict, words == 1, isRealWord(c) { continue }
                    // Keep trailing punctuation ("Uon?" → "UNO?").
                    let trailing = String(chunk.reversed().prefix { $0.isPunctuation }.reversed())
                    var out = tokens
                    out.replaceSubrange(i..<(i + words), with: [name + trailing])
                    return Hit(typo: chunk.trimmingCharacters(in: .punctuationCharacters), name: name, corrected: out.joined(separator: " "))
                }
            }
            return nil
        }
        return scan(focus, strict: false) ?? scan(all, strict: true)
    }
}
