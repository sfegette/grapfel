import Foundation

// MARK: - Retention mode

enum RetentionMode: String, CaseIterable, Identifiable, Codable {
    case sessionOnly = "session-only"
    case lastNTurns  = "last-n-turns"
    case unlimited   = "unlimited"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sessionOnly: return "Session only (no disk)"
        case .lastNTurns:  return "Last \(ConversationStore.maxTurns) turns"
        case .unlimited:   return "Unlimited (capped at \(ConversationStore.maxMessages) messages)"
        }
    }
}

// MARK: - Conversation record

struct ConversationRecord: Codable, Identifiable {
    var id: UUID
    var name: String
    var messages: [ChatMessage]
    var updatedAt: Date

    init(name: String = "New conversation", messages: [ChatMessage] = []) {
        self.id = UUID()
        self.name = name
        self.messages = messages
        self.updatedAt = Date()
    }
}

@Observable
@MainActor
final class ConversationStore {
    static let shared = ConversationStore()

    /// Hard cap on messages stored per conversation (~2 000 tokens × 200 = generous but bounded).
    nonisolated static let maxMessages = 200
    /// Turn-pairs retained under `.lastNTurns` mode (1 turn = 1 user + 1 assistant message).
    nonisolated static let maxTurns = 50

    private(set) var conversations: [ConversationRecord] = []
    private(set) var activeID: UUID?

    private let directory: URL

    var active: ConversationRecord? {
        conversations.first { $0.id == activeID }
    }

    init(directory: URL? = nil) {
        if let dir = directory {
            self.directory = dir
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.directory = support.appendingPathComponent("grapfel/conversations", isDirectory: true)
        }
        try? FileManager.default.createDirectory(
            at: self.directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        migrateIfNeeded()
        loadAll()
        if activeID == nil {
            createAndActivate()
        }
    }

    // MARK: - Actions

    func activate(_ id: UUID) {
        activeID = id
    }

    func save(_ record: ConversationRecord) {
        var bounded = record
        if bounded.messages.count > Self.maxMessages {
            bounded.messages = Array(bounded.messages.suffix(Self.maxMessages))
        }
        let url = fileURL(for: bounded.id)
        if let data = try? encoder().encode(bounded) {
            try? data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        if let idx = conversations.firstIndex(where: { $0.id == record.id }) {
            conversations[idx] = record
        } else {
            conversations.append(record)
        }
        conversations.sort { $0.updatedAt > $1.updatedAt }
    }

    func createAndActivate() {
        let record = ConversationRecord()
        save(record)
        activeID = record.id
    }

    func delete(_ record: ConversationRecord) {
        try? FileManager.default.removeItem(at: fileURL(for: record.id))
        conversations.removeAll { $0.id == record.id }
        if activeID == record.id {
            if let first = conversations.first {
                activeID = first.id
            } else {
                createAndActivate()
            }
        }
    }

    func rename(_ id: UUID, to name: String) {
        guard var record = conversations.first(where: { $0.id == id }) else { return }
        record.name = name
        save(record)
    }

    func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    // MARK: - Persistence

    private func loadAll() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return }
        let dec = decoder()
        conversations = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> ConversationRecord? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? dec.decode(ConversationRecord.self, from: data)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
        activeID = conversations.first?.id
    }

    // Migrate the pre-sidebar single conversation.json into the new directory.
    private func migrateIfNeeded() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let oldURL = support.appendingPathComponent("grapfel/conversation.json")
        guard FileManager.default.fileExists(atPath: oldURL.path),
              let data = try? Data(contentsOf: oldURL),
              let messages = try? JSONDecoder().decode([ChatMessage].self, from: data),
              !messages.isEmpty
        else {
            try? FileManager.default.removeItem(at: oldURL)
            return
        }
        let firstName = messages.first(where: { $0.role == .user })
            .map { String($0.content.prefix(40)).trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? "Imported conversation"
        var record = ConversationRecord(name: firstName, messages: messages)
        record.updatedAt = Date()
        save(record)
        try? FileManager.default.removeItem(at: oldURL)
    }

    private func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
