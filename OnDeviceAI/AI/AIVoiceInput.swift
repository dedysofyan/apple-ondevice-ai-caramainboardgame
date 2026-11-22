import Foundation
import AVFoundation
import Speech

// Ask by voice: mic → live transcript in the prompt field → sent automatically when you stop talking.
// Apple frameworks only. Three engines, tried in order:
//   1. SpeechTranscriber (SpeechAnalyzer): newest model, on-device. Not on every device (not in the Simulator).
//   2. DictationTranscriber (SpeechAnalyzer): on-device, more devices. Its model is downloaded once.
//   3. SFSpeechRecognizer: the older API. Used if 1–2 aren't ready within `prepareTimeout` (in the Simulator the
//      model download for 2 never finishes). Forced on-device when the device supports it.

@MainActor
final class AIVoiceInput: ObservableObject {
    enum Phase: Equatable { case idle, preparing, listening, finishing }

    @Published private(set) var phase: Phase = .idle
    /// Finalised text + the volatile part that may still change.
    @Published private(set) var transcript = ""
    @Published private(set) var problem: String?
    /// Short status while preparing, e.g. "Downloading speech model…".
    @Published private(set) var status: String?
    /// Input level 0…1, for the mic button animation.
    @Published private(set) var level: Float = 0
    /// Engine in use (for debugging).
    @Published private(set) var engineName = ""

    /// Called once with the final text when the user stops talking (or taps the mic again).
    var onFinished: ((String) -> Void)?
    /// Mic finished without words; `silent` = input level stayed at 0 (the mic got no sound at all).
    var onNothingHeard: ((Bool) -> Void)?

    private var engine: AVAudioEngine?
    // SpeechAnalyzer
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var results: Task<Void, Never>?
    // SFSpeechRecognizer
    private var legacyRequest: SFSpeechAudioBufferRecognitionRequest?
    private var legacyTask: SFSpeechRecognitionTask?

    private var silence: Task<Void, Never>?
    private var finalText = ""
    private var volatileText = ""

    /// Stop automatically after this much silence (once some words were heard).
    private let silenceSeconds: Double = 1.6
    private let maxSeconds: Double = 30
    private let prepareTimeout: Double = 8

    var isActive: Bool { phase != .idle }

    private func log(_ m: String) {
        #if DEBUG
        print("[Voice] \(m)")
        #endif
    }

    // MARK: Start

