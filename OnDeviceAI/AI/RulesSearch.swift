import Foundation

// On-device RAG with BM25.
//
// The on-device model has a small context window (a few thousand tokens), far smaller than a full rulebook.
// So the rulebook is not "memorised": the model writes the relevant rules terms as a tool argument, and
// RulesSearch scores every rule passage with BM25 (weighted keywords) and returns only the top passages.
//
// In our tests, keyword search with terms chosen by the model found exact rules better than semantic search
// with NLEmbedding (which also took much longer to index). Here the "rulebook" is built from the sample guides;
// point `passages` at your own rules text (e.g. a JSON file in the bundle) for a real game.

final class RulesSearch: @unchecked Sendable {
    struct Passage { let id: String; let game: String; let title: String; let text: String }
    struct Result { let ids: [String]; let text: String }

    private let passages: [Passage]
    private var docTokens: [[String: Int]] = []
    private var docLength: [Int] = []
    private var docFreq: [String: Int] = [:]
    private var avgLength = 1.0

    private static let stop: Set<String> = ["the", "a", "an", "of", "to", "in", "is", "it", "and", "or", "if", "that", "this", "be", "by", "for", "on", "with", "as", "are", "its", "at", "from", "can", "does", "do", "what", "how", "when", "i", "my", "you"]

    static func tokens(_ s: String) -> [String] {
        s.lowercased().split { !($0.isLetter || $0.isNumber) }.map(String.init).filter { !stop.contains($0) }
    }

    init(guides: [PlayGuide]) {
        var p: [Passage] = []
        for g in guides {
            p.append(Passage(id: "\(g.slug)#win", game: g.game, title: "How to win", text: ([g.win.goal] + g.win.keys).joined(separator: " ")))
            for (i, s) in g.sections.enumerated() {
                p.append(Passage(id: "\(g.slug)#\(i + 1)", game: g.game, title: s.heading, text: (s.paragraphs + s.bullets).joined(separator: " ")))
            }
        }
        passages = p
        // The game name and section title are indexed too, so "uno skip" finds the UNO action-card passage.
        for t in p.map({ "\($0.game) \($0.title) \($0.title) \($0.text)" }) {
            var tf: [String: Int] = [:]
            let toks = Self.tokens(t)
            for w in toks { tf[w, default: 0] += 1 }
            docTokens.append(tf); docLength.append(toks.count)
            for w in tf.keys { docFreq[w, default: 0] += 1 }
        }
        avgLength = Double(docLength.reduce(0, +)) / Double(max(1, docLength.count))
    }

    /// `terms` come from the model (full weight); `question` is the user's own text (weight 0.6),
    /// so results don't depend entirely on the small model's choice of terms.
    func search(terms: [String], question: String = "", limit: Int = 4, maxChars: Int = 1800) -> Result {
        var weights: [String: Double] = [:]
        for w in Self.tokens(question) { weights[w] = max(weights[w] ?? 0, 0.6) }
        for w in Self.tokens(terms.joined(separator: " ")) { weights[w] = 1.0 }
        let q = Array(weights.keys)
        guard !q.isEmpty else { return Result(ids: [], text: "") }
        let n = Double(docTokens.count)
        var scores: [(Double, Int)] = []
        for (i, tf) in docTokens.enumerated() {
            var s = 0.0
            let len = Double(docLength[i])
            for w in q {
                guard let f = tf[w], let df = docFreq[w] else { continue }
                let idf = log(1 + (n - Double(df) + 0.5) / (Double(df) + 0.5))
                s += (weights[w] ?? 1) * idf * Double(f) * 2.2 / (Double(f) + 1.2 * (0.25 + 0.75 * len / avgLength))
            }
            if s > 0 { scores.append((s, i)) }
        }
        scores.sort { $0.0 > $1.0 }
        var ids: [String] = [], out: [String] = [], used = 0
        for (_, i) in scores.prefix(limit) {
            let p = passages[i]
            let line = "[\(p.id)] \(p.game) – \(p.title): \(p.text)"
            guard used + line.count <= maxChars || ids.isEmpty else { continue }
            ids.append(p.id); out.append(line); used += line.count
        }
        return Result(ids: ids, text: out.joined(separator: "\n\n"))
    }
}
