import SwiftUI
import FoundationModels
import NaturalLanguage
import Translation

// "Translate" under an answer, shown only when the answer's language differs from the app language.
// Apple frameworks only:
//   - NaturalLanguage: detects the answer's language.
//   - FoundationModels: translates (main path). More natural, keeps the casual tone, streamed.
//   - Translation: fallback when the model is unavailable, fails, or drifts.

extension AppLanguage {
    var nl: NLLanguage { isEn ? .english : .indonesian }
    var translationTarget: Locale.Language { Locale.Language(identifier: isEn ? "en" : "id") }
}

enum AITranslate {
    /// The answer's language if it differs from the app language and detection is confident; nil = no button.
    static func foreignLanguage(of text: String, lang: AppLanguage) -> NLLanguage? {
        guard text.count >= 20 else { return nil }
        let r = NLLanguageRecognizer()
        r.languageConstraints = [.english, .indonesian, .malay]
        r.processString(text)
        guard let (l, p) = r.languageHypotheses(withMaximum: 1).first, p >= 0.8 else { return nil }
        // Malay is often confused with Indonesian: treat them as the same.
        let found: NLLanguage = l == .malay ? .indonesian : l
        return found == lang.nl ? nil : found
    }

    /// "term → translation" plus "only if it appears in the text" stopped the model from pasting the glossary
    /// into its output in our tests; a plain list sometimes leaked.
    static func instructions(to lang: AppLanguage) -> String {
        if lang.isEn {
            return """
            Translate the user's text from Indonesian into natural, friendly English. Output only the translated text, nothing else.
            Keep game names and board game terms as they are. Never add sentences, lists or words that are not in the original.
            """
        }
        return """
        Translate the user's text from English into natural, casual Indonesian (pakai "kamu"). Output only the translated text, nothing else.
        Glossary, used only when the word appears in the text:
        deck → deck; discard pile → discard pile; draw pile → draw pile; victory points → victory points; wild card → wild card; \
        token → token; dice → dice; roll the dice → lempar dice; draw a card → ambil kartu; shuffle → kocok; deal → bagikan.
        Keep game names as they are. Never add sentences, lists or words that are not in the original.
        """
    }

    /// Output much longer than the input almost certainly contains invented additions.
    static func looksWrong(_ out: String, from input: String) -> Bool {
        Double(out.count) > Double(input.count) * 1.6 + 40
    }
}

@Generable
struct AITranslation {
    @Guide(description: "The translation only")
    var translation: String
}

// MARK: - Board game terms

/// Common terms stay in English (deck, discard pile, …). Without this, the Translation framework
/// turned "deck" into "dadu" (dice) and "roll the dice" into "gulung dadu" in our tests.
enum BoardGameGlossary {
    /// Nouns that are not translated. Longest first so "discard pile" wins over "discard".
    static let keep = [
        "discard pile", "draw pile", "victory points", "victory point", "wild card", "game board",
        "deck", "token", "meeple", "dice", "card game", "board game",
    ].sorted { $0.count > $1.count }

    /// Fixes for EN → ID output (both paths). Case-insensitive.
    static let fixesToIndonesian: [(String, String)] = [
        ("poin kemenangan", "victory points"), ("kartu liar", "wild card"), ("tumpukan buangan", "discard pile"),
        ("gulir dice", "lempar dice"), ("gulung dice", "lempar dice"), ("lempar dadu", "lempar dice"),
        ("gambar kartu", "ambil kartu"), ("menggambar kartu", "mengambil kartu"), ("Anda", "kamu"),
    ]

    static func fix(_ s: String) -> String {
        var out = s
        for (a, b) in fixesToIndonesian { out = out.replacingOccurrences(of: a, with: b, options: .caseInsensitive) }
        if let f = out.first, f.isLowercase { out = f.uppercased() + out.dropFirst() }
        return out
    }

