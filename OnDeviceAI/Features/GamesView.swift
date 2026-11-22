import SwiftUI

struct GamesView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.pal) private var p
    @Environment(\.lang) private var lang
    @State private var query = ""

    private var results: [Game] { GameFilter(query: query).apply(games: state.games, guides: state.guides) }

    var body: some View {
        NavigationStack(path: $state.path) {
            List(results) { g in
                if let guide = state.guide(for: g) {
                    NavigationLink(value: guide) { row(g) }
                }
            }
            .navigationTitle(tx(lang, "Game", "Games"))
            .searchable(text: $query, prompt: tx(lang, "Cari game", "Search games"))
            .navigationDestination(for: PlayGuide.self) { GuideScreen(guide: $0) }
        }
    }

    private func row(_ g: Game) -> some View {
        HStack(spacing: 12) {
            Image(systemName: g.symbol).font(.title2).foregroundStyle(p.tint).frame(width: 44, height: 44)
                .background(p.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(g.name).font(.headline)
                Text("\(g.players) · \(g.minutes) · \(g.age)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// A guide with a Kids Mode toggle (animated, little text) in the toolbar.
struct GuideScreen: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.lang) private var lang
    let guide: PlayGuide
    @State private var kids = true

    var body: some View {
        Group {
            if kids { kidsView.transition(.opacity) } else { GuideView(guide: guide).transition(.opacity) }
        }
        .animation(.easeInOut(duration: 0.25), value: kids)
        .sensoryFeedback(.selection, trigger: kids)
        .navigationTitle(guide.game)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: $kids) { Label(tx(lang, "Mode anak", "Kids mode"), systemImage: "figure.and.child.holdinghands") }
                    .toggleStyle(.button)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { state.ask(about: guide) } label: { Label(tx(lang, "Tanya AI", "Ask AI"), systemImage: "sparkles") }
            }
        }
    }

    @ViewBuilder private var kidsView: some View {
        switch guide.slug {
        case "uno": UnoKidsView()
        case "monopoly": MonopolyKidsView()
        default: KingOfTokyoKidsView()
        }
    }
}

/// The plain text guide.
struct GuideView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.lang) private var lang
    let guide: PlayGuide

    var body: some View {
        List {
            Section { Text(guide.intro) }
            Section(tx(lang, "Cara menang", "How to win")) {
                Text(guide.win.goal).font(.body.weight(.semibold))
                ForEach(guide.win.keys, id: \.self) { Label($0, systemImage: "checkmark.circle") }
            }
            ForEach(Array(guide.sections.enumerated()), id: \.offset) { i, s in
                Section("\(i + 1). \(s.heading)") {
                    ForEach(s.paragraphs, id: \.self) { Text($0) }
                    ForEach(s.bullets, id: \.self) { Label($0, systemImage: "circle.fill").labelStyle(BulletLabel()) }
                }
            }
            Section(tx(lang, "Tips", "Tips")) { ForEach(guide.tips, id: \.self) { Label($0, systemImage: "lightbulb") } }
            Section {
                Button { state.ask(about: guide, prompt: "Explain one turn of \(guide.game) simply") } label: {
                    Label(tx(lang, "Tanya AI soal game ini", "Ask the AI about this game"), systemImage: "sparkles")
                }
            }
        }
    }
}

private struct BulletLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon.font(.system(size: 6))
            configuration.title
        }
    }
}
