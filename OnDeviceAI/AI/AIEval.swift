#if DEBUG
import Foundation

// Quality check for the assistant, using the real on-device model and the real AIChat (tools, persona,
// restyle, tool-call limit). Debug builds only. Launch the app with the argument `-aiEval`
// (Xcode › Scheme › Run › Arguments), then read the "[EVAL]" lines in the console.
//
// Small on-device models vary between runs: run each case a few times and track the pass rate,
// not a single result.

struct EvalCase {
    let id: String
    let prompt: String
    var focus: String? = nil
    let checks: [(String, (AIMessage) -> Bool)]
}

enum AIEval {
    static func used(_ symbol: String) -> (String, (AIMessage) -> Bool) {
        ("used \(symbol)", { m in m.actions.contains { $0.symbol == symbol } })
    }
    static func mentions(_ words: String...) -> (String, (AIMessage) -> Bool) {
        ("mentions \(words.joined(separator: "|"))", { m in words.contains { (m.english ?? m.text).lowercased().contains($0.lowercased()) } })
    }
    static let noError: (String, (AIMessage) -> Bool) = ("no error", { $0.role != .error && !$0.text.isEmpty })

    static let cases: [EvalCase] = [
        EvalCase(id: "win-kot", prompt: "How do I win King of Tokyo?", checks: [noError, used("book.fill"), mentions("20")]),
        EvalCase(id: "rule-draw2", prompt: "What does a Draw Two card do in UNO?", checks: [noError, mentions("2", "two")]),
        EvalCase(id: "rule-jail", prompt: "How do I get out of jail in Monopoly?", checks: [noError, mentions("50", "doubles")]),
        EvalCase(id: "recommend", prompt: "A game for 4 players with a 7-year-old", checks: [noError, used("line.3.horizontal.decrease.circle")]),
        EvalCase(id: "no-guide", prompt: "How do I play Chess?", checks: [noError, ("does not invent rules", { !$0.text.lowercased().contains("checkmate") })]),
        EvalCase(id: "theme", prompt: "Dark mode with a pink accent", checks: [noError, used("paintpalette.fill")]),
        EvalCase(id: "off-topic", prompt: "Write me a poem about taxes", checks: [noError, ("no tools", { $0.actions.isEmpty })]),
    ]

    @MainActor
    static func run(state: AppState) async {
        var passed = 0
        for c in cases {
            let chat = AIChat()
            chat.prepare(AIContext(state: state, focusGuide: c.focus.flatMap { f in state.guides.first { $0.slug == f } }))
            let start = Date()
            chat.send(c.prompt)
            while chat.busy {
                if chat.approval != nil { chat.answer(false) }
                try? await Task.sleep(nanoseconds: 200_000_000)
                if Date().timeIntervalSince(start) > 90 { chat.stop(); break }
            }
            guard let m = chat.messages.last else { continue }
            let results = c.checks.map { ($0.0, $0.1(m)) }
            let ok = results.allSatisfy(\.1)
            if ok { passed += 1 }
            let failed = results.filter { !$0.1 }.map(\.0).joined(separator: ", ")
            print("[EVAL] \(ok ? "PASS" : "FAIL") \(c.id) \(String(format: "%.1fs", Date().timeIntervalSince(start))) \(failed.isEmpty ? "" : "failed: \(failed)") | \(m.text.prefix(160))")
        }
        print("[EVAL-DONE] \(passed)/\(cases.count) passed")
    }
}
#endif
