import SwiftUI
import FoundationModels

// On-device board game assistant (Apple Foundation Models). Apple frameworks only, no third-party AI.
//
// One turn:
// 1. The prompt is always English (the on-device model is prompted in English).
// 2. Stage 1: a LanguageModelSession with tools streams a @Generable AIReply {mood, text}.
//    The mascot's persona is in the instructions.
// 3. Stage 2 (Indonesian only): the English answer is rewritten in casual Indonesian by a separate session.
//    The original English stays available under the answer.
//
// Guardrails: EVERY session uses Apple's default guardrails (SystemLanguageModel.Guardrails.default),
// written out explicitly through AIChat.model.
//
// Pre-routing: some requests are answered by app code before the model runs, because they must be exact
// ("what can you do?", typos in game names, "which of those is easiest?", switching language).

/// What a screen gives the assistant.
struct AIContext {
    let state: AppState
    let focusGuide: PlayGuide?
    var games: [Game] { state.games }
    var guides: [PlayGuide] { state.guides }
}

/// What the assistant is doing, for an informative "thinking" line.
enum AIStatus: Equatable { case thinking, catalog, rulebook, rules, theme, language }

/// One feature button (prompt nil = start the mic).
struct AIFeature: Identifiable, Hashable {
    var id: String { title }
    let symbol: String
    let title: String
    let detail: String
    let prompt: String?
}

/// Something a tool did, shown as a chip under the answer ("what the agent did").
struct AIAction: Identifiable {
    let id = UUID()
    let symbol: String
    let text: String
}

/// The look before a tool changed it, for the Undo button.
struct ThemeSnapshot { let accent: Accent; let appearance: Appearance }

/// A question waiting for the user. The tool call is suspended here until the user taps.
struct AIApproval: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let continuation: CheckedContinuation<Bool, Never>
}

struct AIMessage: Identifiable {
    enum Role { case user, assistant, error }
    let id = UUID()
    var role: Role
    var text: String
    var mood: Mood = .talk
    var links: [PlayGuide] = []
    var games: [Game] = []
    /// Number of matching games + filter summary, shown by the app above the cards.
    var matchCount: Int?
    var matchFilters = ""
    var actions: [AIAction] = []
    var undo: ThemeSnapshot?
    /// Original English answer (stage 1) when the text was rewritten in Indonesian.
    var english: String?
    var restyling = false
    var note: String?
    /// Example prompts the user can tap.
    var prompts: [String] = []
    /// Feature list as buttons (answer to "what can you do?").
    var features: [AIFeature] = []
}

// MARK: - Structured reply

@Generable
enum AIMood: String, CaseIterable {
    case happy, wink, smug, thinking, shock, talk
    var mood: Mood { Mood(rawValue: rawValue) ?? .talk }
}

/// mood comes first so the mascot's face changes while the text is still streaming.
@Generable
struct AIReply {
    @Guide(description: "The mascot's facial expression for this reply")
    var mood: AIMood
    @Guide(description: "The reply to the user")
    var text: String
}

// MARK: - Data summaries for the model (used by instructions & tools)

enum AIText {
    /// Guide summary, cut to fit the on-device model's context window.
    static func guide(_ g: PlayGuide, limit: Int) -> String {
        var out = "\(g.game)\n"
        out += "Intro: \(g.intro)\n"
        out += "Win: \(g.win.goal)\n" + g.win.keys.map { "- \($0)" }.joined(separator: "\n") + "\n"
        for (i, s) in g.sections.enumerated() {
            out += "\(i + 1). \(s.heading): " + (s.paragraphs + s.bullets).joined(separator: " ") + "\n"
        }
        if !g.tips.isEmpty { out += "Tips: " + g.tips.joined(separator: " | ") }
        return out.count > limit ? String(out.prefix(limit)) + "…" : out
    }

    static func game(_ g: Game, hasGuide: Bool) -> String {
        var parts = [g.name, "\(g.players), \(g.minutes), age \(g.age)", String(format: "weight %.1f/5", g.weight)]
        // Small models tend to invent rules for games that come from searchCatalog: mark it clearly.
        // The [note: …] form makes the model read it as a note for itself, not text to copy.
        parts.append(hasGuide ? "[note: has a guide; call readGuide before explaining rules]" : "[note: no guide; do not explain its rules]")
        return parts.joined(separator: " · ")
    }

    /// Game name first, then slug and keywords: "kot" → King of Tokyo.
    static func match(_ name: String, in guides: [PlayGuide]) -> PlayGuide? {
        let q = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return nil }
        if let g = guides.first(where: { $0.game.lowercased() == q }) { return g }
        if let g = guides.first(where: { $0.game.lowercased().contains(q) || q.contains($0.game.lowercased()) || $0.slug.contains(q.replacingOccurrences(of: " ", with: "-")) }) { return g }
        return guides.first { g in g.keywords.contains { k in k.count > 2 && (k.contains(q) || q.contains(k)) } }
    }
}

// MARK: - Tools (Foundation Models tool calling)
// Tools only forward to AIChat (@MainActor), which holds the data, the app state and the per-turn notes.

@Generable
enum Complexity: String, CaseIterable { case light, medium, heavy }

struct SearchCatalogTool: Tool {
    let name = "searchCatalog"
    let description = "Search the app's board game catalogue. Use it to recommend games, e.g. for kids, or to check players, play time, age, and whether a how-to-play guide exists. Pass only what the user mentioned."
    let chat: AIChat

