import SwiftUI
import Charts

// Kids Mode: King of Tokyo. 20 stars or last monster standing, 6 dice faces, Tokyo +1/+2 stars.

struct KingOfTokyoKidsView: View {
    @Environment(\.pal) private var p
    @Environment(\.lang) private var mode

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                KoTHero()
                KoTWinCards()
                KoTDiceRoller()
                KoTDiceLegend()
                KoTTokyoAnimation()
                KoTRaceChart()
                Text(tx(mode, "Siap jadi Raja Tokyo? 👑", "Ready to be King of Tokyo? 👑"))
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .padding(.vertical, 12)
            }
            .padding(16)
        }
    }
}

// MARK: - 1. Hero: jumping monsters

private struct KoTHero: View {
    @Environment(\.lang) private var mode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounce = false
    private let monsters = ["🦖", "🦍", "🐙", "🤖", "🐉", "👽"]

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(Array(monsters.enumerated()), id: \.offset) { i, m in
                    Text(m).font(.system(size: 40))
                        .offset(y: bounce ? -14 : 0)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45).repeatForever().delay(Double(i) * 0.12), value: bounce)
                }
            }
            Text(tx(mode, "Jadilah RAJA Tokyo!", "Be the KING of Tokyo!"))
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                Pill(text: "👥 2–6")
                Pill(text: "⏱ 30 min")
                Pill(text: tx(mode, "🧒 6+ dibantu", "🧒 6+ with a grown-up"))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            LinearGradient(colors: [Color(hex: 0xFFFFE08A), Color(hex: 0xFFFF9F68), Color(hex: 0xFFB388FF)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .foregroundStyle(Color(hex: 0xFF2A1640))
        .onAppear { bounce = true }
    }
}

// MARK: - 2. Two ways to win

private struct KoTWinCards: View {
    @Environment(\.lang) private var mode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stars = 0
    @State private var hearts = 10
    @State private var timer: Timer?