    /// For the Translation framework: replace terms with X0Q, X1Q… markers that pass through unchanged.
    static func protect(_ s: String) -> (String, [String]) {
        var out = s
        var kept: [String] = []
        for t in keep {
            guard let re = try? NSRegularExpression(pattern: "\\b\(NSRegularExpression.escapedPattern(for: t))\\b", options: .caseInsensitive) else { continue }
            while let m = re.firstMatch(in: out, range: NSRange(out.startIndex..., in: out)), let r = Range(m.range, in: out) {
                kept.append(String(out[r]))
                out.replaceSubrange(r, with: "X\(kept.count - 1)Q")
            }
        }
        return (out, kept)
    }

    static func restore(_ s: String, _ kept: [String]) -> String {
        var out = s
        for (i, k) in kept.enumerated().reversed() { out = out.replacingOccurrences(of: "X\(i)Q", with: k) }
        return fix(out)
    }
}

// MARK: - Button

struct AITranslateButton: View {
    @Environment(\.pal) private var p
    @Environment(\.lang) private var lang
    let text: String

    @State private var source: NLLanguage?
    @State private var translated = ""
    @State private var showing = false
    @State private var busy = false
    @State private var failed = false
    /// Set only when falling back to the Translation framework; .translationTask then runs.
    @State private var fallback: TranslationSession.Configuration?

    var body: some View {
        Group {
            if source != nil {
                VStack(alignment: .leading, spacing: 8) {
                    if showing, !translated.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tx(lang, "Terjemahan", "Translation")).font(.caption.weight(.bold)).foregroundStyle(p.ink2)
                            Text(translated).font(.subheadline)
                        }
                        .padding(10)
                        .background(p.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    SmallButton(busy ? "hourglass" : "character.bubble", label) { tap() }
                        .disabled(busy)
                        .accessibilityHint(tx(lang, "Terjemahan di perangkat", "On-device translation"))
                    if failed {
                        Text(tx(lang, "Terjemahan belum tersedia di perangkat ini.", "Translation isn't available on this device.")).font(.caption).foregroundStyle(p.ink2)
                    }
                }
            }
        }
        .task(id: text + lang.rawValue) {
            source = AITranslate.foreignLanguage(of: text, lang: lang)
            translated = ""; showing = false; failed = false; fallback = nil
        }
        // Fallback. .translationTask also shows the download prompt if the translation model isn't installed.
        .translationTask(fallback) { session in
            await translateWithTranslationFramework(session)
        }
    }

    private var label: String {
        if showing { return tx(lang, "Sembunyikan terjemahan", "Hide translation") }
        return tx(lang, "Terjemahkan ke Bahasa Indonesia", "Translate to English")
    }

    private func tap() {
        if !translated.isEmpty, !busy { showing.toggle(); return }
        busy = true
        failed = false
        Task { await translateWithFoundationModels() }
    }

    /// Main path: streamed, so the translation appears word by word.
    private func translateWithFoundationModels() async {
        guard SystemLanguageModel.default.availability == .available else { return useFallback() }
        let session = LanguageModelSession(model: AIChat.model, instructions: AITranslate.instructions(to: lang)) // Apple's default guardrails
        do {
            showing = true
            let stream = session.streamResponse(to: text, generating: AITranslation.self, options: GenerationOptions(temperature: 0.3))
            for try await snap in stream {
                if let t = snap.content.translation { translated = t }
            }
            if AITranslate.looksWrong(translated, from: text) { return useFallback() }
            if !lang.isEn { translated = BoardGameGlossary.fix(translated) }
            busy = false
        } catch {
            // e.g. LanguageModelError.unsupportedLanguageOrLocale.
            useFallback()
        }
    }

    private func useFallback() {
        translated = ""
        guard let source else { busy = false; failed = true; return }
        let c = TranslationSession.Configuration(source: Locale.Language(identifier: source.rawValue), target: lang.translationTarget)
        if fallback == c { fallback?.invalidate() } else { fallback = c }
    }

    private func translateWithTranslationFramework(_ session: TranslationSession) async {
        defer { busy = false }
        let toID = !lang.isEn
        let (input, kept) = toID ? BoardGameGlossary.protect(text) : (text, [])
        do {
            let r = try await session.translate(input)
            translated = toID ? BoardGameGlossary.restore(r.targetText, kept) : r.targetText
            showing = true
        } catch {
            failed = true
        }
    }
}
