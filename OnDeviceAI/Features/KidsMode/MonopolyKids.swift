import SwiftUI
import Charts

// Kids Mode: Monopoly. How to win, a mini board to roll and move, rent chart, ways out of jail.

// MARK: - Monopoly

struct MonopolyKidsView: View {
    @Environment(\.lang) private var mode
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                KidsHero(emojis: ["🎩", "🚗", "🐕", "🚢", "💵"],
                         title: tx(mode, "Jadi tuan tanah terkaya!", "Be the richest landlord!"),
                         pills: ["👥 2–6", "⏱ 60–180 min", tx(mode, "🧒 8+ (Junior 5+)", "🧒 8+ (Junior 5+)")],
                         colors: [Color(hex: 0xFFB8F2C9), Color(hex: 0xFF7FD6A2), Color(hex: 0xFFFFE08A)])
                MonopolyWin()
                MonopolyBoard()
                MonopolyRentChart()
                KidsCard(title: tx(mode, "Masuk penjara? 3 cara keluar", "In jail? 3 ways out"), emoji: "🚔") {
                    HStack(spacing: 10) {
                        FlipCard(emoji: "💵", name: "M50", meaning: tx(mode, "Bayar M50", "Pay M50"), color: Color(hex: 0xFF2F9E44))
                        FlipCard(emoji: "🎫", name: tx(mode, "Kartu bebas", "Free card"), meaning: tx(mode, "Pakai kartu Bebas Penjara", "Use a Get Out of Jail Free card"), color: Color(hex: 0xFFF08C00))
                        FlipCard(emoji: "🎲🎲", name: tx(mode, "Dadu kembar", "Doubles"), meaning: tx(mode, "Lempar angka kembar", "Roll doubles"), color: Color(hex: 0xFF1C7ED6))
                    }
                }
                Text(tx(mode, "Beli, bangun, tukar! 🏠", "Buy, build, trade! 🏠")).font(.system(.title3, design: .rounded, weight: .bold)).padding(.vertical, 12)
            }
            .padding(16)
        }
    }
}

/// The last player who is not bankrupt wins.
private struct MonopolyWin: View {
    @Environment(\.lang) private var mode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var timer: Timer?
    private let tokens = ["🎩", "🚗", "🐕", "🚢"]

    var body: some View {
        KidsCard(title: tx(mode, "Cara menang", "How to win"), emoji: "🏆") {
            HStack(alignment: .bottom, spacing: 14) {
                ForEach(Array(tokens.enumerated()), id: \.offset) { i, t in
                    let broke = i < step
                    let winner = step == tokens.count - 1 && i == tokens.count - 1
                    VStack(spacing: 4) {
                        Text(winner ? "👑" : " ").font(.title3)
                        RoundedRectangle(cornerRadius: 6).fill(broke ? AnyShapeStyle(Color.gray.opacity(0.3)) : AnyShapeStyle(Color.green.gradient))
                            .frame(width: 26, height: broke ? 6 : (winner ? 90 : 60))
                        Text(broke ? "💸" : t).font(.system(size: 30)).opacity(broke ? 0.5 : 1)
                    }
                    .frame(maxWidth: .infinity)
                    .animation(.spring(duration: 0.5), value: step)
                }
            }
            Text(tx(mode, "Yang terakhir tidak bangkrut menang!", "The last player who isn't bankrupt wins!"))
                .font(.system(.headline, design: .rounded)).frame(maxWidth: .infinity)
        }
        .onAppear {
            guard !reduceMotion else { step = tokens.count - 1; return }
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 1.1, repeats: true) { _ in
                Task { @MainActor in step = step >= tokens.count - 1 ? 0 : step + 1 }
            }
        }
        .onDisappear { timer?.invalidate() }
    }
}

/// Mini 12-space board: roll 2 dice, move, pass GO +200, buy property, go to jail.
private struct MonopolyBoard: View {
    @Environment(\.pal) private var p
    @Environment(\.lang) private var mode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    struct Space { let emoji: String; let name: String; let color: Color?; let price: Int }
    private let spaces: [Space] = [
        Space(emoji: "🏁", name: "GO", color: nil, price: 0),
        Space(emoji: "🟫", name: "Old Kent", color: Color(hex: 0xFF8B5A2B), price: 60),
        Space(emoji: "❓", name: "Chance", color: nil, price: 0),
        Space(emoji: "🩵", name: "Angel", color: Color(hex: 0xFF74C0FC), price: 100),
        Space(emoji: "🚔", name: "Jail", color: nil, price: 0),
        Space(emoji: "🩷", name: "Pall Mall", color: Color(hex: 0xFFF783AC), price: 140),
        Space(emoji: "🟧", name: "Bow St", color: Color(hex: 0xFFFF922B), price: 180),
        Space(emoji: "🅿️", name: "Parking", color: nil, price: 0),
        Space(emoji: "🟥", name: "Strand", color: Color(hex: 0xFFFA5252), price: 220),
        Space(emoji: "🟨", name: "Leicester", color: Color(hex: 0xFFFCC419), price: 260),
        Space(emoji: "👮", name: "Go to Jail", color: nil, price: 0),
        Space(emoji: "🟩", name: "Regent", color: Color(hex: 0xFF40C057), price: 300),
    ]
    @State private var pos = 0
    @State private var cash = 1500
    @State private var owned: Set<Int> = []
    @State private var dice = (1, 1)
    @State private var message = ""
    @State private var moving = false

