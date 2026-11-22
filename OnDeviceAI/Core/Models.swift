import Foundation

/// One game in the catalogue.
struct Game: Identifiable, Hashable {
    let id: Int
    let name: String
    let minPlayers: Int
    let maxPlayers: Int
    let minMinutes: Int
    let maxMinutes: Int
    let minAge: Int
    /// Complexity from 1 (very light) to 5 (very heavy).
    let weight: Double
    let summary: String
    let keywords: [String]

    var players: String { minPlayers == maxPlayers ? "\(minPlayers) players" : "\(minPlayers)–\(maxPlayers) players" }
    var minutes: String { minMinutes == maxMinutes ? "\(minMinutes) min" : "\(minMinutes)–\(maxMinutes) min" }
    var age: String { "\(minAge)+" }
    var symbol: String {
        switch id {
        case 1: "lizard.fill"
        case 2: "rectangle.portrait.on.rectangle.portrait.fill"
        default: "house.fill"
        }
    }
}

/// A how-to-play guide. The assistant may only explain rules that are written here (see ReadGuideTool).
struct PlayGuide: Identifiable, Hashable {
    struct Win: Hashable { let goal: String; let keys: [String] }
    struct Section: Hashable { let heading: String; let paragraphs: [String]; var bullets: [String] = [] }

    var id: String { slug }
    let slug: String
    let game: String
    let intro: String
    let win: Win
    let sections: [Section]
    let tips: [String]
    let keywords: [String]
    /// Has an animated Kids Mode screen.
    var kids = true
}

/// Sample data for the demo. Text written for this sample; game names are trademarks of their owners.
enum SampleData {
    static let games: [Game] = [
        Game(id: 1, name: "King of Tokyo", minPlayers: 2, maxPlayers: 6, minMinutes: 30, maxMinutes: 30, minAge: 8, weight: 1.5,
             summary: "Giant monsters roll dice to smash each other and take over Tokyo.",
             keywords: ["monsters", "dice", "kaiju", "family", "party"]),
        Game(id: 2, name: "UNO", minPlayers: 2, maxPlayers: 10, minMinutes: 15, maxMinutes: 30, minAge: 7, weight: 1.0,
             summary: "Match cards by colour or number and be the first to empty your hand.",
             keywords: ["cards", "colours", "family", "kids", "party"]),
        Game(id: 3, name: "Monopoly", minPlayers: 2, maxPlayers: 8, minMinutes: 60, maxMinutes: 180, minAge: 8, weight: 1.7,
             summary: "Buy properties, build houses and collect rent until everyone else goes bankrupt.",
             keywords: ["property", "money", "trading", "dice", "family", "classic"]),
    ]

    static let guides: [PlayGuide] = [
        PlayGuide(
            slug: "king-of-tokyo", game: "King of Tokyo",
            intro: "Each player is a giant monster. Roll dice to score stars, gain energy, heal and smash the other monsters.",
            win: .init(goal: "Be the first monster to reach 20 victory points (stars), or be the last monster still standing.",
                       keys: ["Stars come from dice, from entering Tokyo and from some cards.", "A monster at 0 health is out of the game."]),
            sections: [
                .init(heading: "Setup", paragraphs: ["Each monster starts with 10 health and 0 stars. Put the energy cubes in a pile and lay out 3 power cards face up."]),
                .init(heading: "Your turn: roll", paragraphs: ["Roll the 6 dice. You may re-roll any of them up to two more times, keeping the ones you like."]),
                .init(heading: "Your turn: resolve the dice", paragraphs: ["Apply the dice you ended with:"],
                      bullets: ["Three of the same number scores that many stars; each extra matching die adds 1 star.",
                                "Each lightning bolt gives 1 energy cube.",
                                "Each heart heals 1 health (not while you are in Tokyo; maximum 10).",
                                "Each claw deals 1 damage: from outside Tokyo you hit the monster in Tokyo; from inside Tokyo you hit every monster outside."]),
                .init(heading: "Tokyo", paragraphs: ["If Tokyo is empty, you must enter it. Entering gives 1 star, and starting your turn in Tokyo gives 2 stars. When a monster in Tokyo is damaged, it may leave, and the attacker takes its place."]),
                .init(heading: "Buy cards", paragraphs: ["At the end of your turn you may spend energy to buy power cards. You may also pay 2 energy to replace the 3 face-up cards."]),
            ],
            tips: ["Staying in Tokyo scores fast but you cannot heal there.", "Energy cards can win the game; don't ignore them."],
            keywords: ["kot", "monster", "tokyo"]),
        PlayGuide(
            slug: "uno", game: "UNO",
            intro: "A fast card game: match the top card of the discard pile and be the first to play all your cards.",
            win: .init(goal: "Be the first to play every card in your hand. The round winner scores points for the cards left in other players' hands; first to 500 points wins the game.",
                       keys: ["Say \"UNO\" when you play your second-to-last card.", "If you are caught not saying it, draw 2 cards."]),
            sections: [
                .init(heading: "Setup", paragraphs: ["Shuffle and deal 7 cards to each player. Turn the top card of the draw pile face up to start the discard pile."]),
                .init(heading: "Your turn", paragraphs: ["Play one card that matches the top card by colour, number or symbol. A Wild card can always be played. If you can't play, draw 1 card; if it fits, you may play it."]),
                .init(heading: "Action cards", paragraphs: ["Action cards change the game:"],
                      bullets: ["Skip: the next player loses their turn.",
                                "Reverse: the direction of play changes.",
                                "Draw Two: the next player draws 2 cards and loses their turn.",
                                "Wild: choose the colour that continues play.",
                                "Wild Draw Four: choose the colour; the next player draws 4 cards and loses their turn. Officially you may only play it when you have no card matching the current colour."]),
                .init(heading: "Scoring", paragraphs: ["Number cards score their face value. Skip, Reverse and Draw Two score 20. Wild and Wild Draw Four score 50."]),
            ],
            tips: ["Save a Wild card for when you are stuck.", "Watch who is close to UNO and use Draw Two on them."],
            keywords: ["uno card", "cards"]),
        PlayGuide(
            slug: "monopoly", game: "Monopoly",
            intro: "Move around the board buying properties, then charge rent to everyone who lands on them.",
            win: .init(goal: "Be the last player who is not bankrupt.",
                       keys: ["A player who can't pay what they owe is bankrupt and leaves the game.", "Owning a full colour set lets you build houses and hotels."]),
            sections: [
                .init(heading: "Setup", paragraphs: ["Each player picks a token and starts on GO with 1,500 in money. One player is the Banker."]),
                .init(heading: "Your turn", paragraphs: ["Roll two dice and move that many spaces clockwise. Every time you pass GO, collect 200. If you roll doubles, roll again; three doubles in a row sends you to Jail."]),
                .init(heading: "Properties", paragraphs: ["Land on an unowned property and you may buy it at its price; if you don't, it is auctioned. Land on someone else's property and you pay them rent."]),
                .init(heading: "Houses and hotels", paragraphs: ["When you own every property of one colour, you can buy houses, building evenly across the set. After four houses, a hotel can replace them. Houses raise the rent a lot."]),
                .init(heading: "Jail", paragraphs: ["You can get out of Jail by paying 50, using a Get Out of Jail Free card, or rolling doubles on one of your next three turns."]),
            ],
            tips: ["The third house on a property gives the biggest rent jump.", "Orange properties are landed on often because they sit after Jail."],
            keywords: ["property", "money", "landlord"]),
    ]
}
