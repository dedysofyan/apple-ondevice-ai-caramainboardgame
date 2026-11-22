import SwiftUI

// Chat history, stored locally (a JSON file in Application Support; it never leaves the device).
// Starting a new chat keeps the old one; users can reopen, continue or delete chats.

struct ChatRecord: Codable, Identifiable, Equatable {
    struct Msg: Codable, Equatable {
        var user: Bool
        var text: String
        var english: String?
        var games: [String] = []
    }
    var id = UUID()
    /// guide:<slug> or general (see AIChat.memoryKey).
    var focusKey: String
    var gameName: String?
    var updatedAt = Date()
    var messages: [Msg]

    var title: String { messages.first(where: \.user)?.text ?? "…" }
}

@MainActor
final class ChatHistoryStore: ObservableObject {
    static let shared = ChatHistoryStore()
    @Published private(set) var records: [ChatRecord] = []
    private let maxRecords = 100, maxMessages = 40

    private var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ai-chat-history.json")
    }

    private init() {
        if let d = try? Data(contentsOf: url), let r = try? JSONDecoder().decode([ChatRecord].self, from: d) { records = r }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(records) { try? d.write(to: url, options: [.atomic, .completeFileProtection]) }
    }

    /// Insert or update a chat; newest first.
    func upsert(_ r: ChatRecord) {
        var r = r
        r.updatedAt = Date()
        r.messages = Array(r.messages.suffix(maxMessages))
        records.removeAll { $0.id == r.id }
        records.insert(r, at: 0)
        if records.count > maxRecords { records.removeLast(records.count - maxRecords) }
        save()
    }

    func latest(for key: String) -> ChatRecord? { records.first { $0.focusKey == key } }
    func record(_ id: UUID) -> ChatRecord? { records.first { $0.id == id } }
    func delete(_ id: UUID) { records.removeAll { $0.id == id }; save() }
    func clearAll() { records = []; save() }
}

/// Previous chats: tap to continue, swipe to delete, or clear all.
struct ChatHistoryView: View {
    @ObservedObject var store = ChatHistoryStore.shared
    @Environment(\.lang) private var lang
    @Environment(\.dismiss) private var dismiss
    let currentID: UUID?
    let open: (ChatRecord) -> Void
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            List {
                if store.records.isEmpty {
                    ContentUnavailableView(tx(lang, "Belum ada obrolan", "No chats yet"), systemImage: "bubble.left.and.bubble.right",
                                           description: Text(tx(lang, "Obrolan dengan AI tersimpan di perangkat ini.", "Your AI chats are saved on this device.")))
                }
                ForEach(store.records) { r in
                    Button { open(r); dismiss() } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(r.title).font(.body.weight(.semibold)).lineLimit(2)
                                if r.id == currentID { Spacer(); Text(tx(lang, "sekarang", "current")).font(.caption2.weight(.bold)).foregroundStyle(.tint) }
                            }
                            Text([r.gameName ?? tx(lang, "Umum", "General"),
                                  tx(lang, "\(r.messages.count) pesan", "\(r.messages.count) messages"),
                                  r.updatedAt.formatted(.relative(presentation: .named))].joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { idx in for i in idx { store.delete(store.records[i].id) } }
            }
            .navigationTitle(tx(lang, "Obrolan sebelumnya", "Previous chats"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(tx(lang, "Tutup", "Close")) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(tx(lang, "Hapus semua", "Clear all"), role: .destructive) { confirmClear = true }
                        .disabled(store.records.isEmpty)
                }
            }
            .confirmationDialog(tx(lang, "Hapus semua riwayat obrolan AI?", "Delete all AI chat history?"), isPresented: $confirmClear, titleVisibility: .visible) {
                Button(tx(lang, "Hapus semua", "Delete all"), role: .destructive) { store.clearAll() }
            } message: {
                Text(tx(lang, "Tidak bisa dibatalkan.", "This can't be undone."))
            }
        }
    }
}