    var body: some View {
        KidsCard(title: tx(mode, "2 cara menang", "2 ways to win"), emoji: "🏆") {
            HStack(spacing: 12) {
                VStack(spacing: 8) {
                    ZStack {
                        Circle().stroke(Color.yellow.opacity(0.25), lineWidth: 12)
                        Circle().trim(from: 0, to: CGFloat(stars) / 20)
                            .stroke(Color.yellow, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text("⭐").font(.title2)
                            Text("\(stars)").font(.system(.title, design: .rounded, weight: .heavy)).contentTransition(.numericText())
                        }
                    }
                    .frame(width: 110, height: 110)
                    Text(tx(mode, "Kumpulkan 20 ⭐", "Get 20 ⭐")).font(.system(.headline, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                Text(tx(mode, "atau", "or")).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                VStack(spacing: 8) {
                    VStack(spacing: 2) {
                        HStack(spacing: 1) { ForEach(0..<5, id: \.self) { i in heart(i) } }
                        HStack(spacing: 1) { ForEach(5..<10, id: \.self) { i in heart(i) } }
                    }
                    .frame(height: 110)
                    Text(tx(mode, "Monster terakhir 💪", "Last monster standing 💪"))
                        .font(.system(.headline, design: .rounded)).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear(perform: start)
        .onDisappear { timer?.invalidate() }
    }

    private func heart(_ i: Int) -> some View {
        Text(i < hearts ? "❤️" : "🤍").font(.system(size: 20))
            .scaleEffect(i < hearts ? 1 : 0.7)
            .animation(.spring(duration: 0.35), value: hearts)
    }

    private func start() {
        guard !reduceMotion else { stars = 20; hearts = 0; return }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { _ in
            Task { @MainActor in
                withAnimation(.easeOut(duration: 0.3)) {
                    if stars < 20 { stars += 1 } else { stars = 0 }
                    hearts = hearts > 0 ? hearts - 1 : 10
                }
            }
        }
    }
}

// MARK: - 3. Roll the dice (interactive)

enum KoTFace: Int, CaseIterable {
    case one = 1, two, three, energy, heal, smash
    var symbol: String {
        switch self { case .one: "1"; case .two: "2"; case .three: "3"; case .energy: "⚡"; case .heal: "❤️"; case .smash: "👊" }
    }
    var color: Color {
        switch self {
        case .one, .two, .three: Color(hex: 0xFF3A3A48)
        case .energy: Color(hex: 0xFF1C9C5A)
        case .heal: Color(hex: 0xFFE0335A)
        case .smash: Color(hex: 0xFFE07A1F)
        }
    }
}

private struct KoTDiceRoller: View {
    @Environment(\.pal) private var p
    @Environment(\.lang) private var mode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dice: [KoTFace] = [.one, .two, .three, .energy, .heal, .smash]
    @State private var kept: Set<Int> = []
    @State private var rolls = 0
    @State private var spin = 0.0

    var body: some View {
        KidsCard(title: tx(mode, "Giliranmu: lempar dadu!", "Your turn: roll the dice!"), emoji: "🎲") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                ForEach(0..<6, id: \.self) { i in
                    Button { if rolls > 0 { kept.formSymmetricDifference([i]) } } label: {
                        Text(dice[i].symbol)
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
                            .background(dice[i].color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(kept.contains(i) ? Color.yellow : .clear, lineWidth: 4))
                            .rotationEffect(.degrees(kept.contains(i) ? 0 : spin))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(dice[i].symbol)\(kept.contains(i) ? ", kept" : "")")
                }
            }
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(i < rolls ? p.tint : p.ink.opacity(0.15)).frame(width: 10, height: 10)
                }
                Text(rolls == 0 ? tx(mode, "3 kali lempar", "3 rolls") : tx(mode, "Ketuk dadu untuk simpan 🔒", "Tap dice to keep 🔒"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if rolls > 0 { result }
            Button(action: roll) {
                Label(rolls >= 3 ? tx(mode, "Main lagi", "Play again") : tx(mode, "Lempar!", "Roll!"),
                      systemImage: rolls >= 3 ? "arrow.counterclockwise" : "dice.fill")
                    .font(.system(.headline, design: .rounded)).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(p.tint)
        }
    }

    /// Result by the rules: three of a number = that many stars, +1 per extra die; ⚡/❤️/👊 count per die.
    private var result: some View {
        let counts = Dictionary(grouping: dice, by: { $0 }).mapValues(\.count)
        let stars = [KoTFace.one, .two, .three].reduce(0) { sum, f in
            let c = counts[f] ?? 0
            return sum + (c >= 3 ? f.rawValue + (c - 3) : 0)
        }
        return HStack(spacing: 10) {
            ResultBadge(emoji: "⭐", value: stars)
            ResultBadge(emoji: "⚡", value: counts[.energy] ?? 0)
            ResultBadge(emoji: "❤️", value: counts[.heal] ?? 0)
            ResultBadge(emoji: "👊", value: counts[.smash] ?? 0)
        }
        .frame(maxWidth: .infinity)
    }

    private func roll() {
        if rolls >= 3 { rolls = 0; kept = [] }
        rolls += 1
        withAnimation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.4)) {
            spin += 360
            for i in 0..<6 where !kept.contains(i) { dice[i] = KoTFace.allCases.randomElement()! }
        }
    }
}

private struct ResultBadge: View {
    let emoji: String
    let value: Int
    var body: some View {
        VStack(spacing: 2) {
            Text(emoji).font(.title3)
            Text("+\(value)").font(.system(.headline, design: .rounded, weight: .heavy)).contentTransition(.numericText())
        }
        .frame(width: 58, height: 58)
        .background(.yellow.opacity(value > 0 ? 0.3 : 0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.spring(duration: 0.3), value: value)
    }
}

// MARK: - 4. What the dice faces do

private struct KoTDiceLegend: View {
    @Environment(\.lang) private var mode
    var body: some View {
        KidsCard(title: tx(mode, "Arti dadu", "What the dice do"), emoji: "🔎") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 10) {
                row(.three, tx(mode, "3 sama = ⭐", "3 same = ⭐"))
                row(.energy, tx(mode, "Energi → beli kartu", "Energy → buy cards"))
                row(.heal, tx(mode, "Sembuh +1 ❤️", "Heal +1 ❤️"))
                row(.smash, tx(mode, "Pukul −1 ❤️", "Smash −1 ❤️"))
            }
        }
    }
    private func row(_ f: KoTFace, _ text: String) -> some View {
        HStack(spacing: 8) {
            Text(f.symbol).font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                .frame(width: 36, height: 36).background(f.color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(text).font(.system(.subheadline, design: .rounded, weight: .semibold))
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 5. Tokyo: entering the city

private struct KoTTokyoAnimation: View {
    @Environment(\.lang) private var mode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var timer: Timer?

    var body: some View {
        KidsCard(title: "Tokyo", emoji: "🏙️") {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0xFF2B2D5C), Color(hex: 0xFF5B3E9E)], startPoint: .top, endPoint: .bottom))
                Text("🏙️").font(.system(size: 70)).offset(y: 18)
                // The player's monster enters Tokyo at step 1.
                Text("🦖").font(.system(size: 44))
                    .offset(x: step >= 1 ? 0 : -120, y: step >= 1 ? -10 : 30)
                    .scaleEffect(step == 3 ? 0.9 : 1)
                // The other monsters attack at step 3.
                ForEach(Array(["🦍", "🐙", "🤖"].enumerated()), id: \.offset) { i, m in
                    Text(m).font(.system(size: 30))
                        .offset(x: [-110, 0, 110][i] * (step == 3 ? 0.55 : 1), y: 55)
                }
                if step == 3 { Text("👊💥").font(.system(size: 30)).offset(y: -45).transition(.scale) }
                Text(caption).font(.system(.headline, design: .rounded, weight: .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.black.opacity(0.35), in: Capsule())
                    .offset(y: -78)
                    .id(step)
                    .transition(.opacity)
            }
            .frame(height: 210)
            .clipped()
        }
        .onAppear(perform: start)
        .onDisappear { timer?.invalidate() }
    }

    private var caption: String {
        switch step {
        case 0: tx(mode, "Tokyo kosong…", "Tokyo is empty…")
        case 1: tx(mode, "Masuk Tokyo: +1 ⭐", "Enter Tokyo: +1 ⭐")
        case 2: tx(mode, "Mulai giliran di sini: +2 ⭐", "Start your turn here: +2 ⭐")
        default: tx(mode, "Tapi semua memukulmu & tak bisa ❤️", "But everyone smashes you & no ❤️")
        }
    }

    private func start() {
        guard !reduceMotion else { step = 2; return }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: true) { _ in
            Task { @MainActor in withAnimation(.spring(duration: 0.6, bounce: 0.35)) { step = (step + 1) % 4 } }
        }
    }
}

// MARK: - 6. Chart: race to 20 ⭐ (Swift Charts)

private struct KoTRaceChart: View {
    @Environment(\.pal) private var p
    @Environment(\.lang) private var mode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    struct Racer: Identifiable { let id: String; let emoji: String; var points: Int; let color: Color }
    @State private var racers: [Racer] = [
        Racer(id: "Rex", emoji: "🦖", points: 0, color: Color(hex: 0xFF34C759)),
        Racer(id: "Kong", emoji: "🦍", points: 0, color: Color(hex: 0xFF8E6E53)),
        Racer(id: "Octo", emoji: "🐙", points: 0, color: Color(hex: 0xFFAF52DE)),
        Racer(id: "Robo", emoji: "🤖", points: 0, color: Color(hex: 0xFF5AC8FA)),
    ]
    @State private var turn = 0
    @State private var winner: String?
    @State private var timer: Timer?

    var body: some View {
        KidsCard(title: tx(mode, "Balapan ke 20 ⭐", "Race to 20 ⭐"), emoji: "📊") {
            Chart {
                ForEach(racers) { r in
                    BarMark(x: .value("⭐", r.points), y: .value("Monster", "\(r.emoji) \(r.id)"))
                        .foregroundStyle(r.color.gradient)
                        .cornerRadius(6)
                        .annotation(position: .trailing) {
                            Text("\(r.points)").font(.system(.caption, design: .rounded, weight: .bold))
                        }
                }
                RuleMark(x: .value("Finish", 20))
                    .foregroundStyle(.yellow)
                    .lineStyle(StrokeStyle(lineWidth: 3, dash: [6, 4]))
                    .annotation(position: .top, alignment: .trailing) { Text("🏁 20").font(.caption.weight(.bold)) }
            }
            .chartXScale(domain: 0...22)
            .chartXAxis { AxisMarks(values: [0, 5, 10, 15, 20]) }
            .frame(height: 190)
            HStack {
                Text(winner.map { tx(mode, "\($0) menang! 👑", "\($0) wins! 👑") } ?? tx(mode, "Giliran \(turn)", "Turn \(turn)"))
                    .font(.system(.headline, design: .rounded))
                    .contentTransition(.numericText())
                Spacer()
                Button(action: race) { Label(tx(mode, "Balapan!", "Race!"), systemImage: "flag.checkered") }
                    .buttonStyle(.bordered).buttonBorderShape(.capsule).tint(p.tint)
            }
        }
        .onDisappear { timer?.invalidate() }
    }

    /// Simple simulation: each turn a monster gets 0–4 ⭐ (an example, not real data) until one reaches 20.
    private func race() {
        timer?.invalidate()
        for i in racers.indices { racers[i].points = 0 }
        turn = 0; winner = nil
        timer = Timer.scheduledTimer(withTimeInterval: reduceMotion ? 0.05 : 0.6, repeats: true) { t in
            Task { @MainActor in
                withAnimation(.spring(duration: 0.5)) {
                    turn += 1
                    for i in racers.indices { racers[i].points = min(20, racers[i].points + Int.random(in: 0...4)) }
                }
                if let w = racers.first(where: { $0.points >= 20 }) {
                    winner = "\(w.emoji) \(w.id)"
                    t.invalidate()
                }
            }
        }
    }
}
