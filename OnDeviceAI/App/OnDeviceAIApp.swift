import SwiftUI

@main
struct OnDeviceAIApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
        }
    }
}

/// Native TabView + one NavigationStack per tab. On iOS 26+ the tab bar, navigation bars, toolbars and
/// search field get Liquid Glass automatically; the chat input uses glassEffect explicitly (AIChatView).
struct RootView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TabView(selection: $state.tab) {
            Tab(tx(state.language, "Game", "Games"), systemImage: "dice.fill", value: .games) { GamesView() }
            Tab(tx(state.language, "Tanya AI", "Ask AI"), systemImage: "sparkles", value: .ask) { AIChatView() }
            Tab(tx(state.language, "Pengaturan", "Settings"), systemImage: "gearshape.fill", value: .settings) { SettingsView() }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(state.accent.color)
        .environment(\.pal, Palette(tint: state.accent.color, dark: scheme == .dark))
        .environment(\.lang, state.language)
        .preferredColorScheme(state.appearance.scheme)
    }
}