    @Generable
    struct Arguments {
        @Guide(description: "Only a game name or a theme word that appears in game descriptions, e.g. 'monsters', 'cards', 'property'. Leave empty for descriptions like easy, fun, for kids or family; use the other fields instead.")
        var query: String?
        @Guide(description: "How many people will play", .range(1...12))
        var players: Int?
        @Guide(description: "Age in years of the youngest player", .range(3...18))
        var youngestAge: Int?
        @Guide(description: "The longest a game may take, in minutes", .range(5...240))
        var maxMinutes: Int?
        @Guide(description: "light = easy to learn, heavy = complex strategy")
        var complexity: Complexity?
    }

    func call(arguments: Arguments) async throws -> String { await chat.searchCatalog(arguments) }
}

struct ReadGuideTool: Tool {
    let name = "readGuide"
    let description = "Read the app's how-to-play guide for a game (setup, turns, how to win, tips). Always use this before explaining rules so you don't invent them."
    let chat: AIChat

    @Generable
    struct Arguments {
        @Guide(description: "The game name, e.g. 'UNO' or 'Monopoly'.")
        var game: String
    }

    func call(arguments: Arguments) async throws -> String { await chat.readGuide(arguments.game) }
}

/// RAG: keyword search (BM25) over rule passages, for specific rules questions.
struct SearchRulesTool: Tool {
    let name = "searchRules"
    let description = "Search the rule passages of all guides for a specific rules question (e.g. what a card or dice face does, jail, scoring). Pass precise rules terms."
    let chat: AIChat

    @Generable
    struct Arguments {
        @Guide(description: "1 to 5 precise rules terms, e.g. ['draw two', 'skip'] or ['jail', 'doubles'] or ['claw', 'tokyo', 'damage']", .count(1...5))
        var terms: [String]
    }

    func call(arguments: Arguments) async throws -> String { await chat.searchRules(arguments.terms) }
}

// Theme choices are @Generable enums: the model can only pick values that exist in the app.

@Generable
enum AppearanceChoice: String, CaseIterable { case light, dark, system }

@Generable
enum AccentChoice: String, CaseIterable { case yellow, orange, green, pink, blue }

struct ChangeThemeTool: Tool {
    let name = "changeTheme"
    let description = "Changes how the app looks. Pass only the parts the user wants to change."
    let chat: AIChat

    @Generable
    struct Arguments {
        @Guide(description: "light mode, dark mode, or follow the phone's setting")
        var appearance: AppearanceChoice?
        @Guide(description: "The highlight colour")
        var accent: AccentChoice?
    }

    func call(arguments: Arguments) async throws -> String { await chat.changeTheme(appearance: arguments.appearance, accent: arguments.accent) }
}

@Generable
enum LanguageChoice: String, CaseIterable { case english, indonesian }

/// Human in the loop: the tool suspends until the user approves or denies (see AIChat.askUser).
struct ChangeLanguageTool: Tool {
    let name = "changeLanguage"
    let description = "Changes the app's language and the language of your replies. The user is asked to approve first."
    let chat: AIChat

    @Generable
    struct Arguments { var language: LanguageChoice }

    func call(arguments: Arguments) async throws -> String { await chat.changeLanguage(arguments.language) }
}

// MARK: - Chat session

@MainActor
final class AIChat: ObservableObject {
    @Published var messages: [AIMessage] = []
    @Published var busy = false
    @Published private(set) var approval: AIApproval?
    /// Tokens used by this conversation (instructions, tool schemas, messages and tool results).
    @Published private(set) var usedTokens = 0
    /// Collected by tools during one turn (shown live as chips), then attached to the answer.
    @Published private(set) var turnActions: [AIAction] = []
    @Published private(set) var status: AIStatus = .thinking
    /// Chat currently shown (nil = new chat, not saved yet).
    @Published private(set) var currentChatID: UUID?

    /// The on-device model with Apple's default guardrails. Used by every assistant session.
    static let model = SystemLanguageModel(guardrails: .default)

    /// Context window size, re-read each time. Can be 0 while the model isn't ready: never use it raw,
    /// or `usedTokens > 0` would reset the session on every message and lose the context.
    var contextSize: Int { SystemLanguageModel.default.contextSize }
    private var knownContextSize: Int? { contextSize > 0 ? contextSize : nil }
    private var big: Bool { contextSize >= 8192 }
    var availability: SystemLanguageModel.Availability { SystemLanguageModel.default.availability }

    private var ctx: AIContext?
    private var session: LanguageModelSession?
    private var sessionKey = ""
    private var task: Task<Void, Never>?
    private lazy var rules = RulesSearch(guides: SampleData.guides)

    private var turnGuides: [PlayGuide] = []
    /// Tool calls this turn; capped so a small model doesn't loop forever.
    private var turnToolCalls = 0
    private let maxToolCalls = 6
    private var turnGames: [Game] = []
    private var turnMatchCount: Int?
    private var turnMatchFilters = ""
    private var turnRuleSearches: Set<String> = []
    private var turnPrompt = ""
    private var turnUndo: ThemeSnapshot?
    /// Last filter and games shown: used to refine and carried into a new session.
    private var lastFilter: GameFilter?
    private var lastShown: [String] = []
    /// Prompts the user confirmed are "not a typo": not asked again.
    private var typoSkip: Set<String> = []

    private var lang: AppLanguage { ctx?.state.language ?? .english }
    private var mascot: Mascot { ctx?.state.mascot ?? .a }