    // Space positions around a 4×4 grid (clockwise from bottom left).
    private let cells: [(Int, Int)] = [(3, 0), (2, 0), (1, 0), (0, 0), (0, 1), (0, 2), (0, 3), (1, 3), (2, 3), (3, 3), (3, 2), (3, 1)]

    var body: some View {
        KidsCard(title: tx(mode, "Lempar & jalan!", "Roll & move!"), emoji: "🎲") {
            GeometryReader { geo in
                let s = geo.size.width / 4
                ZStack {
                    ForEach(0..<spaces.count, id: \.self) { i in
                        let (r, c) = cells[i]
                        VStack(spacing: 1) {
                            Text(spaces[i].emoji).font(.system(size: 18))
                            Text(spaces[i].name).font(.system(size: 9, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
                            if owned.contains(i) { Text("🏠").font(.system(size: 10)) }
                        }
                        .frame(width: s - 4, height: s - 4)
                        .background((spaces[i].color ?? Color.gray).opacity(spaces[i].color == nil ? 0.12 : 0.25), in: RoundedRectangle(cornerRadius: 8))
                        .position(x: CGFloat(c) * s + s / 2, y: CGFloat(r) * s + s / 2)
                    }
                    VStack(spacing: 4) {
                        Text("💵 M\(cash)").font(.system(.headline, design: .rounded, weight: .heavy)).contentTransition(.numericText())
                        Text("🎲 \(dice.0) + \(dice.1)").font(.system(.subheadline, design: .rounded, weight: .bold))
                    }
                    .position(x: 2 * s, y: 2 * s)
                    let (r, c) = cells[pos]
                    Text("🎩").font(.system(size: 26))
                        .position(x: CGFloat(c) * s + s / 2, y: CGFloat(r) * s + s / 2 - 12)
                        .animation(.spring(duration: 0.25), value: pos)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            Text(message.isEmpty ? tx(mode, "Lewat GO = +200 💵", "Pass GO = +200 💵") : message)
                .font(.system(.subheadline, design: .rounded, weight: .semibold)).frame(maxWidth: .infinity)
            Button(action: roll) {
                Label(tx(mode, "Lempar dadu!", "Roll the dice!"), systemImage: "dice.fill")
                    .font(.system(.headline, design: .rounded)).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(p.tint)
            .disabled(moving)
        }
    }

    private func roll() {
        let a = Int.random(in: 1...6), b = Int.random(in: 1...6)
        dice = (a, b)
        moving = true
        let steps = a + b
        Task { @MainActor in
            for _ in 0..<steps {
                try? await Task.sleep(nanoseconds: reduceMotion ? 0 : 180_000_000)
                withAnimation { pos = (pos + 1) % spaces.count }
                if pos == 0 { withAnimation { cash += 200 } }
            }
            land(doubles: a == b)
            moving = false
        }
    }

    private func land(doubles: Bool) {
        let sp = spaces[pos]
        var text: String
        if sp.name == "Go to Jail" {
            withAnimation { pos = 4 }
            text = tx(mode, "Masuk penjara! 🚔", "Go to jail! 🚔")
        } else if sp.price > 0, !owned.contains(pos), cash >= sp.price {
            withAnimation { cash -= sp.price; owned.insert(pos) }
            text = tx(mode, "Beli \(sp.name) M\(sp.price) 🏠", "Bought \(sp.name) for M\(sp.price) 🏠")
        } else if sp.price > 0, owned.contains(pos) {
            text = tx(mode, "Milikmu sendiri 😎", "You own this 😎")
        } else {
            text = "\(sp.emoji) \(sp.name)"
        }
        if doubles, sp.name != "Go to Jail" { text += tx(mode, " · Kembar! Lempar lagi 🎲", " · Doubles! Roll again 🎲") }
        message = text
    }
}

/// St. James Place (orange) rent per number of houses: the 3rd house gives the biggest jump.
private struct MonopolyRentChart: View {
    @Environment(\.lang) private var mode
    @State private var shown = false
    private let rent: [(String, Int)] = [("🏠×0", 14), ("🏠×1", 70), ("🏠×2", 200), ("🏠×3", 550), ("🏠×4", 750), ("🏨", 950)]

    var body: some View {
        KidsCard(title: tx(mode, "Sewa naik kalau ada rumah", "Houses make rent jump"), emoji: "📊") {
            Chart(Array(rent.enumerated()), id: \.offset) { i, r in
                BarMark(x: .value("Houses", r.0), y: .value("Rent", shown ? r.1 : 0))
                    .foregroundStyle(i == 3 ? Color.orange.gradient : Color.orange.opacity(0.45).gradient)
                    .cornerRadius(6)
                    .annotation(position: .top) { Text("M\(r.1)").font(.system(.caption2, design: .rounded, weight: .bold)) }
            }
            .chartYScale(domain: 0...1050)
            .chartYAxis(.hidden)
            .frame(height: 170)
            Text(tx(mode, "Rumah ke-3 = lompatan terbesar! 🚀", "The 3rd house = biggest jump! 🚀"))
                .font(.system(.headline, design: .rounded))
        }
        .onAppear { withAnimation(.spring(duration: 0.9).delay(0.2)) { shown = true } }
    }
}

