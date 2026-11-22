import SwiftUI
import Charts

// Kids Mode: UNO. A mini game against the mascot, flip cards for the action cards, and a points chart.

// MARK: - UNO

struct UnoCard: Identifiable, Hashable {
    enum Face: Hashable { case number(Int), skip, reverse, draw2, wild, wild4 }
    let id = UUID()
    let color: Int? // 0 red, 1 yellow, 2 green, 3 blue; nil = wild
    let face: Face
    static let colors: [Color] = [Color(hex: 0xFFE03131), Color(hex: 0xFFFAB005), Color(hex: 0xFF2F9E44), Color(hex: 0xFF1C7ED6)]
    var label: String {
        switch face {
        case .number(let n): "\(n)"
        case .skip: "⊘"
        case .reverse: "⇄"
        case .draw2: "+2"
        case .wild: "🌈"
        case .wild4: "+4"
        }
    }
    static func random() -> UnoCard {
        switch Int.random(in: 0..<20) {
        case 0: UnoCard(color: nil, face: .wild)
        case 1: UnoCard(color: nil, face: .wild4)
        case 2: UnoCard(color: Int.random(in: 0..<4), face: .skip)
        case 3: UnoCard(color: Int.random(in: 0..<4), face: .reverse)
        case 4: UnoCard(color: Int.random(in: 0..<4), face: .draw2)
        default: UnoCard(color: Int.random(in: 0..<4), face: .number(Int.random(in: 0...9)))
        }
    }
}

struct UnoCardView: View {
    let card: UnoCard
    var shownColor: Int? = nil // colour chosen for a wild on the pile
    var size: CGFloat = 48
    var dim = false
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                .fill(card.color.map { AnyShapeStyle(UnoCard.colors[$0].gradient) }
                      ?? AnyShapeStyle(AngularGradient(colors: UnoCard.colors + [UnoCard.colors[0]], center: .center)))
            Ellipse().fill(.white).rotationEffect(.degrees(-30)).padding(size * 0.12)
            Text(card.label).font(.system(size: size * 0.42, weight: .black, design: .rounded))
                .foregroundStyle(card.color.map { UnoCard.colors[$0] } ?? shownColor.map { UnoCard.colors[$0] } ?? .black)
            if card.color == nil, let c = shownColor {
                RoundedRectangle(cornerRadius: size * 0.16, style: .continuous).stroke(UnoCard.colors[c], lineWidth: 4)
            }
        }
        .frame(width: size, height: size * 1.45)
        .shadow(color: .black.opacity(0.2), radius: 2, y: 2)
        .opacity(dim ? 0.4 : 1)
    }
}

struct UnoKidsView: View {
    @Environment(\.lang) private var mode
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                KidsHero(emojis: ["🟥", "🟨", "🟩", "🟦", "🌈"],
                         title: tx(mode, "Habiskan kartumu, teriak UNO!", "Empty your hand, shout UNO!"),
                         pills: ["👥 2–10", "⏱ 15–30 min", "🧒 7+"],
                         colors: [Color(hex: 0xFFFFA8A8), Color(hex: 0xFFFFE066), Color(hex: 0xFF8CE99A), Color(hex: 0xFF74C0FC)])
                UnoMatchGame()
                KidsCard(title: tx(mode, "Kartu aksi (ketuk!)", "Action cards (tap!)"), emoji: "✨") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        FlipCard(emoji: "⊘", name: "Skip", meaning: tx(mode, "Pemain berikut dilewati", "Next player is skipped"), color: UnoCard.colors[0])
                        FlipCard(emoji: "⇄", name: "Reverse", meaning: tx(mode, "Arah giliran berbalik", "Direction flips"), color: UnoCard.colors[1])
                        FlipCard(emoji: "+2", name: "Draw Two", meaning: tx(mode, "Berikut ambil 2 & dilewati", "Next draws 2 & is skipped"), color: UnoCard.colors[2])
                        FlipCard(emoji: "🌈", name: "Wild", meaning: tx(mode, "Kamu pilih warna", "You pick the colour"), color: Color(hex: 0xFF212529))
                        FlipCard(emoji: "+4", name: "Wild Draw 4", meaning: tx(mode, "Pilih warna, berikut ambil 4", "Pick colour, next draws 4"), color: Color(hex: 0xFF495057))
                        FlipCard(emoji: "🔀", name: "Shuffle Hands", meaning: tx(mode, "Semua kartu dikocok ulang", "Everyone's hands reshuffled"), color: UnoCard.colors[3])
                    }
                }
                UnoPointsChart()
                Text(tx(mode, "Sisa 1 kartu? Teriak UNO! 📣", "One card left? Shout UNO! 📣"))
                    .font(.system(.title3, design: .rounded, weight: .bold)).padding(.vertical, 12)
            }
            .padding(16)
        }
    }
}

