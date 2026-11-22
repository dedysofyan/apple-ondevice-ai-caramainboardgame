# On-device AI board game assistant (Apple Foundation Models)

A small SwiftUI sample app for iOS 27: a board game rules assistant that runs **entirely on device** with
Apple Intelligence. There are no servers, API keys or third-party AI services. It ships with three
example games (King of Tokyo, UNO, Monopoly) and three placeholder mascots.

## What it shows

| Topic | Where |
|---|---|
| `LanguageModelSession` with Apple's default guardrails, streaming, `prewarm()` | `AI/AIAssistant.swift` |
| Structured output with `@Generable` / `@Guide` (mascot mood + text, streamed) | `AIReply` in `AIAssistant.swift` |
| Tool calling: catalogue search, read a guide, rules search, change theme, change language | `*Tool` structs in `AIAssistant.swift` |
| Human in the loop: a tool that waits for the user's approval (`CheckedContinuation`) | `ChangeLanguageTool`, `AIChat.askUser` |
| On-device RAG with BM25 keyword search over rule passages | `AI/RulesSearch.swift` |
| Context window: token meter (`tokenCount(for:)`), carrying a summary into a fresh session | `AIChat.prepare`, `carryOverSummary` |
| Pre-routing: requests answered by app code before the model (help, typos, comparisons) | `AIChat.send` |
| Guardrail-aware fallbacks (show the guide's own text instead of failing) | `guardrailFallbackGuide` |
| Two-stage answers: accurate English first, then a rewrite in another language | `AIChat.restyle` |
| Translate button: Foundation Models first, `Translation` framework as fallback, `NaturalLanguage` detection | `AI/AITranslate.swift` |
| Ask by voice: `SpeechAnalyzer` (SpeechTranscriber / DictationTranscriber) with `SFSpeechRecognizer` fallback | `AI/AIVoiceInput.swift` |
| Read aloud with `AVSpeechSynthesizer`, character voices via `AVAudioUnitTimePitch` | `AI/AISpeech.swift` |
| Typo detection for game names, and fixing misheard names from speech | `AI/AITypo.swift`, `GameNameFixer` |
| Local chat history (JSON in Application Support, file protection) | `AI/AIChatHistory.swift` |
| A small eval harness that runs the real model (`-aiEval` launch argument, Debug only) | `AI/AIEval.swift` |
| Liquid Glass: native `TabView`/`NavigationStack`/`.searchable`, `glassEffect`, `GlassEffectContainer`, `.glass` buttons | `App/OnDeviceAIApp.swift`, `AI/AIChatView.swift` |
| Kids Mode: SwiftUI animations and Swift Charts for each game | `Features/KidsMode/` |

## Run it

You need Xcode with the iOS 27 SDK and a device that supports Apple Intelligence (for the model), with
Apple Intelligence turned on. The Simulator on an Apple silicon Mac works for most features. Voice input
falls back to `SFSpeechRecognizer` there.

```sh
brew install xcodegen
xcodegen generate
open OnDeviceAI.xcodeproj
```

Set your own team and bundle ID in **Signing & Capabilities** (`project.yml` uses `com.example.ondeviceai.boardgame`).

## Lessons from testing with a small on-device model

- Keep the prompt and instructions in English. Produce other languages in a second pass.
- Put the mood field *before* the text in `@Generable` output, so the face updates while the text streams.
- Mark tool output the model must not repeat as `[note: …]`, and strip those notes from the answer as a safety net.
- Cap tool calls per turn and answer repeated calls with "you already did this", because small models can loop.
- Don't trust the model to remember earlier filters when refining a search. Keep them in app state.
- Use `@Generable` enums for choices (themes, languages) so the model can only pick values that exist.
- Some requests (switching language, resetting a theme, comparing shown results) are more reliable when
  app code does them and the model only confirms.

## Customise

- **Mascots**: `Mascot` in `Core/Theme.swift` (names, personas, voices) and `MascotFace` in `Core/Components.swift` (artwork).
- **Games and guides**: `SampleData` in `Core/Models.swift`. The guide text was written for this sample.
- **Rules text for RAG**: `RulesSearch` builds passages from the guides. Point it at your own rulebook.

## Credits

Built while following an Apple course on Apple Intelligence and the Foundation Models framework.
Only Apple frameworks are used.

King of Tokyo, UNO and Monopoly are trademarks of their respective owners. This project is not affiliated
with or endorsed by them. The game descriptions here are short original summaries for demo purposes.

## License

MIT. See [LICENSE](LICENSE).