    func start(british: Bool) async {
        guard phase == .idle else { return }
        problem = nil; status = nil
        transcript = ""; finalText = ""; volatileText = ""
        phase = .preparing
        log("start british=\(british) speechTranscriberAvailable=\(SpeechTranscriber.isAvailable)")

        guard await AVAudioApplication.requestRecordPermission() else {
            fail("Microphone access is off. Turn it on in Settings for this app.")
            return
        }
        let wanted = Locale(identifier: british ? "en-GB" : "en-US")
        // 1–2: SpeechAnalyzer, with a time limit so the button never spins forever. (withTaskGroup can't be used:
        // it waits for every child, and a model download doesn't stop when cancelled.)
        attempt += 1
        let mine = attempt
        let ready = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            var resumed = false
            func finish(_ ok: Bool) { if !resumed { resumed = true; c.resume(returning: ok) } }
            Task { let ok = await self.startAnalyzer(wanted, attempt: mine); finish(ok) }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(self.prepareTimeout * 1_000_000_000))
                finish(false)
            }
        }
        if !ready { attempt += 1 }  // the losing attempt must not turn the mic on later
        if ready, analyzer != nil {
            phase = .listening; status = nil
            log("listening (\(engineName))")
            armSilenceTimer(first: true)
            return
        }
        log("SpeechAnalyzer not ready in \(prepareTimeout)s, falling back to SFSpeechRecognizer")
        teardownAnalyzer()
        // 3: SFSpeechRecognizer.
        await startLegacy(wanted)
    }

    /// SpeechTranscriber or DictationTranscriber. true once the mic is streaming into the analyzer.
    private var attempt = 0

    private func startAnalyzer(_ wanted: Locale, attempt mine: Int) async -> Bool {
        do {
            let module: any SpeechModule
            if SpeechTranscriber.isAvailable,
               let locale = Self.pick(wanted, from: await SpeechTranscriber.supportedLocales) {
                let t = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
                module = t; engineName = "SpeechTranscriber \(locale.identifier(.bcp47))"
                try await install(locale: locale, modules: [t])
                results = Task { [weak self] in
                    do { for try await r in t.results { self?.apply(String(r.text.characters), final: r.isFinal) } } catch {}
                }
            } else if let locale = Self.pick(wanted, from: await DictationTranscriber.supportedLocales) {
                let t = DictationTranscriber(locale: locale, preset: .progressiveShortDictation)
                module = t; engineName = "DictationTranscriber \(locale.identifier(.bcp47))"
                try await install(locale: locale, modules: [t])
                results = Task { [weak self] in
                    do { for try await r in t.results { self?.apply(String(r.text.characters), final: r.isFinal) } } catch {}
                }
            } else {
                return false
            }
            guard mine == attempt,
                  let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else { return false }
            let analyzer = SpeechAnalyzer(modules: [module])
            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            try await analyzer.start(inputSequence: stream)
            guard mine == attempt, phase == .preparing else { await analyzer.cancelAndFinishNow(); return false }
            self.analyzer = analyzer
            self.input = continuation
            try startMicrophone(convertingTo: format) { out in continuation.yield(AnalyzerInput(buffer: out)) }
            return true
        } catch {
            log("analyzer error: \(error)")
            return false
        }
    }

    private func startLegacy(_ wanted: Locale) async {
        engineName = "SFSpeechRecognizer"
        let auth = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        guard auth == .authorized else {
            fail("Speech recognition is off. Turn it on in Settings for this app.")
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: wanted) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            fail("Speech recognition for English isn't available right now.")
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        engineName = "SFSpeechRecognizer \(recognizer.locale.identifier(.bcp47))" + (request.requiresOnDeviceRecognition ? " on-device" : "")
        legacyRequest = request
        legacyTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            Task { @MainActor in
                guard let self else { return }
                if let text { self.volatileText = text; self.transcript = text; self.armSilenceTimer(first: false) }
                // Offline / airplane mode: recognition fails before any word → clear message instead of hanging.
                if let error, self.phase == .listening, self.transcript.isEmpty {
                    self.log("legacy error: \(error)")
                    self.fail("Voice input isn't available right now (it needs the on-device speech model or an internet connection). Please type your question.")
                }
                _ = isFinal
            }
        }
        do {
            try startMicrophone(convertingTo: nil) { request.append($0) }
            phase = .listening; status = nil
            log("listening (\(engineName))")
            armSilenceTimer(first: true)
        } catch {
            fail("Couldn't start the microphone: \(error.localizedDescription)")
        }
    }

    // MARK: Finish

    /// `send: false` cancels without sending (e.g. the screen closed).
    func stop(send: Bool) async {
        guard phase == .listening || phase == .preparing else { return }
        phase = .finishing
        silence?.cancel()
        stopMicrophone()
        if let analyzer {
            input?.finish()
            if send { try? await analyzer.finalizeAndFinishThroughEndOfInput() } else { await analyzer.cancelAndFinishNow() }
            // The last final result arrives just after finalize.
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        if let legacyRequest {
            legacyRequest.endAudio()
            try? await Task.sleep(nanoseconds: 300_000_000)
            legacyTask?.cancel()
        }
        teardownAnalyzer()
        legacyRequest = nil; legacyTask = nil
        level = 0; status = nil
        phase = .idle
        let text = (finalText + volatileText).trimmingCharacters(in: .whitespacesAndNewlines)
        log("finished send=\(send): \(text) [\(stats.snapshot())]")
        if send, !text.isEmpty { onFinished?(text) }
        else if send { onNothingHeard?(stats.peak < 0.0005) }
    }

    private func teardownAnalyzer() {
        results?.cancel()
        input?.finish()
        analyzer = nil; input = nil; results = nil
    }

    // MARK: Results

    private func apply(_ text: String, final: Bool) {
        log("result final=\(final): \(text)")
        if final { finalText += text; volatileText = "" } else { volatileText = text }
        transcript = (finalText + volatileText).trimmingCharacters(in: .whitespaces)
        armSilenceTimer(first: false)
    }

    /// Auto-send after a short silence; an overall limit so it never listens forever.
    private func armSilenceTimer(first: Bool) {
        guard phase == .listening else { return }
        silence?.cancel()
        let wait = first ? maxSeconds : silenceSeconds
        silence = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.stop(send: true)
        }
    }

    private func fail(_ message: String) {
        log("FAIL \(message)")
        problem = message
        status = nil
        stopMicrophone()
        teardownAnalyzer()
        legacyTask?.cancel(); legacyRequest = nil; legacyTask = nil
        phase = .idle
    }

    // MARK: Microphone

    /// One input buffer per call, capacity rounded up, status checked (the pattern Apple documents for SpeechAnalyzer).
    nonisolated private static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var handed = false
        var err: NSError?
        let status = converter.convert(to: out, error: &err) { _, inputStatus in
            defer { handed = true }
            inputStatus.pointee = handed ? .noDataNow : .haveData
            return handed ? nil : buffer
        }
        guard status != .error, err == nil, out.frameLength > 0 else { return nil }
        return out
    }

    /// Audio stats for diagnosis (written on the audio thread, read on the main actor).
    final class AudioStats: @unchecked Sendable {
        private let lock = NSLock()
        private var inBuffers = 0, outBuffers = 0, outFrames = 0, maxLevel: Float = 0
        func record(level: Float, converted: AVAudioPCMBuffer?) {
            lock.lock(); defer { lock.unlock() }
            inBuffers += 1; maxLevel = max(maxLevel, level)
            if let c = converted { outBuffers += 1; outFrames += Int(c.frameLength) }
        }
        var peak: Float { lock.lock(); defer { lock.unlock() }; return maxLevel }
        func snapshot() -> String {
            lock.lock(); defer { lock.unlock() }
            return "in=\(inBuffers) out=\(outBuffers) outFrames=\(outFrames) maxLevel=\(String(format: "%.4f", maxLevel))"
        }
    }
    private var stats = AudioStats()

    enum MicError: LocalizedError {
        case unavailable, formatNotSupported
        var errorDescription: String? {
            switch self {
            case .unavailable: "The microphone isn't available right now."
            case .formatNotSupported: "This microphone's audio format isn't supported."
            }
        }
    }

    /// Mic → `sink` (called on the audio thread). The level is sent to the main actor for the animation.
    /// The mic format is read from the SAME engine that stays alive, AFTER the audio session is active, and validated
    /// before AVAudioConverter/installTap. Reading `AVAudioEngine().inputNode` from a temporary engine that is released
    /// right away crashes (EXC_BAD_ACCESS, especially in airplane mode). installTap with an invalid format throws an
    /// Objective-C exception that `catch` can't handle, so this validation is required.
    private func startMicrophone(convertingTo target: AVAudioFormat?, _ sink: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        let session = AVAudioSession.sharedInstance()
        // .record + .default while listening. .playAndRecord with mode .spokenAudio (meant for PLAYING podcasts or
        // audiobooks) left the iPhone mic input silent in our tests. AISpeaker sets .playback itself when reading aloud.
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)
        // Per-app mic input can be muted (iOS 17+): make sure it isn't, then log the session state.
        if AVAudioApplication.shared.isInputMuted { try? AVAudioApplication.shared.setInputMuted(false) }
        log("session category=\(session.category.rawValue) mode=\(session.mode.rawValue) permission=\(AVAudioApplication.shared.recordPermission.rawValue) muted=\(AVAudioApplication.shared.isInputMuted) inputAvailable=\(session.isInputAvailable) gain=\(session.inputGain) inputs=\(session.currentRoute.inputs.map { "\($0.portType.rawValue):\($0.portName)" })")
        guard session.isInputAvailable else { throw MicError.unavailable }
        let engine = AVAudioEngine()
        let node = engine.inputNode
        let micFormat = node.outputFormat(forBus: 0)
        guard micFormat.sampleRate > 0, micFormat.channelCount > 0 else { throw MicError.unavailable }
        var converter: AVAudioConverter?
        if let target {
            guard let c = AVAudioConverter(from: micFormat, to: target) else { throw MicError.formatNotSupported }
            c.primeMethod = .none // avoid timestamp shifts from priming
            converter = c
        }
        log("mic format \(micFormat) → \(target.map { "\($0)" } ?? "raw")")
        let stats = AudioStats()
        self.stats = stats
        node.installTap(onBus: 0, bufferSize: 4096, format: micFormat) { [weak self] buffer, _ in
            let lvl = Self.rms(buffer)
            if let target, let converter {
                let out = Self.convert(buffer, with: converter, to: target)
                if let out { sink(out) }
                stats.record(level: lvl, converted: out)
            } else {
                sink(buffer)
                stats.record(level: lvl, converted: buffer)
            }
            Task { @MainActor in self?.level = lvl }
        }
        engine.prepare()
        do { try engine.start() } catch { node.removeTap(onBus: 0); throw error }
        self.engine = engine
    }

    private func stopMicrophone() {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated private static func rms(_ b: AVAudioPCMBuffer) -> Float {
        guard let ch = b.floatChannelData?[0], b.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(b.frameLength) { sum += ch[i] * ch[i] }
        return min(1, sqrt(sum / Float(b.frameLength)) * 8)
    }

    // MARK: Speech model

    /// en-GB for the British persona, en-US otherwise; any English if neither exists.
    private static func pick(_ wanted: Locale, from supported: [Locale]) -> Locale? {
        let en = supported.filter { $0.language.languageCode?.identifier == "en" }
        return en.first { $0.region == wanted.region } ?? en.first { $0.region?.identifier == "US" } ?? en.first
    }

    /// Reserve the speech model for this app and download it if missing (once).
    private func install(locale: Locale, modules: [any SpeechModule]) async throws {
        let reserved = await AssetInventory.reservedLocales
        if !reserved.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) {
            _ = try await AssetInventory.reserve(locale: locale)
        }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
            status = "Downloading the speech model (one time)…"
            log("downloading model for \(locale.identifier(.bcp47))")
            try await request.downloadAndInstall()
            status = nil
        }
    }
}

