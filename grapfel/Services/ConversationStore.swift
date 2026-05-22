import Foundation

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
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
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
        if let data = try? encoder().encode(record) {
            try? data.write(to: fileURL(for: record.id), options: .atomic)
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
