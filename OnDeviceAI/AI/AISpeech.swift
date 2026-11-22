import SwiftUI
import AVFoundation
import NaturalLanguage

// "Read aloud" under each answer: the mascot reads it with AVSpeechSynthesizer (on-device).
// AVSpeech has no child or cartoon voices, so a character voice is made by writing the speech into buffers
// and playing them through AVAudioEngine + AVAudioUnitTimePitch (pitch shift in cents).

@MainActor
final class AISpeaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = AISpeaker()

    enum VoiceStyle {
        /// Female voice, higher pitch, then shifted up 5 semitones.
        case childlike
        /// Female voice shifted down 6 semitones when no male voice exists for the language (e.g. id-ID).
        case lowered
        /// en-GB male voice, a little lower and slower.
        case britishMale
    }

    /// The message being read; nil when silent.
    @Published private(set) var speakingID: UUID?
    /// The voice is basic ("compact") quality: show a tip to download an Enhanced/Premium voice.
    @Published private(set) var basicVoiceLanguage: String?

    private let synth = AVSpeechSynthesizer()
    private var writer: AVSpeechSynthesizer?
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var engineStarted = false
    private var token = UUID()

    override private init() {
        super.init()
        synth.delegate = self
    }

    func toggle(id: UUID, text: String, style: VoiceStyle, lang: AppLanguage) {
        if speakingID == id { stop(); return }
        stop()
        let clean = Self.plain(text)
        guard !clean.isEmpty else { return }

        // Play even with the silent switch on; duck other audio briefly.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        let u = AVSpeechUtterance(string: clean)
        let language = Self.language(of: clean, british: style == .britishMale, fallback: lang)
        u.voice = Self.voice(language: language, male: style != .childlike)
        basicVoiceLanguage = (u.voice?.quality ?? .default) == .default ? language : nil
        u.postUtteranceDelay = 0.1
        speakingID = id
        switch style {
        case .britishMale where language == "en-GB":
            u.pitchMultiplier = 0.88
            u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
            synth.speak(u)
        case .lowered, .britishMale:
            u.pitchMultiplier = 0.9
            if u.voice?.gender == .male { synth.speak(u) } else { speakShifted(u, cents: -600) }
        case .childlike:
            u.pitchMultiplier = 2.0
            speakShifted(u, cents: 500)
        }
    }

    /// Write TTS into buffers (streaming) and play them through AVAudioUnitTimePitch.
    private func speakShifted(_ u: AVSpeechUtterance, cents: Float) {
        let t = UUID(); token = t
        let e = AVAudioEngine(), pl = AVAudioPlayerNode(), tp = AVAudioUnitTimePitch()
        tp.pitch = cents
        e.attach(pl); e.attach(tp)
        engine = e; player = pl; engineStarted = false
        let w = AVSpeechSynthesizer(); writer = w
        w.write(u) { [weak self] buf in
            guard let pcm = buf as? AVAudioPCMBuffer else { return }
            Task { @MainActor in self?.receive(pcm, token: t, engine: e, player: pl, pitch: tp) }
        }
    }

    private func receive(_ pcm: AVAudioPCMBuffer, token t: UUID, engine e: AVAudioEngine, player pl: AVAudioPlayerNode, pitch tp: AVAudioUnitTimePitch) {
        guard token == t else { return }
        if pcm.frameLength == 0 {
            // Writing finished: a 1-frame silent buffer marks the end of playback.
            guard engineStarted, let end = AVAudioPCMBuffer(pcmFormat: pcm.format, frameCapacity: 1) else { speakingID = nil; return }
            end.frameLength = 1
            pl.scheduleBuffer(end, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in if self?.token == t { self?.finishShifted() } }
            }
            return
        }
        if !engineStarted {
            // iOS 27: throwing connectNode/play (replacing connect(_:to:format:) and play()).
            do {
                try e.connectNode(pl, to: tp, format: pcm.format)
                try e.connectNode(tp, to: e.mainMixerNode, format: pcm.format)
                try e.start()
                try pl.play()
            } catch { speakingID = nil; return }
            engineStarted = true
        }
        pl.scheduleBuffer(pcm)
    }

    private func finishShifted() {
        player?.stop(); engine?.stop()
        player = nil; engine = nil; writer = nil; engineStarted = false
        speakingID = nil
    }

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        token = UUID()
        writer?.stopSpeaking(at: .immediate)
        player?.stop(); engine?.stop()
        player = nil; engine = nil; writer = nil; engineStarted = false
        speakingID = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in self.speakingID = nil }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in self.speakingID = nil }
    }

    // MARK: Text & voice

    /// Strip markdown so "*splendid*" and "- step" are not read out.
    static func plain(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "_", with: " ")
        t = t.replacingOccurrences(of: "(?m)^\\s*([-•]|\\d+\\.)\\s+", with: "", options: .regularExpression)
        // All-caps words ("UNO") tend to be spelled letter by letter: make them normal words, except real acronyms.
        let keep: Set<String> = ["RPG", "TCG", "CCG"]
        if let re = try? NSRegularExpression(pattern: "\\b[A-Z]{3,6}\\b") {
            for m in re.matches(in: t, range: NSRange(t.startIndex..., in: t)).reversed() {
                guard let r = Range(m.range, in: t), !keep.contains(String(t[r])) else { continue }
                t.replaceSubrange(r, with: t[r].capitalized)
            }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The voice follows the text on screen (original English or a translation), not only the app language.
    static func language(of text: String, british: Bool, fallback: AppLanguage) -> String {
        let r = NLLanguageRecognizer()
        r.languageConstraints = [.english, .indonesian, .malay]
        r.processString(text)
        let isEnglish = r.dominantLanguage == .english || (r.dominantLanguage == nil && fallback.isEn)
        if isEnglish { return british ? "en-GB" : "en-US" }
        return "id-ID"
    }

    /// Best installed voice. Installed voices differ per device, so there are fallbacks.
    static func voice(language: String, male: Bool) -> AVSpeechSynthesisVoice? {
        let all = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language == language && !$0.voiceTraits.contains(.isNoveltyVoice)
        }
        let gender: AVSpeechSynthesisVoiceGender = male ? .male : .female
        func rank(_ v: AVSpeechSynthesisVoice) -> (Int, Int) {
            let q = v.quality == .premium ? 0 : v.quality == .enhanced ? 1 : 2
            return (v.gender == gender ? 0 : 1, q)
        }
        return all.min { rank($0) < rank($1) } ?? AVSpeechSynthesisVoice(language: language)
    }
}

// MARK: - Button

struct AISpeakButton: View {
    @Environment(\.pal) private var p
    @Environment(\.lang) private var lang
    @ObservedObject private var speaker = AISpeaker.shared
    let id: UUID
    let text: String
    let mascot: Mascot

    var body: some View {
        let playing = speaker.speakingID == id
        VStack(alignment: .leading, spacing: 6) {
            SmallButton(playing ? "stop.fill" : "speaker.wave.2.fill", playing ? tx(lang, "Berhenti", "Stop") : tx(lang, "Bacakan", "Read aloud")) {
                speaker.toggle(id: id, text: text, style: mascot.voice, lang: lang)
            }
            .accessibilityHint(tx(lang, "Suara di perangkat", "On-device voice"))
            if playing, speaker.basicVoiceLanguage != nil {
                Text(tx(lang, "Suara terdengar robotik? Unduh suara Enhanced/Premium: Pengaturan › cari “Voices”.",
                        "Sounds robotic? Download an Enhanced or Premium voice: Settings › search “Voices”."))
                    .font(.caption).foregroundStyle(p.ink2)
            }
        }
    }
}