/// Speech recognition often mishears board game names ("Catan" → "Caiton", "Dixit" → "Digsid").
/// AnalysisContext.contextualStrings did not help SpeechTranscriber in our tests, so names are fixed afterwards
/// with a rough sound key.
enum GameNameFixer {
    /// Rough sound key: similar-sounding letters merged, vowels (except the first) dropped, doubles collapsed.
    static func key(_ s: String) -> String {
        var t = s.lowercased().folding(options: .diacriticInsensitive, locale: nil).filter(\.isLetter)
        for (a, b) in [("ph", "f"), ("ck", "k"), ("qu", "k"), ("x", "ks"), ("c", "k"), ("q", "k"), ("g", "k"), ("d", "t"), ("b", "p"), ("v", "f"), ("z", "s"), ("w", ""), ("h", ""), ("y", "")] {
            t = t.replacingOccurrences(of: a, with: b)
        }
        guard let first = t.first else { return "" }
        let rest = t.dropFirst().filter { !"aeiou".contains($0) }
        var out = String(first)
        for c in rest where c != out.last { out.append(c) }
        return out
    }

    static func similarity(_ a: String, _ b: String) -> Double {
        let a = Array(a.lowercased()), b = Array(b.lowercased())
        if a.isEmpty || b.isEmpty { return 0 }
        var d = Array(0...b.count)
        for i in 1...a.count {
            var prev = d[0]; d[0] = i
            for j in 1...b.count {
                let tmp = d[j]
                d[j] = min(d[j] + 1, d[j - 1] + 1, prev + (a[i - 1] == b[j - 1] ? 0 : 1))
                prev = tmp
            }
        }
        return 1 - Double(d[b.count]) / Double(max(a.count, b.count))
    }

