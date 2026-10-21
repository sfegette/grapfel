import XCTest

final class SystemPromptStoreTests: XCTestCase {
    @MainActor
    func testSaveAndLoadRoundTrip() throws {
        let directory = try makeTemporaryDirectory()
        let fileURL = directory.appendingPathComponent("system-prompts.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = SystemPromptStore(fileURL: fileURL)
        let preset = SystemPromptPreset(name: "Pirate", body: "You are a pirate.", category: .role)
        try store.save(preset)

        let store2 = SystemPromptStore(fileURL: fileURL)
        XCTAssertEqual(store2.presets.count, 1)
        XCTAssertEqual(store2.presets[0].name, "Pirate")
        XCTAssertEqual(store2.presets[0].body, "You are a pirate.")
        XCTAssertEqual(store2.presets[0].category, .role)
        XCTAssertEqual(store2.presets[0].id, preset.id)
    }

    @MainActor
    func testDelete() throws {
        let directory = try makeTemporaryDirectory()
        let fileURL = directory.appendingPathComponent("system-prompts.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = SystemPromptStore(fileURL: fileURL)
        let preset = SystemPromptPreset(name: "Bullet points", body: "Use bullet points.", category: .rules)
        try store.save(preset)
        XCTAssertEqual(store.presets.count, 1)

        try store.delete(id: preset.id)
        XCTAssertTrue(store.presets.isEmpty)

        let store2 = SystemPromptStore(fileURL: fileURL)
        XCTAssertTrue(store2.presets.isEmpty)
    }

    @MainActor
    func testUpdateInPlace() throws {
        let directory = try makeTemporaryDirectory()
        let fileURL = directory.appendingPathComponent("system-prompts.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = SystemPromptStore(fileURL: fileURL)
        var preset = SystemPromptPreset(name: "Draft", body: "Initial body.", category: .general)
        try store.save(preset)

        preset.name = "Final"
        preset.body = "Updated body."
        try store.save(preset)

        XCTAssertEqual(store.presets.count, 1)
        XCTAssertEqual(store.presets[0].name, "Final")
        XCTAssertEqual(store.presets[0].body, "Updated body.")

        let store2 = SystemPromptStore(fileURL: fileURL)
        XCTAssertEqual(store2.presets.count, 1)
        XCTAssertEqual(store2.presets[0].name, "Final")
    }

    @MainActor
    func testMissingFileDoesNotCrash() throws {
        let directory = try makeTemporaryDirectory()
        let fileURL = directory.appendingPathComponent("system-prompts.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = SystemPromptStore(fileURL: fileURL)
        XCTAssertTrue(store.presets.isEmpty)
    }

    @MainActor
    func testCategoryPreservedInJSON() throws {
        let directory = try makeTemporaryDirectory()
        let fileURL = directory.appendingPathComponent("system-prompts.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = SystemPromptStore(fileURL: fileURL)
        try store.save(SystemPromptPreset(name: "A", body: "a", category: .role))
        try store.save(SystemPromptPreset(name: "B", body: "b", category: .rules))
        try store.save(SystemPromptPreset(name: "C", body: "c", category: .general))

        let store2 = SystemPromptStore(fileURL: fileURL)
        XCTAssertEqual(store2.presets.count, 3)
        let categories = Set(store2.presets.map { $0.category })
        XCTAssertEqual(categories, [.role, .rules, .general])
    }

    @MainActor
    func testSavedPresetFileHasOwnerOnlyPermissions() throws {
        let directory = try makeTemporaryDirectory()
        let fileURL = directory.appendingPathComponent("system-prompts.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = SystemPromptStore(fileURL: fileURL)
        try store.save(SystemPromptPreset(name: "Private", body: "Do not share."))

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue
        XCTAssertEqual(permissions & 0o777, 0o600)

        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        let directoryPermissions = try XCTUnwrap(directoryAttributes[.posixPermissions] as? NSNumber).intValue
        XCTAssertEqual(directoryPermissions & 0o777, 0o700)
    }

    @MainActor
    func testFailedSaveLeavesInMemoryPresetsUnchanged() throws {
        let directory = try makeTemporaryDirectory()
        let blockerURL = directory.appendingPathComponent("blocker")
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("blocker".utf8).write(to: blockerURL)

        let store = SystemPromptStore(fileURL: blockerURL.appendingPathComponent("system-prompts.json"))

        XCTAssertThrowsError(try store.save(SystemPromptPreset(name: "Unsaved", body: "Body")))
        XCTAssertTrue(store.presets.isEmpty)
    }

    @MainActor
    func testUnreadableSavedPresetFileIsNotOverwritten() throws {
        let directory = try makeTemporaryDirectory()
        let fileURL = directory.appendingPathComponent("system-prompts.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let invalidData = Data("not a preset archive".utf8)
        try invalidData.write(to: fileURL)

        let store = SystemPromptStore(fileURL: fileURL)

        XCTAssertThrowsError(try store.save(SystemPromptPreset(name: "Replacement", body: "Body")))
        XCTAssertEqual(try Data(contentsOf: fileURL), invalidData)
    }
}