/// Mini UNO against the mascot: match colour, number or symbol; Wild any time; forgetting UNO = draw 2.
private struct UnoMatchGame: View {
    @Environment(\.pal) private var p
    @Environment(\.lang) private var mode
    @State private var top = UnoCard(color: 0, face: .number(5))
    @State private var topColor = 0
    @State private var hand: [UnoCard] = []
    @EnvironmentObject private var state: AppState
    @State private var botCards = 7
    private var bot: String { state.mascot.name }
    @State private var saidUno = false
    @State private var picking: UnoCard?
    @State private var note = ""
    @State private var over = false
    @State private var unoFlash = false

    private func legal(_ c: UnoCard) -> Bool {
        guard let col = c.color else { return true }
        if col == topColor { return true }
        switch (c.face, top.face) {
        case (.number(let a), .number(let b)): return a == b
        case (.skip, .skip), (.reverse, .reverse), (.draw2, .draw2): return true
        default: return false
        }
    }

    var body: some View {
        KidsCard(title: tx(mode, "Main lawan \(bot)!", "Play against \(bot)!"), emoji: "🎴") {
            HStack(spacing: 18) {
                VStack(spacing: 2) {
                    MascotFace(mascot: state.mascot, mood: .smug, size: 36)
                    Text(tx(mode, "\(bot): \(botCards) kartu", "\(bot): \(botCards) cards")).font(.caption.weight(.bold)).contentTransition(.numericText())
                }
                UnoCardView(card: top, shownColor: topColor, size: 62).id(top.id).transition(.scale.combined(with: .move(edge: .bottom)))
                VStack(spacing: 2) {
                    Circle().fill(UnoCard.colors[topColor]).frame(width: 26, height: 26)
                    Text(tx(mode, "warna", "colour")).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            Text(unoFlash ? "UNO! 📣" : note.isEmpty ? tx(mode, "Cocokkan warna, angka, atau simbol", "Match colour, number or symbol") : note)
                .font(.system(unoFlash ? .title : .headline, design: .rounded, weight: .heavy))
                .foregroundStyle(unoFlash ? .red : p.ink)
                .frame(maxWidth: .infinity).multilineTextAlignment(.center)
            if let w = picking {
                HStack(spacing: 14) {
                    ForEach(0..<4, id: \.self) { c in
                        Button { finishPlay(w, color: c) } label: { Circle().fill(UnoCard.colors[c]).frame(width: 44, height: 44) }.buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: -6) {
                    ForEach(hand) { c in
                        Button { tap(c) } label: { UnoCardView(card: c, size: 46, dim: !legal(c)).offset(y: legal(c) ? -6 : 0) }
                            .buttonStyle(.plain).disabled(!legal(c) || picking != nil || over)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.top, 8).padding(.horizontal, 6)
            }
            HStack(spacing: 10) {
                if over {
                    kidsButton(tx(mode, "Main lagi", "Play again"), "arrow.counterclockwise", tint: p.tint, action: newGame)
                } else {
                    kidsButton(tx(mode, "Ambil 1", "Draw 1"), "plus.rectangle.on.rectangle", tint: p.tint, action: draw)
                    Button {
                        saidUno = true
                        withAnimation(.spring(duration: 0.3, bounce: 0.6)) { unoFlash = true }
                        Task { try? await Task.sleep(nanoseconds: 900_000_000); withAnimation { unoFlash = false } }
                    } label: {
                        Text("UNO!").font(.system(.headline, design: .rounded, weight: .black)).padding(.horizontal, 14).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(.red)
                    .disabled(hand.count != 2 || picking != nil)
                }
            }
        }
        .sensoryFeedback(.impact, trigger: top.id)
        .onAppear { if hand.isEmpty { newGame() } }
    }

    private func newGame() {
        withAnimation {
            hand = (0..<7).map { _ in UnoCard.random() }
            top = UnoCard(color: Int.random(in: 0..<4), face: .number(Int.random(in: 0...9)))
            topColor = top.color ?? 0
            botCards = 7; saidUno = false; picking = nil; note = ""; over = false
        }
    }

    private func tap(_ c: UnoCard) {
        if c.color == nil { withAnimation { picking = c; note = tx(mode, "Pilih warna 🌈", "Pick a colour 🌈") } }
        else { finishPlay(c, color: c.color!) }
    }

    private func finishPlay(_ c: UnoCard, color: Int) {
        // Forgot to shout UNO when playing the second-to-last card → draw 2 (the mascot "catches" you).
        let forgot = hand.count == 2 && !saidUno
        withAnimation(.spring(duration: 0.4)) {
            hand.removeAll { $0.id == c.id }
            top = c; topColor = color; picking = nil
            if forgot { hand += [UnoCard.random(), UnoCard.random()]; note = tx(mode, "Lupa UNO! \(bot) menangkap: ambil 2 😅", "Forgot UNO! \(bot) caught you: draw 2 😅") }
        }
        saidUno = false
        if hand.isEmpty { withAnimation { over = true; note = tx(mode, "Kartumu habis, kamu menang! 🏆", "Hand empty, you win! 🏆") }; return }
        botTurn(after: c)
    }

    private func draw() {
        withAnimation { hand.append(UnoCard.random()); note = tx(mode, "Ambil 1 kartu", "Drew a card") }
        botTurn(after: nil)
    }

    private func botTurn(after c: UnoCard?) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            var effect = ""
            switch c?.face {
            case .skip?, .reverse?: note = tx(mode, "\(bot) dilewati! Giliranmu lagi ⊘", "\(bot) is skipped! Your turn again ⊘"); return
            case .draw2?: withAnimation { botCards += 2 }; note = tx(mode, "\(bot) ambil 2 & dilewati! +2", "\(bot) draws 2 & is skipped! +2"); return
            case .wild4?: withAnimation { botCards += 4 }; note = tx(mode, "\(bot) ambil 4 & dilewati! +4", "\(bot) draws 4 & is skipped! +4"); return
            default: break
            }
            // The mascot plays a random matching card most of the time, otherwise draws 1.
            if Bool.random() || Int.random(in: 0..<10) < 4 {
                let col = Bool.random() ? topColor : Int.random(in: 0..<4)
                let card = UnoCard(color: col, face: col == topColor ? .number(Int.random(in: 0...9)) : top.face)
                withAnimation(.spring(duration: 0.4)) { top = card; topColor = col; botCards -= 1 }
                effect = botCards == 1 ? tx(mode, "\(bot): UNO! 📣", "\(bot): UNO! 📣") : tx(mode, "\(bot) main \(card.label)", "\(bot) played \(card.label)")
            } else {
                withAnimation { botCards += 1 }
                effect = tx(mode, "\(bot) ambil 1 kartu", "\(bot) drew a card")
            }
            if botCards == 0 { over = true; effect = tx(mode, "\(bot) menang! Main lagi? 🙂", "\(bot) wins! Play again? 🙂") }
            note = effect
        }
    }
}

/// Points for cards left in other hands (to the round winner); 500 points wins the game.
private struct UnoPointsChart: View {
    @Environment(\.lang) private var mode
    @State private var shown = false
    private let data: [(String, Int, Color)] = [("0–9", 9, UnoCard.colors[2]), ("⊘ ⇄ +2", 20, UnoCard.colors[1]), ("🔀", 40, UnoCard.colors[3]), ("🌈 +4", 50, UnoCard.colors[0])]
    var body: some View {
        KidsCard(title: tx(mode, "Nilai kartu", "Card points"), emoji: "📊") {
            Chart(data, id: \.0) { d in
                BarMark(x: .value("Card", d.0), y: .value("Points", shown ? d.1 : 0))
                    .foregroundStyle(d.2.gradient).cornerRadius(6)
                    .annotation(position: .top) { Text(d.0 == "0–9" ? "0–9" : "\(d.1)").font(.system(.caption, design: .rounded, weight: .bold)) }
            }
            .chartYScale(domain: 0...58).chartYAxis(.hidden).frame(height: 160)
            Text(tx(mode, "Pemenang ronde dapat poin dari kartu lawan. 500 poin = juara! 🏆", "The round winner scores the cards left in other hands. 500 points = champion! 🏆"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { withAnimation(.spring(duration: 0.9).delay(0.2)) { shown = true } }
    }
}