    /// Replace 1–4 word chunks that sound like a game name (e.g. "Caiton" → "Catan").
    static func fix(_ text: String, names: [String]) -> String {
        let entries = names.map { n -> (name: String, words: Int, key: String) in (n, n.split(separator: " ").count, key(n)) }
            .filter { $0.key.count >= 3 }
        var words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var i = 0
        while i < words.count {
            var replaced = false
            for len in stride(from: 4, through: 1, by: -1) where i + len <= words.count {
                let chunk = words[i..<(i + len)].joined(separator: " ")
                let core = chunk.trimmingCharacters(in: .punctuationCharacters)
                guard core.count >= 4 else { continue }
                let k = key(core)
                if let hit = entries.first(where: { $0.words == len && $0.key == k && similarity(core, $0.name) >= 0.45 }) {
                    if core.lowercased() != hit.name.lowercased() {
                        let trailing = String(chunk.reversed().prefix { $0.isPunctuation }.reversed())
                        words.replaceSubrange(i..<(i + len), with: [hit.name + trailing])
                    } else {
                        words.replaceSubrange(i..<(i + len), with: [hit.name + chunk.dropFirst(core.count)])
                    }
                    replaced = true
                    break
                }
            }
            i += 1
            _ = replaced  // one replacement per position
        }
        return words.joined(separator: " ")
    }
}
