import SwiftUI

/// The Ask tab: chat with the on-device assistant.
struct AIChatView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.pal) private var p
    @Environment(\.lang) private var lang
    @StateObject private var chat = AIChat()
    @StateObject private var voice = AIVoiceInput()
    @ObservedObject private var history = ChatHistoryStore.shared
    /// The last question came by voice: read the answer aloud automatically.
    @State private var voiceTurn = false
    @State private var prompt = ""
    @State private var showHistory = false
    @FocusState private var focused: Bool

    private var context: AIContext { AIContext(state: state, focusGuide: state.askFocus) }
    private var focusKey: String { AIChat.memoryKey(context) + "|" + state.mascot.rawValue }

    var body: some View {
        NavigationStack {
            Group {
                if let reason = chat.unavailableText(lang) {
                    VStack { Says(mascot: state.mascot, text: reason, mood: .shock).padding(16); Spacer() }
                } else {
                    messagesList
                        .safeAreaInset(edge: .bottom) { inputBar }
                }
            }
            .background(p.paper)
            .navigationTitle(tx(lang, "Tanya AI", "Ask AI"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .sheet(isPresented: $showHistory) {
            ChatHistoryView(currentID: chat.currentChatID) { r in chat.open(r) }
                .environment(\.lang, lang)
        }
        .onChange(of: focusKey) { if chat.unavailableText(lang) == nil { chat.switchTo(context) } }
        .onChange(of: state.pendingAsk) { sendPending() }
        .onChange(of: voice.transcript) { if voice.isActive { prompt = voice.transcript } }
        .onChange(of: chat.busy) {
            guard !chat.busy, voiceTurn else { return }
            voiceTurn = false
            if let m = chat.messages.last, m.role == .assistant, !m.text.isEmpty {
                AISpeaker.shared.toggle(id: m.id, text: m.text, style: state.mascot.voice, lang: lang)
            }
        }
        .onDisappear { AISpeaker.shared.stop(); Task { await voice.stop(send: false) } }
        .onAppear {
            voice.onNothingHeard = { silent in chat.voiceHeardNothing(silent: silent) }
            voice.onFinished = { text in
                prompt = ""
                chat.send(GameNameFixer.fix(text, names: state.guides.map(\.game)))
                voiceTurn = chat.busy
            }
            if chat.unavailableText(lang) == nil { chat.prepareRestoring(context) }
            sendPending()
            #if DEBUG
            // Quality check on a real device or simulator: launch with `-aiEval`. See AIEval.swift.
            if ProcessInfo.processInfo.arguments.contains("-aiEval") { Task { await AIEval.run(state: state) } }
            #endif
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let g = state.askFocus {
            ToolbarItem(placement: .topBarLeading) {
                Button { state.askFocus = nil } label: { Label(g.game, systemImage: "xmark.circle.fill").labelStyle(.titleAndIcon) }
                    .accessibilityLabel(tx(lang, "Tentang \(g.game). Ketuk untuk obrolan umum", "About \(g.game). Tap for a general chat"))
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if !history.records.isEmpty {
                Button { showHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }
                    .accessibilityLabel(tx(lang, "Obrolan sebelumnya", "Previous chats"))
            }
            if !chat.messages.isEmpty {
                Button { chat.reset() } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel(tx(lang, "Percakapan baru", "New conversation"))
            }
        }
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // How fast the context window fills: "1,240 / 4,096 tokens".
                    Text(tokenStatus).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    if chat.messages.isEmpty { welcome }
                    ForEach(chat.messages) { m in bubble(m).id(m.id) }
                    if let a = chat.approval { approvalCard(a) }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            // New turn: put the user's question at the top ONCE and let the answer grow below it.
            .onChange(of: chat.messages.count) {
                guard let q = chat.messages.last(where: { $0.role == .user }) else { return }
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(q.id, anchor: .top) }
            }
            .onChange(of: chat.approval?.id) { withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
        }
    }

    private var tokenStatus: String {
        chat.contextSize > 0 ? "\(chat.usedTokens.formatted()) / \(chat.contextSize.formatted()) tokens" : "\(chat.usedTokens.formatted()) tokens"
    }

    private var suggestions: [String] {
        if let g = state.askFocus {
            return ["How do I win \(g.game)?", "How do I set up \(g.game)?", "What happens on one turn of \(g.game)?", "Is \(g.game) good for a 6-year-old?"]
        }
        return ["How do I win King of Tokyo?", "What does a Draw Two card do?", "A game for 4 players with a 7-year-old", "Dark mode with a pink accent", "What can you help me with?"]
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 12) {
            Says(mascot: state.mascot, text: state.askFocus.map {
                tx(lang, "Mau tanya apa soal **\($0.game)**? Tanya pakai bahasa Inggris ya.", "What do you want to know about **\($0.game)**? I answer straight from the guide.")
            } ?? tx(lang, "Hai! Tanya pakai **bahasa Inggris** ya: cara main, aturan, rekomendasi game, atau minta ganti tampilan.",
                    "Hi! Ask in **English**: how to play, confusing rules, what to play next, or ask me to change the app's look."))
            FlowLayout(spacing: 8) {
                ForEach(suggestions, id: \.self) { q in
                    Button(q) { chat.send(q) }
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .buttonStyle(.glass)
                }
            }
        }
    }

    @ViewBuilder
    private func bubble(_ m: AIMessage) -> some View {
        switch m.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(m.text).font(.body.weight(.medium)).foregroundStyle(.white)
                    .padding(12)
                    .background(p.tint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        case .error:
            Says(mascot: state.mascot, text: m.text, mood: m.mood, size: 40)
        case .assistant:
            HStack(alignment: .top, spacing: 8) {
                MascotFace(mascot: state.mascot, mood: m.mood, size: 40)
                VStack(alignment: .leading, spacing: 8) {
                    Group {
                        if m.text.isEmpty {
                            HStack(spacing: 8) { ProgressView(); Text(thinkingText).font(.subheadline).foregroundStyle(p.ink2) }
                        } else {
                            Text(markdown(m.text)).font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .background(p.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    meta(m)
                    if !m.restyling, !chat.busy || m.id != chat.messages.last?.id {
                        HStack { AISpeakButton(id: m.id, text: m.text, mascot: state.mascot); AITranslateButton(text: m.text) }
                    }
                    let actions = m.id == chat.messages.last?.id && chat.busy ? chat.turnActions : m.actions
                    if !actions.isEmpty { chips(actions) }
                    if let n = m.matchCount, !m.games.isEmpty {
                        Text(tx(lang, "\(n) game cocok", "\(n) matching games") + (m.matchFilters.isEmpty ? "" : " · " + m.matchFilters))
                            .font(.caption.weight(.bold)).foregroundStyle(p.ink2)
                    }
                    ForEach(m.games) { g in gameCard(g) }
                    if let undo = m.undo { SmallButton("arrow.uturn.backward", tx(lang, "Batalkan", "Undo")) { chat.undoTheme(undo) } }
                    if !m.features.isEmpty { features(m.features) }
                    if !m.prompts.isEmpty {
                        FlowLayout(spacing: 8) {
                            ForEach(m.prompts, id: \.self) { q in Button(q) { chat.send(q) }.buttonStyle(.glass).disabled(chat.busy) }
                        }
                    }
                    if !m.links.isEmpty {
                        FlowLayout(spacing: 8) {
                            ForEach(m.links) { g in SmallButton("book.fill", tx(lang, "Panduan \(g.game)", "\(g.game) guide")) { state.open(g) } }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func meta(_ m: AIMessage) -> some View {
        if let note = m.note { Text(note).font(.caption.weight(.semibold)).foregroundStyle(p.ink2) }
        if m.restyling {
            HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("Menulis ulang ke Bahasa Indonesia…").font(.caption).foregroundStyle(p.ink2) }
        } else if let en = m.english {
            DisclosureGroup(tx(lang, "Lihat English asli", "Show original English")) {
                Text(en).font(.footnote).foregroundStyle(p.ink2).padding(.top, 4)
            }
            .font(.caption.weight(.semibold))
        }
    }

    /// Informative "thinking" line that follows the step in progress.
    private var thinkingText: String {
        switch chat.status {
        case .catalog: tx(lang, "Bongkar lemari board game…", "Looking through the game shelf…")
        case .rulebook: tx(lang, "Buka-buka buku aturan…", "Flipping through the rulebook…")
        case .rules: tx(lang, "Cari aturan yang pas…", "Searching the rules…")
        case .theme: tx(lang, "Ambil kotak cat…", "Grabbing the paint box…")
        case .language: tx(lang, "Menunggu persetujuanmu…", "Waiting for your OK…")
        case .thinking: tx(lang, "\(state.mascot.name) lagi mikir…", "\(state.mascot.name) is thinking…")
        }
    }

    private func chips(_ actions: [AIAction]) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(actions) { a in
                Label(a.text, systemImage: a.symbol)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(p.surface, in: Capsule())
            }
        }
    }

    private func gameCard(_ g: Game) -> some View {
        Button {
            if let guide = state.guide(for: g) { state.open(guide) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: g.symbol).font(.title3).foregroundStyle(p.tint).frame(width: 40, height: 40)
                    .background(p.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(g.name).font(.headline)
                    Text("\(g.players) · \(g.minutes) · \(g.age)").font(.caption).foregroundStyle(p.ink2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(p.ink2)
            }
            .padding(10)
            .background(p.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func features(_ list: [AIFeature]) -> some View {
        VStack(spacing: 8) {
            ForEach(list) { f in
                Button {
                    if let q = f.prompt { chat.send(q) } else { Task { await voice.start(british: state.mascot == .c) } }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: f.symbol).foregroundStyle(p.tint).frame(width: 32, height: 32)
                            .background(p.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(f.title).font(.subheadline.weight(.semibold))
                            Text(f.prompt.map { "“\($0)”" } ?? f.detail).font(.caption).foregroundStyle(p.ink2).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(p.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(chat.busy)
            }
        }
    }

    /// changeLanguage waits here until the user chooses (human in the loop).
    private func approvalCard(_ a: AIApproval) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(a.title).font(.headline)
            Text(a.detail).font(.subheadline).foregroundStyle(p.ink2)
            HStack {
                Button(tx(lang, "Setuju", "Approve"), systemImage: "checkmark") { chat.answer(true) }.buttonStyle(.glassProminent)
                Button(tx(lang, "Jangan", "Deny"), systemImage: "xmark") { chat.answer(false) }.buttonStyle(.glass)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// Prompt field + mic + send, floating on Liquid Glass above the tab bar.
    private var inputBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                TextField(tx(lang, "Tanya dalam bahasa Inggris…", "Ask in English…"), text: $prompt, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .glassEffect(.regular.interactive(), in: Capsule())
                micButton
                Button { if chat.busy { chat.stop() } else { send() } } label: {
                    Image(systemName: chat.busy ? "stop.fill" : "arrow.up").font(.headline).frame(width: 30, height: 30)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(p.tint)
                .disabled(!chat.busy && prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(chat.busy ? tx(lang, "Berhenti", "Stop") : tx(lang, "Kirim", "Send"))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .overlay(alignment: .top) {
            if let note = voice.problem ?? voice.status { Text(note).font(.caption).foregroundStyle(p.ink2).offset(y: -14) }
        }
    }

    /// Tap to talk (English), tap again to send now. Stops by itself after a short silence.
    private var micButton: some View {
        let on = voice.phase == .listening
        return Button {
            Task {
                if voice.isActive { await voice.stop(send: true) } else {
                    // Stop reading aloud first and wait a moment: switching straight from .playback to .record
                    // in the same tick sometimes left the mic silent.
                    let wasSpeaking = AISpeaker.shared.speakingID != nil
                    AISpeaker.shared.stop()
                    focused = false
                    if wasSpeaking { try? await Task.sleep(nanoseconds: 300_000_000) }
                    await voice.start(british: state.mascot == .c)
                }
            }
        } label: {
            Group {
                if voice.phase == .preparing || voice.phase == .finishing { ProgressView() }
                else { Image(systemName: on ? "waveform" : "mic.fill").symbolEffect(.variableColor.iterative, isActive: on) }
            }
            .font(.headline).frame(width: 30, height: 30)
            .scaleEffect(on ? 1 + CGFloat(voice.level) * 0.15 : 1)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .disabled(chat.busy)
        .accessibilityLabel(on ? tx(lang, "Selesai bicara", "Done talking") : tx(lang, "Tanya pakai suara", "Ask by voice"))
    }

    private func sendPending() {
        guard let q = state.pendingAsk else { return }
        state.pendingAsk = nil
        guard chat.unavailableText(lang) == nil else { prompt = q; return }
        Task {
            while chat.busy { try? await Task.sleep(nanoseconds: 300_000_000) }
            chat.send(q)
        }
    }

    private func send() {
        let q = prompt
        prompt = ""
        voiceTurn = false // typed prompts are never read aloud automatically
        chat.send(q)
    }
}
