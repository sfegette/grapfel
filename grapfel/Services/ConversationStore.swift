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
    private let userDefaults: UserDefaults
    private let fallbackSupportDirectory: URL

    var active: ConversationRecord? {
        conversations.first { $0.id == activeID }
    }

    private var currentRetentionMode: RetentionMode {
        let rawValue = userDefaults.string(forKey: UserDefaultsKey.retentionMode) ?? RetentionMode.unlimited.rawValue
        return RetentionMode(rawValue: rawValue) ?? .unlimited
    }

    init(directory: URL? = nil, userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.fallbackSupportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("grapfel", isDirectory: true)
        if let dir = directory {
            self.directory = dir
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fallbackSupportDirectory
            self.directory = support.appendingPathComponent("grapfel/conversations", isDirectory: true)
        }
        try? FileManager.default.createDirectory(
            at: self.directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        if currentRetentionMode == .sessionOnly {
            purgeStoredConversations()
        } else {
            migrateIfNeeded()
            loadAll()
        }
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
        bounded.messages = applyRetentionLimit(to: bounded.messages)
        let url = fileURL(for: bounded.id)
        if currentRetentionMode == .sessionOnly {
            try? FileManager.default.removeItem(at: url)
            upsertInMemoryRecord(bounded)
            return
        }

        do {
            let data = try encoder().encode(bounded)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            upsertInMemoryRecord(bounded)
        } catch {
            return
        }
    }

    private func upsertInMemoryRecord(_ record: ConversationRecord) {
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

    func applyRetentionMode() {
        switch currentRetentionMode {
        case .sessionOnly:
            let activeConversation = active
            purgeStoredConversations()
            if let activeConversation {
                conversations = [activeConversation]
                activeID = activeConversation.id
            } else {
                conversations = []
                activeID = nil
            }
        case .lastNTurns, .unlimited:
            let currentRecords = conversations
            conversations = []
            for record in currentRecords {
                save(record)
            }
        }

        if activeID == nil {
            createAndActivate()
        }
    }

    func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    // MARK: - Persistence

    private func loadAll() {
        guard currentRetentionMode != .sessionOnly else {
            conversations = []
            activeID = nil
            return
        }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return }
        let dec = decoder()
        conversations = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> ConversationRecord? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                guard var record = try? dec.decode(ConversationRecord.self, from: data) else { return nil }
                record.messages = applyRetentionLimit(to: record.messages)
                return record
            }
            .sorted { $0.updatedAt > $1.updatedAt }
        activeID = conversations.first?.id
    }

    // Migrate the pre-sidebar single conversation.json into the new directory.
    private func migrateIfNeeded() {
        guard currentRetentionMode != .sessionOnly else {
            try? FileManager.default.removeItem(at: legacyConversationFileURL())
            return
        }

        let oldURL = legacyConversationFileURL()
        guard FileManager.default.fileExists(atPath: oldURL.path),
              let data = try? Data(contentsOf: oldURL),
              let messages = try? JSONDecoder().decode([ChatMessage].self, from: data),
              !messages.isEmpty
        else {
            try? FileManager.default.removeItem(at: oldURL)
            return
        }
        let firstName = messages.first(where: { $0.role == .user })
            .map { ConversationTitleFormatter.title(for: $0.content) }
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

    private func applyRetentionLimit(to messages: [ChatMessage]) -> [ChatMessage] {
        let maxMessages = switch currentRetentionMode {
        case .sessionOnly, .unlimited:
            Self.maxMessages
        case .lastNTurns:
            min(Self.maxMessages, Self.maxTurns * 2)
        }

        guard messages.count > maxMessages else { return messages }
        return Array(messages.suffix(maxMessages))
    }

    private func purgeStoredConversations() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }

        for file in files where file.pathExtension == "json" {
            try? FileManager.default.removeItem(at: file)
        }

        try? FileManager.default.removeItem(at: legacyConversationFileURL())
    }

    private func legacyConversationFileURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fallbackSupportDirectory
        return support.appendingPathComponent("grapfel/conversation.json")
    }
}