    func unavailableText(_ l: AppLanguage) -> String? {
        switch availability {
        case .available: return nil
        case .unavailable(.deviceNotEligible):
            return tx(l, "Perangkat ini belum mendukung Apple Intelligence.", "This device doesn't support Apple Intelligence.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return tx(l, "Aktifkan Apple Intelligence dulu di Pengaturan › Apple Intelligence & Siri.", "Turn on Apple Intelligence in Settings › Apple Intelligence & Siri.")
        case .unavailable(.modelNotReady):
            return tx(l, "Model AI sedang diunduh oleh sistem. Coba lagi sebentar lagi.", "The AI model is still downloading. Try again in a bit.")
        case .unavailable:
            return tx(l, "Apple Intelligence sedang tidak tersedia.", "Apple Intelligence isn't available right now.")
        }
    }

    private func key(_ ctx: AIContext) -> String { "\(ctx.state.mascot.rawValue)|\(ctx.focusGuide?.slug ?? "-")" }

    func prepare(_ ctx: AIContext) {
        self.ctx = ctx
        let k = key(ctx)
        guard k != sessionKey else { return }
        sessionKey = k
        // A session replaced mid-conversation (context full, persona changed) gets a summary,
        // so the user can keep refining earlier results. Reset clears messages first, so no summary then.
        session = LanguageModelSession(
            model: Self.model, // Apple's default guardrails
            tools: [SearchCatalogTool(chat: self), ReadGuideTool(chat: self), SearchRulesTool(chat: self), ChangeThemeTool(chat: self), ChangeLanguageTool(chat: self)],
            instructions: Self.instructions(ctx, big: big) + carryOverSummary()
        )
        usedTokens = 0
        session?.prewarm()
    }

    /// Summary for a new session: last 3 exchanges (English), active filter, games shown.
    private func carryOverSummary() -> String {
        let pairs = messages.filter { $0.role != .error && !$0.text.isEmpty }.suffix(6)
        guard !pairs.isEmpty else { return "" }
        var out = "\n\nConversation so far (continue from it; the user may refer to it):"
        for m in pairs {
            let t = (m.english ?? m.text).replacingOccurrences(of: "\n", with: " ")
            out += "\n- \(m.role == .user ? "User" : "You"): " + String(t.prefix(220))
        }
        if let f = lastFilter, f.isActive { out += "\nCurrent game search filters: \(f.summary)." }
        if !lastShown.isEmpty { out += "\nGames currently shown to the user: " + lastShown.joined(separator: ", ") + "." }
        return out
    }

    // MARK: Local chat history

    static func memoryKey(_ ctx: AIContext?) -> String { ctx?.focusGuide.map { "guide:\($0.slug)" } ?? "general" }

    /// Save the current chat (called after every answer).
    func remember() {
        guard let ctx else { return }
        let msgs: [ChatRecord.Msg] = messages.compactMap { m in
            guard m.role != .error, !m.text.isEmpty else { return nil }
            return ChatRecord.Msg(user: m.role == .user, text: m.text, english: m.english, games: m.games.map(\.name))
        }
        guard msgs.contains(where: { !$0.user }) else { return }
        let id = currentChatID ?? UUID()
        currentChatID = id
        ChatHistoryStore.shared.upsert(ChatRecord(id: id, focusKey: Self.memoryKey(ctx), gameName: ctx.focusGuide?.game, messages: msgs))
    }

    private func load(_ r: ChatRecord, _ ctx: AIContext) {
        currentChatID = r.id
        messages = r.messages.map { m in
            var a = AIMessage(role: m.user ? .user : .assistant, text: m.text, mood: .happy)
            a.english = m.english
            a.games = m.games.compactMap { n in ctx.games.first { $0.name == n } }
            return a
        }
        if let i = messages.indices.last { messages[i].note = tx(lang, "Lanjutan obrolan tersimpan", "Continuing a saved chat") }
    }

    /// The focused game changed: save this chat, load that game's latest chat.
    func switchTo(_ ctx: AIContext) {
        guard key(ctx) != sessionKey else { return }
        if !busy { remember() }
        stop()
        lastFilter = nil; lastShown = []
        messages = []; currentChatID = nil
        if let r = ChatHistoryStore.shared.latest(for: Self.memoryKey(ctx)) { load(r, ctx) }
        sessionKey = ""
        prepare(ctx)
    }

    func prepareRestoring(_ ctx: AIContext) {
        if messages.isEmpty, let r = ChatHistoryStore.shared.latest(for: Self.memoryKey(ctx)) { load(r, ctx) }
        prepare(ctx)
    }

    /// Open a chat from history. If it is about another game, move the focus first.
    func open(_ r: ChatRecord) {
        guard let ctx else { return }
        if !busy { remember() }
        stop(); lastFilter = nil; lastShown = []
        if r.focusKey != Self.memoryKey(ctx) {
            let slug = r.focusKey.hasPrefix("guide:") ? String(r.focusKey.dropFirst(6)) : nil
            ctx.state.askFocus = ctx.guides.first { $0.slug == slug }
        }
        let next = AIContext(state: ctx.state, focusGuide: ctx.guides.first { "guide:\($0.slug)" == r.focusKey })
        load(r, next)
        sessionKey = ""; prepare(next)
    }

    /// New chat: the old one stays in history.
    func reset() {
        if !busy { remember() }
        lastFilter = nil; lastShown = []
        stop()
        messages = []; currentChatID = nil
        sessionKey = ""
        if let ctx { prepare(ctx) }
    }

    func stop() {
        task?.cancel()
        if let a = approval { approval = nil; a.continuation.resume(returning: false) }
    }

    // MARK: Send

    func send(_ prompt: String) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy, let ctx else { return }
        // "?", "hmm", "test": no question. Ask back (no model).
        if Self.isContentFree(text) {
            messages.append(AIMessage(role: .user, text: text))
            messages.append(askBack(heard: true))
            return
        }
        // Misspelled game name: ask first, never guess silently.
        if !typoSkip.contains(text), let hit = GameTypo.find(in: text, focus: typoFocus(ctx), all: ctx.guides.map(\.game)) {
            messages.append(AIMessage(role: .user, text: text))
            var a = AIMessage(role: .assistant, text: tx(lang, "Maksudmu **\(hit.name)**? Kamu menulis “\(hit.typo)”. Ketuk yang benar:",
                                                         "Did you mean **\(hit.name)**? You wrote “\(hit.typo)”. Tap the right one:"), mood: .thinking)
            a.prompts = [hit.corrected, text]
            messages.append(a)
            typoSkip.insert(text)
            return
        }
        // "Which of those is easiest?": answered by the app from catalogue data (exact; guardrails can't block it).
        if Self.refersToShown(text), let answer = comparison(text) {
            messages.append(AIMessage(role: .user, text: text))
            var a = AIMessage(role: .assistant, text: answer.text, mood: .happy)
            a.games = answer.games
            a.note = tx(lang, "Dihitung app dari data katalog.", "Worked out by the app from catalogue data.")
            messages.append(a)
            lastShown = answer.games.map(\.name)
            remember()
            return
        }
        // "What can you do?": the feature list is built by the app (complete, accurate, instant).
        if Self.isHelpRequest(text) {
            messages.append(AIMessage(role: .user, text: text))
            messages.append(capabilities(ctx))
            return
        }
        // Nearly full? Start a new session now rather than fail mid-answer.
        if let size = knownContextSize, usedTokens > size * 3 / 4 { sessionKey = "" }
        prepare(ctx)
        messages.append(AIMessage(role: .user, text: text))
        messages.append(AIMessage(role: .assistant, text: "", mood: .thinking))
        let idx = messages.count - 1
        turnActions = []; turnGuides = []; turnGames = []; turnMatchCount = nil; turnMatchFilters = ""
        turnRuleSearches = []; turnPrompt = text; turnUndo = nil; turnToolCalls = 0; status = .thinking
        let modelPrompt = preRouteGuideName(text)
        busy = true
        task = Task {
            defer { busy = false; remember() }
            do {
                guard let session else { return }
                // Language switching is run by the app (with an approval card) before the model:
                // the small model sometimes refused "Switch the app to Indonesian" without calling the tool.
                var stagePrompt = modelPrompt
                if let l = Self.requestedLanguage(text) {
                    let result = await changeLanguage(l)
                    stagePrompt = "[Note from the app: the app handled the language request itself. Result: \(result) Confirm this to the user in one short English sentence; do not call changeLanguage.]\n\n" + text
                }
                // Stage 1: accurate answer in English with tools, streamed as AIReply.
                for try await snap in session.streamResponse(to: stagePrompt, generating: AIReply.self) {
                    if let t = snap.content.text { messages[idx].text = Self.stripNotes(t) }
                    if let m = snap.content.mood { messages[idx].mood = m.mood }
                }
                finish(idx)
                usedTokens = (try? await SystemLanguageModel.default.tokenCount(for: session.transcript)) ?? usedTokens
                // Stage 2: rewrite in the app language (read after tools ran, so it follows a new language).
                await restyle(idx)
            } catch is CancellationError {
                finish(idx)
            } catch let e as LanguageModelError {
                if case .contextSizeExceeded = e { sessionKey = "" } // fresh session on the next message
                #if DEBUG
                print("[AI-ERROR] \(e) | prompt=\(text)")
                #endif
                if let answer = comparisonFallback(e, prompt: text) {
                    messages[idx].text = answer.text
                    messages[idx].mood = .happy
                    turnGames = answer.games
                    lastShown = answer.games.map(\.name)
                } else if let g = guardrailFallbackGuide(e, prompt: text) {
                    // Guardrails stay on and are respected: the model doesn't answer. The app shows the guide's own
                    // text instead (game words like "smash" or "attack" sometimes trigger the filter).
                    messages[idx].text = tx(lang, "Ini cara menang dari panduan \(g.game) di app:", "Here's how to win from the \(g.game) guide in the app:")
                        + "\n\n" + g.win.goal + "\n" + g.win.keys.map { "• " + $0 }.joined(separator: "\n")
                    messages[idx].mood = .happy
                    if !turnGuides.contains(g) { turnGuides.append(g) }
                } else {
                    messages[idx].role = .error
                    messages[idx].text = Self.describe(e, lang)
                    messages[idx].mood = .shock
                }
                finish(idx)
            } catch {
                messages[idx].role = .error
                messages[idx].text = error.localizedDescription
                messages[idx].mood = .shock
                finish(idx)
            }
        }
    }

