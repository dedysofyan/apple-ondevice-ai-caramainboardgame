import SwiftUI

enum AppTab: Hashable { case games, ask, settings }

/// App-wide state. The assistant's tools (changeTheme, changeLanguage) write to it directly.
@MainActor
final class AppState: ObservableObject {
    let games = SampleData.games
    let guides = SampleData.guides

    @Published var tab: AppTab = .games
    @Published var path = NavigationPath()
    @Published var language: AppLanguage { didSet { save("language", language.rawValue) } }
    @Published var mascot: Mascot { didSet { save("mascot", mascot.rawValue) } }
    @Published var accent: Accent { didSet { save("accent", accent.rawValue) } }
    @Published var appearance: Appearance { didSet { save("appearance", appearance.rawValue) } }
    /// Game the Ask tab is focused on (nil = general chat).
    @Published var askFocus: PlayGuide?
    /// Prompt sent to the Ask tab from elsewhere (e.g. "Ask about this game").
    @Published var pendingAsk: String?

    private let prefs = UserDefaults.standard

    init() {
        language = AppLanguage(rawValue: prefs.string(forKey: "language") ?? "") ?? .english
        mascot = Mascot(rawValue: prefs.string(forKey: "mascot") ?? "") ?? .a
        accent = Accent(rawValue: prefs.string(forKey: "accent") ?? "") ?? .yellow
        appearance = Appearance(rawValue: prefs.string(forKey: "appearance") ?? "") ?? .system
    }

    private func save(_ k: String, _ v: String) { prefs.set(v, forKey: k) }

    func guide(for game: Game) -> PlayGuide? { guides.first { $0.game == game.name } }
    func game(for guide: PlayGuide) -> Game? { games.first { $0.name == guide.game } }

    /// Open the Ask tab about one guide, optionally sending a prompt.
    func ask(about guide: PlayGuide?, prompt: String? = nil) {
        askFocus = guide
        pendingAsk = prompt
        tab = .ask
    }

    func open(_ guide: PlayGuide) {
        tab = .games
        path = NavigationPath()
        path.append(guide)
    }
}
