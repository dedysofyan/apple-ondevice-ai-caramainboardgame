import Foundation

/// Catalogue filter shared by the Games tab and the searchCatalog tool, so their counts always match.
struct GameFilter: Equatable {
    var query = ""
    var players: Int?
    var age: Int?
    var maxMinutes: Int?
    /// light / medium / heavy
    var complexity: String?

    var isActive: Bool { !query.isEmpty || players != nil || age != nil || maxMinutes != nil || complexity != nil }

    /// "4 players · age 6 · ≤ 30 min"
    var summary: String {
        var p: [String] = []
        if !query.isEmpty { p.append("“\(query)”") }
        if let players { p.append("\(players) players") }
        if let age { p.append("age \(age)") }
        if let maxMinutes { p.append("≤ \(maxMinutes) min") }
        if let complexity { p.append(complexity) }
        return p.joined(separator: " · ")
    }

    /// Sort: games with a guide first, then best age fit, then A–Z.
    /// A box age up to 2 years above the child's age still matches (play with an adult's help).
    func apply(games: [Game], guides: [PlayGuide]) -> [Game] {
        let withGuide = Set(guides.map(\.game))
        let q = query.lowercased()
        return games.filter { g in
            if !q.isEmpty, !(g.name.lowercased().contains(q) || g.summary.lowercased().contains(q) || g.keywords.contains { $0.contains(q) }) { return false }
            if let players, !(g.minPlayers...g.maxPlayers).contains(players) { return false }
            if let age, g.minAge > age + 2 { return false }
            if let maxMinutes, g.minMinutes > maxMinutes { return false }
            if let complexity {
                switch complexity {
                case "light": if g.weight > 2 { return false }
                case "medium": if g.weight < 2 || g.weight > 3.5 { return false }
                default: if g.weight < 3.5 { return false }
                }
            }
            return true
        }
        .sorted { a, b in
            let ga = withGuide.contains(a.name), gb = withGuide.contains(b.name)
            if ga != gb { return ga }
            if let age, (a.minAge <= age) != (b.minAge <= age) { return a.minAge <= age }
            return a.name < b.name
        }
    }
}