    /// Last safety net: drop tool notes ([note: …]) the model copied into its answer.
    static func stripNotes(_ t: String) -> String {
        t.replacingOccurrences(of: #"\s*[–—-]?\s*\[note:[^\]]*\]?"#, with: "", options: .regularExpression)
    }

    private func restyle(_ idx: Int) async {
        guard !lang.isEn, messages.indices.contains(idx), !Task.isCancelled else { return }
        let english = messages[idx].text
        guard !english.isEmpty else { return }
        messages[idx].restyling = true
        defer { messages[idx].restyling = false }
        do {
            // Apple's default guardrails. If blocked, the English answer stays, with a note and the Translate button.
            let writer = LanguageModelSession(
                model: Self.model,
                instructions: "You rewrite text into a requested style. Keep EVERY fact, number and step from the original; do not drop or add facts. Keep game names and the speaker's own name (\(mascot.name)) unchanged. Output only the rewritten text."
            )
            var styled = ""
            for try await snap in writer.streamResponse(to: "Style: casual, friendly spoken Indonesian (Bahasa Indonesia).\n\nRewrite this text in that style:\n\(english)") {
                styled = snap.content
            }
            guard !styled.isEmpty else { return }
            messages[idx].english = english
            messages[idx].text = Self.stripNotes(styled)
        } catch is CancellationError {
        } catch {
            messages[idx].note = "Couldn't rewrite in Indonesian; showing English."
        }
    }

    private func finish(_ idx: Int) {
        guard messages.indices.contains(idx), let ctx else { return }
        var m = messages[idx]
        m.actions = turnActions
        m.games = turnGames
        m.matchCount = turnMatchCount
        m.matchFilters = turnMatchFilters
        m.undo = turnUndo
        // Guides read by a tool or named in the answer (whole words) → "Open guide" buttons.
        let mentioned = ctx.guides.filter { g in
            m.text.range(of: "\\b" + NSRegularExpression.escapedPattern(for: g.game) + "\\b", options: [.regularExpression, .caseInsensitive]) != nil
        }
        m.links = (turnGuides + mentioned).reduce(into: [PlayGuide]()) { acc, g in
            if !acc.contains(g), g.slug != ctx.focusGuide?.slug, !turnGames.contains(where: { $0.name == g.game }) { acc.append(g) }
        }
        messages[idx] = m
    }

    // MARK: Pre-routing

    static func isHelpRequest(_ text: String) -> Bool {
        let t = text.lowercased()
        let patterns = [
            #"\b(what|which)\b.{0,20}\b(can|could)\b.{0,10}\b(you|u)\b.{0,15}\b(do|help)"#,
            #"\bhow\b.{0,10}\b(can|could)\b.{0,10}\byou\b.{0,10}\bhelp"#,
            #"\bwhat are your (features|abilities|skills)"#,
            #"\b(bisa apa|bisa ngapain|kamu bisa apa)\b"#, #"^\s*help\s*[?!.]*\s*$"#,
        ]
        return patterns.contains { t.range(of: $0, options: .regularExpression) != nil }
    }

    static func isContentFree(_ t: String) -> Bool {
        let words = t.lowercased().replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .split(separator: " ").map(String.init)
        let filler: Set<String> = ["um", "umm", "uh", "hmm", "hm", "mm", "eh", "ah", "er", "oh", "test", "testing"]
        return words.isEmpty || words.allSatisfy { filler.contains($0) }
    }

    /// Ask back when the prompt or the voice input was empty. `silent`: the mic heard no sound at all.
    func askBack(heard: Bool, silent: Bool = false) -> AIMessage {
        let text: String
        if silent {
            text = tx(lang, "Mic-nya nggak menangkap suara. Coba bicara lebih dekat, atau ketik pertanyaannya.", "The microphone didn't pick up any sound. Try speaking closer, or type your question.")
        } else if heard {
            text = tx(lang, "Hmm, mau tanya soal apa? Contohnya:", "Hmm, what would you like to ask? For example:")
        } else {
            text = tx(lang, "Aku nggak dengar apa-apa. Ketuk mic lalu bicara, atau coba ini:", "I didn't hear anything. Tap the mic and speak, or try one of these:")
        }
        var msg = AIMessage(role: .assistant, text: text, mood: .thinking)
        let g = ctx?.focusGuide?.game ?? "UNO"
        if !silent { msg.prompts = ["How do I win \(g)?", "A game for 4 players with a 7-year-old", "What can you do?"] }
        return msg
    }

    func voiceHeardNothing(silent: Bool) {
        guard !busy else { return }
        messages.append(askBack(heard: false, silent: silent))
    }

    private func capabilities(_ ctx: AIContext) -> AIMessage {
        let l = lang
        let game = ctx.focusGuide?.game ?? "King of Tokyo"
        let f: [AIFeature] = [
            AIFeature(symbol: "book.fill", title: tx(l, "Cara main & cara menang", "How to play & how to win"), detail: tx(l, "Dari panduan di app", "Straight from the app's guides"), prompt: "How do I win \(game)?"),
            AIFeature(symbol: "magnifyingglass", title: tx(l, "Tanya aturan spesifik", "Specific rules"), detail: tx(l, "Cari di potongan aturan (RAG)", "Searches rule passages (RAG)"), prompt: "What does a Draw Two card do?"),
            AIFeature(symbol: "line.3.horizontal.decrease.circle.fill", title: tx(l, "Rekomendasi game", "Game picks"), detail: tx(l, "Pemain, umur, durasi", "Players, ages, play time"), prompt: "A game for 4 players with a 7-year-old"),
            AIFeature(symbol: "paintpalette.fill", title: tx(l, "Ganti tampilan", "Look & colour"), detail: tx(l, "Terang/gelap, warna · bisa Undo", "Light/dark, colour · with Undo"), prompt: "Dark mode with a pink accent"),
            AIFeature(symbol: "globe", title: tx(l, "Ganti bahasa", "Language"), detail: tx(l, "Minta persetujuan dulu", "Asks you first"), prompt: l.isEn ? "Switch the app to Indonesian" : "Switch the app to English"),
            AIFeature(symbol: "mic.fill", title: tx(l, "Tanya pakai suara", "Ask by voice"), detail: tx(l, "Bicara, terkirim otomatis", "Talk, it sends when you stop"), prompt: nil),
            AIFeature(symbol: "speaker.wave.2.fill", title: tx(l, "Bacakan & terjemahkan", "Read aloud & translate"), detail: tx(l, "Tombol di bawah jawaban", "Buttons under each answer"), prompt: "How do you win UNO?"),
        ]
        var m = AIMessage(role: .assistant, text: tx(l, "Ini yang bisa aku bantu. Ketuk salah satu:", "Here's what I can help with. Tap one to try it:"), mood: .happy)
        m.features = f
        return m
    }

    /// Games being discussed: chat focus, games just shown, guides named in recent messages.
    private func typoFocus(_ ctx: AIContext) -> [String] {
        var out = [ctx.focusGuide?.game].compactMap { $0 } + lastShown
        for m in messages.suffix(6) { out += m.links.map(\.game) + m.games.map(\.name) }
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }

    /// "Of those", "which one", "dari yang tadi".
    static func refersToShown(_ t: String) -> Bool {
        t.lowercased().range(of: #"\b(of those|of these|from those|among (them|those|these)|which one|which of|of them|dari (itu|tadi|yang tadi)|yang tadi|mana yang)\b"#, options: .regularExpression) != nil
    }

    /// Rank the games just shown by the criterion in the question (catalogue data). nil = not a comparison.
    func comparison(_ prompt: String) -> (text: String, games: [Game])? {
        guard let ctx, !lastShown.isEmpty else { return nil }
        let games = lastShown.compactMap { n in ctx.games.first { $0.name == n } }
        guard games.count > 1 else { return nil }
        let t = prompt.lowercased()
        func has(_ p: String) -> Bool { t.range(of: p, options: .regularExpression) != nil }
        let sorted: [Game], label: String, value: (Game) -> String
        if has(#"\b(easiest|simplest|easy|simple|light|gampang|mudah)"#) {
            sorted = games.sorted { $0.weight < $1.weight }; label = tx(lang, "paling gampang", "easiest"); value = { String(format: "%.1f/5", $0.weight) }
        } else if has(#"\b(hardest|most complex|complex|heavy|susah|sulit)"#) {
            sorted = games.sorted { $0.weight > $1.weight }; label = tx(lang, "paling menantang", "most complex"); value = { String(format: "%.1f/5", $0.weight) }
        } else if has(#"\b(shortest|quickest|fastest|short|quick|singkat|cepat)"#) {
            sorted = games.sorted { $0.maxMinutes < $1.maxMinutes }; label = tx(lang, "paling singkat", "shortest"); value = { $0.minutes }
        } else if has(#"\b(youngest|kids?|child|anak|younger)"#) {
            sorted = games.sorted { $0.minAge < $1.minAge }; label = tx(lang, "paling cocok untuk anak", "best for younger kids"); value = { $0.age }
        } else { return nil }
        guard let top = sorted.first else { return nil }
        let list = sorted.map { "• \($0.name): \(value($0))" }.joined(separator: "\n")
        return (tx(lang, "Dari game tadi, yang \(label): \(top.name) (\(value(top))).", "Of those games, the \(label) is \(top.name) (\(value(top))).") + "\n" + list, sorted)
    }

    private func comparisonFallback(_ e: LanguageModelError, prompt: String) -> (text: String, games: [Game])? {
        switch e { case .guardrailViolation, .refusal: return comparison(prompt); default: return nil }
    }

    private func guardrailFallbackGuide(_ e: LanguageModelError, prompt: String) -> PlayGuide? {
        switch e { case .guardrailViolation, .refusal: break; default: return nil }
        guard let ctx else { return nil }
        let named = ctx.guides.first { g in
            prompt.range(of: "\\b" + NSRegularExpression.escapedPattern(for: g.game) + "\\b", options: [.regularExpression, .caseInsensitive]) != nil
        }
        return named ?? ctx.focusGuide
    }

    /// A prompt naming a game with a guide: tell the model which game is meant (small models sometimes
    /// answered about the focused game instead).
    private func preRouteGuideName(_ prompt: String) -> String {
        guard let ctx else { return prompt }
        let named = ctx.guides.filter { g in
            g.slug != ctx.focusGuide?.slug &&
                prompt.range(of: "\\b" + NSRegularExpression.escapedPattern(for: g.game) + "\\b", options: [.regularExpression, .caseInsensitive]) != nil
        }
        guard !named.isEmpty, named.count <= 2 else { return prompt }
        let names = named.map { "'\($0.game)'" }.joined(separator: " and ")
        return "[Note from the app: the user is asking about \(names), which has a guide in this app. Call readGuide for it before answering, and answer about that game.]\n\n" + prompt
    }

    /// "Switch the app to Indonesian", "change the language to English".
    static func requestedLanguage(_ text: String) -> LanguageChoice? {
        let t = text.lowercased()
        guard t.range(of: #"\b(switch|change|set|use|turn|put|make|speak|talk|ganti)\b"#, options: .regularExpression) != nil,
              t.range(of: #"\b(language|bahasa|speak|talk|in|to|ke)\b"#, options: .regularExpression) != nil else { return nil }
        if t.range(of: #"\b(indonesian|bahasa indonesia|indo)\b"#, options: .regularExpression) != nil { return .indonesian }
        if t.range(of: #"\b(english|inggris)\b"#, options: .regularExpression) != nil { return .english }
        return nil
    }

    /// "6 year old", "6-year-old", "6yo" → 6.
    static func childAge(in text: String) -> Int? {
        guard let r = text.range(of: #"\b(\d{1,2})[- ]?(year|yr|yo\b|tahun)"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return Int(text[r].prefix { $0.isNumber })
    }

    static func isRefinement(_ text: String) -> Bool {
        let t = text.lowercased()
        return [#"\b(only|just|those|these|them|ones|instead|also)\b"#,
                #"\b(under|less than|below|shorter|quicker|easier|harder|fewer|more)\b"#,
                #"^\s*(and|but|what about|how about|ok|now)\b"#].contains { t.range(of: $0, options: .regularExpression) != nil }
    }

    // MARK: Approval (the tool waits here until the user taps)

    private func askUser(title: String, detail: String) async -> Bool {
        await withCheckedContinuation { c in approval = AIApproval(title: title, detail: detail, continuation: c) }
    }

    func answer(_ approved: Bool) {
        guard let a = approval else { return }
        approval = nil
        a.continuation.resume(returning: approved)
    }

    // MARK: Tool implementations

    /// Add an action chip; identical chips never appear twice.
    private func act(_ symbol: String, _ text: String) {
        guard !turnActions.contains(where: { $0.text == text }) else { return }
        turnActions.append(AIAction(symbol: symbol, text: text))
    }

    /// nil = go ahead; otherwise a message telling the model to stop calling tools.
    private func toolBudget() -> String? {
        turnToolCalls += 1
        return turnToolCalls > maxToolCalls ? "Tool limit reached for this question. Do not call any more tools; answer the user now with what you have." : nil
    }

    func searchCatalog(_ a: SearchCatalogTool.Arguments) -> String {
        status = .catalog
        if let stop = toolBudget() { return stop }
        guard let ctx else { return "The catalogue isn't loaded." }
        // Refine: "only short ones" after "games for 4 players" keeps the old filters; new ones override.
        // Small models often pass only the new requirement and forget the earlier ones.
        let refining = lastFilter != nil && Self.isRefinement(turnPrompt)
        let base = refining ? (lastFilter ?? GameFilter()) : GameFilter()
        // The model sometimes forgets youngestAge although the question says "7-year-old": read it from the text.
        let age = a.youngestAge ?? Self.childAge(in: turnPrompt) ?? base.age
        let newQ = a.query?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        var f = GameFilter(query: newQ.isEmpty ? base.query : newQ, players: a.players ?? base.players, age: age,
                           maxMinutes: a.maxMinutes ?? base.maxMinutes, complexity: a.complexity?.rawValue ?? base.complexity)
        var hits = f.apply(games: ctx.games, guides: ctx.guides)
        var note = ""
        // Small models often put adjectives ("easy", "kids") in query: if that empties the result, drop it.
        if hits.isEmpty, !f.query.isEmpty, f.players != nil || age != nil || f.maxMinutes != nil || f.complexity != nil {
            note = "No game matched the word '\(f.query)', so these fit the other requirements:\n"
            f.query = ""
            hits = f.apply(games: ctx.games, guides: ctx.guides)
        }
        if refining { act("arrow.triangle.branch", "Refined: " + f.summary) }
        lastFilter = f
        turnGames = hits
        lastShown = hits.map(\.name)
        turnMatchCount = hits.count
        turnMatchFilters = f.summary
        act("line.3.horizontal.decrease.circle", "\(ctx.games.count) games searched · \(hits.count) fit")
        if hits.isEmpty { return "No matching games in the app catalogue. Suggest loosening one requirement." }
        let guideGames = Set(ctx.guides.map(\.game))
        return "\(hits.count) games fit. The app shows them as cards. The app has NO popularity or sales data, so never claim a game is the most popular.\n"
            + note + hits.map { g in
                var line = AIText.game(g, hasGuide: guideGames.contains(g.name))
                if let age, g.minAge > age { line += " · box says \(g.age): a \(age)-year-old can play with an adult's help" }
                return line
            }.joined(separator: "\n")
    }

    func readGuide(_ name: String) -> String {
        status = .rulebook
        if let stop = toolBudget() { return stop }
        guard let ctx else { return "The guides aren't loaded." }
        guard let g = AIText.match(name, in: ctx.guides) else {
            act("questionmark.circle", "No guide for “\(name)”")
            return "No guide for '\(name)' in the app. Do not describe its rules. Available guides: " + ctx.guides.map(\.game).joined(separator: ", ")
        }
        // Small models sometimes call the same tool again and again: break the loop.
        if turnGuides.contains(g) { return "You already read the \(g.game) guide above. Do not call readGuide again; answer the user now using it." }
        turnGuides.append(g)
        act("book.fill", "Read the \(g.game) guide")
        // Tool output uses the context window too: a bigger window allows a longer summary.
        return AIText.guide(g, limit: big ? 3300 : 1700)
    }

    func searchRules(_ terms: [String]) async -> String {
        status = .rules
        if let stop = toolBudget() { return stop }
        let key = terms.map { $0.lowercased() }.sorted().joined(separator: "|")
        guard turnRuleSearches.insert(key).inserted else { return "You already looked these terms up above. Answer now." }
        let r = rules.search(terms: terms, question: turnPrompt, maxChars: big ? 2400 : 1300)
        guard !r.text.isEmpty else {
            act("questionmark.circle", "No rule for “\(terms.joined(separator: ", "))”")
            return "No matching rule found. Tell the user you are not sure rather than guessing."
        }
        act("magnifyingglass", "Rules " + r.ids.prefix(3).joined(separator: ", "))
        return "Rule passages:\n\n" + r.text + "\n\n[Internal note for you only: answer only from these passages.]"
    }

    func changeTheme(appearance: AppearanceChoice?, accent: AccentChoice?) -> String {
        status = .theme
        if let stop = toolBudget() { return stop }
        guard let app = ctx?.state else { return "The app isn't ready." }
        let before = ThemeSnapshot(accent: app.accent, appearance: app.appearance)
        var done: [String] = []
        if let appearance, let a = Appearance(rawValue: appearance.rawValue), app.appearance != a {
            app.appearance = a; done.append("\(a.rawValue) mode")
        }
        if let accent, let a = Accent(rawValue: accent.rawValue), app.accent != a {
            app.accent = a; done.append("a \(a.rawValue) accent")
        }
        // Repeated call with values already active: no chip, no Undo, and ask the model to stop.
        guard !done.isEmpty else { return "Nothing changed: the app already looks like that. Do not call changeTheme again; just answer." }
        if turnUndo == nil { turnUndo = before }
        let summary = done.joined(separator: ", ")
        act("paintpalette.fill", "Switched to \(summary)")
        return "The app now uses \(summary)."
    }

    func undoTheme(_ snap: ThemeSnapshot) {
        guard let app = ctx?.state else { return }
        app.accent = snap.accent
        app.appearance = snap.appearance
    }

    func changeLanguage(_ language: LanguageChoice) async -> String {
        status = .language
        if let stop = toolBudget() { return stop }
        guard let app = ctx?.state else { return "The app isn't ready." }
        let l: AppLanguage = language == .english ? .english : .indonesian
        if l == app.language { return "The app is already in \(l.label)." }
        act("hourglass", "Asked you before switching to \(l.label)")
        let ok = await askUser(title: tx(lang, "Ganti bahasa ke \(l.label)?", "Switch the app to \(l.label)?"),
                               detail: tx(lang, "Aplikasi dan jawaban asisten akan memakai \(l.label).", "The app and the assistant's answers will use \(l.label)."))
        guard ok else {
            act("hand.raised.fill", "You said no")
            return "The user declined. The language was NOT changed."
        }
        app.language = l
        act("globe", "Language: \(l.label)")
        return "The app is now in \(l.label). Confirm in one short English sentence."
    }

    // MARK: Text

    private static func describe(_ e: LanguageModelError, _ l: AppLanguage) -> String {
        switch e {
        case .contextSizeExceeded:
            return tx(l, "Percakapan terlalu panjang. Tanya lagi ya, aku mulai halaman baru.", "The conversation got too long, so I started a fresh one. Please ask again.")
        case .guardrailViolation, .refusal:
            return tx(l, "Filter keamanan Apple menghentikan jawaban ini (kadang terlalu hati-hati dengan istilah game seperti “serang”). Coba tanya dengan kata lain.",
                      "Apple's on-device safety filter stopped this answer (it's sometimes over-cautious with game words like “attack” or “smash”). Try asking another way.")
        case .unsupportedLanguageOrLocale:
            return tx(l, "Tulis pertanyaannya dalam bahasa Inggris ya.", "Please write your question in English.")
        case .rateLimited, .timeout:
            return tx(l, "Sebentar ya, coba tanya lagi.", "Give me a moment and ask again.")
        default:
            return e.localizedDescription
        }
    }

    /// Stage 1 instructions: always English.
    private static func instructions(_ ctx: AIContext, big: Bool) -> String {
        var s = """
        \(ctx.state.mascot.persona)
        The user writes in English. Families and children use this app, so always be kind. Keep answers short (under 120 words); simple steps or bullet points are fine.
        Always use your tools:
        - How to play or how to win a game: call readGuide, then answer only from what it returns. Never invent rules; if the app has no guide, say so.
        - A specific rules question (what a card, dice face or space does): call searchRules with precise terms and answer only from the passages.
        - Recommending games (for kids, a group size, a time limit): call searchCatalog and mention only games it returns. When the user narrows earlier results, call searchCatalog again with just the new requirement; the app keeps the earlier filters. If a game's box age is up to two years above the child's age, say the child can play with an adult's help. Text in [note: …] is for you only: never copy it into your answer.
        - Changing the app's look (dark or light mode, colour): call changeTheme.
        - Changing the app's language: call changeLanguage.
        Only say something happened if a tool result says it did.
        Only talk about board games, playing together and this app. Politely decline other topics.
        """
        if let g = ctx.focusGuide {
            s += "\n\nThe user is currently reading this guide in the app:\n" + AIText.guide(g, limit: big ? 2500 : 1500)
        }
        return s
    }
}
