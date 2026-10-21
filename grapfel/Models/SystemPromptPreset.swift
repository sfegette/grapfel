import Foundation

enum PresetCategory: String, Codable, CaseIterable {
    case role, rules, general
}

struct SystemPromptPreset: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var body: String
    var category: PresetCategory = .general
    var createdAt: Date = Date()
}

enum SystemPromptStoreError: LocalizedError {
    case savedPresetsUnreadable

    var errorDescription: String? {
        switch self {
        case .savedPresetsUnreadable:
            "Saved system-prompt presets could not be read. Grapfel left the existing file unchanged."
        }
    }
}

@Observable
@MainActor
final class SystemPromptStore {
    static let shared = SystemPromptStore()

    private(set) var presets: [SystemPromptPreset] = []
    private(set) var persistenceErrorMessage: String?

    private let fileURL: URL
    private let fileManager: FileManager
    private var didFailToLoad = false

    private init() {
        self.fileURL = Self.defaultFileURL()
        self.fileManager = .default
        load()
    }

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        load()
    }

    func save(_ preset: SystemPromptPreset) throws {
        try ensureSavedPresetsAreReadable()

        var updated = presets
        if let index = updated.firstIndex(where: { $0.id == preset.id }) {
            updated[index] = preset
        } else {
            updated.append(preset)
        }

        try persist(updated)
        presets = updated
        persistenceErrorMessage = nil
    }

    func delete(id: UUID) throws {
        try ensureSavedPresetsAreReadable()
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return }

        var updated = presets
        updated.remove(at: index)
        try persist(updated)
        presets = updated
        persistenceErrorMessage = nil
    }

    private static func defaultFileURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support
            .appendingPathComponent("grapfel", isDirectory: true)
            .appendingPathComponent("system-prompts.json")
    }

    private func ensureSavedPresetsAreReadable() throws {
        guard !didFailToLoad else { throw SystemPromptStoreError.savedPresetsUnreadable }
    }

    private func persist(_ updated: [SystemPromptPreset]) throws {
        let directory = fileURL.deletingLastPathComponent()
        let temporaryURL = directory.appendingPathComponent(".system-prompts-\(UUID().uuidString)")

        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(updated)
            try data.write(to: temporaryURL, options: .withoutOverwriting)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporaryURL.path)

            if fileManager.fileExists(atPath: fileURL.path) {
                _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: fileURL)
            }
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            persistenceErrorMessage = error.localizedDescription
            throw error
        }
    }

    private func load() {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            presets = try decoder.decode([SystemPromptPreset].self, from: data)
        } catch {
            didFailToLoad = true
            persistenceErrorMessage = SystemPromptStoreError.savedPresetsUnreadable.localizedDescription
        }
    }
}
