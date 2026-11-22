import SwiftUI

// MARK: - Language

/// The language the app shows and the assistant answers in.
/// The on-device model is prompted in English; Indonesian answers are produced by a second "restyle" pass.
enum AppLanguage: String, CaseIterable, Identifiable {
    case english, indonesian
    var id: String { rawValue }
    var isEn: Bool { self == .english }
    var label: String { self == .english ? "English" : "Bahasa Indonesia" }
}

/// Pick the string for the current language.
func tx(_ l: AppLanguage, _ id: String, _ en: String) -> String { l.isEn ? en : id }

// MARK: - Placeholder mascots

/// Three placeholder personas. Replace the names, prompts and artwork with your own characters.
enum Mascot: String, CaseIterable, Identifiable {
    case a, b, c
    var id: String { rawValue }
    var name: String {
        switch self {
        case .a: "Mascot A"
        case .b: "Mascot B"
        case .c: "Mascot C"
        }
    }
    var tagline: String {
        switch self {
        case .a: "Cheerful and friendly"
        case .b: "Funny and cheeky"
        case .c: "Very proper and formal"
        }
    }
    var color: Color {
        switch self {
        case .a: Color(hex: 0xFFFF9F43)
        case .b: Color(hex: 0xFF10AC84)
        case .c: Color(hex: 0xFF5F27CD)
        }
    }
    /// Persona line for the system instructions (stage 1, always English).
    var persona: String {
        switch self {
        case .a: "You are \(name), the cheerful mascot of a board game guide app. Reply in clear, friendly American English."
        case .b: "You are \(name), a funny, cheeky mascot of a board game guide app. Reply in clear English with a playful tone."
        case .c: "You are \(name), a very proper, slightly formal mascot of a board game guide app. Reply in British English with dry, gentle wit. Never greet with 'Hi' or 'Hey'."
        }
    }
    /// Voice character for read aloud (see AISpeech.swift).
    var voice: AISpeaker.VoiceStyle {
        switch self {
        case .a: .childlike
        case .b: .lowered
        case .c: .britishMale
        }
    }
}

/// The mascot's facial expression, chosen by the model for every reply (see AIReply).
enum Mood: String, CaseIterable {
    case happy, wink, smug, thinking, shock, talk
    var emoji: String {
        switch self {
        case .happy: "😄"
        case .wink: "😉"
        case .smug: "😏"
        case .thinking: "🤔"
        case .shock: "😮"
        case .talk: "🙂"
        }
    }
}

// MARK: - Accent & palette

enum Accent: String, CaseIterable, Identifiable {
    case yellow, orange, green, pink, blue
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .yellow: Color(hex: 0xFFF5B700)
        case .orange: Color(hex: 0xFFFF7A1A)
        case .green: Color(hex: 0xFF2BB673)
        case .pink: Color(hex: 0xFFFF4F9A)
        case .blue: Color(hex: 0xFF2F80ED)
        }
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// A tiny palette passed through the environment.
struct Palette {
    var tint: Color
    var dark: Bool
    var ink: Color { .primary }
    var ink2: Color { .secondary }
    var surface: Color { Color(.secondarySystemGroupedBackground) }
    var paper: Color { Color(.systemGroupedBackground) }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette(tint: Accent.yellow.color, dark: false)
}

private struct LanguageKey: EnvironmentKey {
    static let defaultValue = AppLanguage.english
}

extension EnvironmentValues {
    var pal: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
    var lang: AppLanguage {
        get { self[LanguageKey.self] }
        set { self[LanguageKey.self] = newValue }
    }
}

extension Color {
    /// 0xAARRGGBB.
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: Double((hex >> 24) & 0xFF) / 255)
    }
}
