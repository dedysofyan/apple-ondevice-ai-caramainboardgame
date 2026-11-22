import SwiftUI
import FoundationModels

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.lang) private var lang
    @ObservedObject private var history = ChatHistoryStore.shared

    var body: some View {
        NavigationStack {
            Form {
                Section(tx(lang, "Maskot", "Mascot")) {
                    Picker(tx(lang, "Maskot", "Mascot"), selection: $state.mascot) {
                        ForEach(Mascot.allCases) { m in
                            HStack { MascotFace(mascot: m, mood: .happy, size: 28); VStack(alignment: .leading) { Text(m.name); Text(m.tagline).font(.caption).foregroundStyle(.secondary) } }
                                .tag(m)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section(tx(lang, "Bahasa", "Language")) {
                    Picker(tx(lang, "Bahasa", "Language"), selection: $state.language) {
                        ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section(tx(lang, "Tampilan", "Appearance")) {
                    Picker(tx(lang, "Mode", "Mode"), selection: $state.appearance) {
                        ForEach(Appearance.allCases) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker(tx(lang, "Warna aksen", "Accent"), selection: $state.accent) {
                        ForEach(Accent.allCases) { a in Label(a.rawValue.capitalized, systemImage: "circle.fill").foregroundStyle(a.color).tag(a) }
                    }
                }
                Section("Apple Intelligence") {
                    LabeledContent(tx(lang, "Model on-device", "On-device model"), value: availability)
                    LabeledContent(tx(lang, "Jendela konteks", "Context window"), value: "\(SystemLanguageModel.default.contextSize.formatted()) tokens")
                    Button(tx(lang, "Hapus riwayat obrolan", "Delete chat history"), role: .destructive) { history.clearAll() }
                        .disabled(history.records.isEmpty)
                }
            }
            .navigationTitle(tx(lang, "Pengaturan", "Settings"))
        }
    }

    private var availability: String {
        switch SystemLanguageModel.default.availability {
        case .available: "Available"
        case .unavailable(let r): "Unavailable (\(String(describing: r)))"
        }
    }
}
