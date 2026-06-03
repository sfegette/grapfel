import XCTest

final class ConversationStoreRetentionTests: XCTestCase {
    @MainActor
    func testSessionOnlyModeDoesNotPersistConversationFiles() throws {
        let directory = try makeTemporaryDirectory()
        let defaults = makeTestUserDefaults()
        defaults.set(RetentionMode.sessionOnly.rawValue, forKey: UserDefaultsKey.retentionMode)

        let store = ConversationStore(directory: directory, userDefaults: defaults)
        let record = ConversationRecord(
            name: "Ephemeral",
            messages: [ChatMessage(role: .user, content: "Hello")]
        )

        store.save(record)

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL(for: record.id).path))
    }

    @MainActor
    func testLastNTurnsModeCapsPersistedMessages() throws {
        let directory = try makeTemporaryDirectory()
        let defaults = makeTestUserDefaults()
        defaults.set(RetentionMode.lastNTurns.rawValue, forKey: UserDefaultsKey.retentionMode)

        let store = ConversationStore(directory: directory, userDefaults: defaults)
        let messages = (0..<(ConversationStore.maxTurns * 2 + 4)).map { index in
            ChatMessage(role: index.isMultiple(of: 2) ? .user : .assistant, content: "Message \(index)")
        }
        let record = ConversationRecord(name: "Trimmed", messages: messages)

        store.save(record)

        let data = try Data(contentsOf: store.fileURL(for: record.id))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let savedRecord = try decoder.decode(ConversationRecord.self, from: data)

        XCTAssertEqual(savedRecord.messages.count, ConversationStore.maxTurns * 2)
        XCTAssertEqual(savedRecord.messages.first?.content, "Message 4")
    }

    @MainActor
    func testSessionOnlyModePurgesExistingStoredConversationsOnInit() throws {
        let directory = try makeTemporaryDirectory()
        let defaults = makeTestUserDefaults()
        defaults.set(RetentionMode.unlimited.rawValue, forKey: UserDefaultsKey.retentionMode)

        let initialStore = ConversationStore(directory: directory, userDefaults: defaults)
        let record = ConversationRecord(
            name: "Persisted",
            messages: [ChatMessage(role: .user, content: "Hello")]
        )
        initialStore.save(record)
        XCTAssertTrue(FileManager.default.fileExists(atPath: initialStore.fileURL(for: record.id).path))

        defaults.set(RetentionMode.sessionOnly.rawValue, forKey: UserDefaultsKey.retentionMode)
        let purgingStore = ConversationStore(directory: directory, userDefaults: defaults)

        XCTAssertFalse(FileManager.default.fileExists(atPath: purgingStore.fileURL(for: record.id).path))
        XCTAssertEqual(purgingStore.conversations.count, 1)
    }

    @MainActor
    func testFailedDiskWriteDoesNotReplaceInMemoryConversationState() throws {
        let directory = try makeTemporaryDirectory()
        let defaults = makeTestUserDefaults()
        defaults.set(RetentionMode.unlimited.rawValue, forKey: UserDefaultsKey.retentionMode)

        let store = ConversationStore(directory: directory, userDefaults: defaults)
        var record = ConversationRecord(
            name: "Stable",
            messages: [ChatMessage(role: .user, content: "Original")]
        )
        store.save(record)
        XCTAssertEqual(store.conversations.first?.messages.first?.content, "Original")

        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }

        record.messages = [ChatMessage(role: .user, content: "Updated")]
        store.save(record)

        XCTAssertEqual(store.conversations.first?.messages.first?.content, "Original")

        let data = try Data(contentsOf: store.fileURL(for: record.id))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let persistedRecord = try decoder.decode(ConversationRecord.self, from: data)
        XCTAssertEqual(persistedRecord.messages.first?.content, "Original")
    }

    @MainActor
    func testSwitchingToSessionOnlyKeepsOnlyActiveConversationInMemory() throws {
        let directory = try makeTemporaryDirectory()
        let defaults = makeTestUserDefaults()
        defaults.set(RetentionMode.unlimited.rawValue, forKey: UserDefaultsKey.retentionMode)

        let store = ConversationStore(directory: directory, userDefaults: defaults)
        let first = ConversationRecord(
            name: "First",
            messages: [ChatMessage(role: .user, content: "One")]
        )
        let second = ConversationRecord(
            name: "Second",
            messages: [ChatMessage(role: .user, content: "Two")]
        )
        store.save(first)
        store.save(second)
        store.activate(first.id)

        defaults.set(RetentionMode.sessionOnly.rawValue, forKey: UserDefaultsKey.retentionMode)
        store.applyRetentionMode()

        XCTAssertEqual(store.conversations.map(\.id), [first.id])
        XCTAssertEqual(store.activeID, first.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL(for: first.id).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL(for: second.id).path))
    }

    // Gap 1a: applyRetentionMode(.lastNTurns) caps messages in existing conversations.
    @MainActor
    func testApplyRetentionModeLastNTurnsCapsExistingMessages() throws {
        let directory = try makeTemporaryDirectory()
        let defaults = makeTestUserDefaults()
        defaults.set(RetentionMode.unlimited.rawValue, forKey: UserDefaultsKey.retentionMode)

        let store = ConversationStore(directory: directory, userDefaults: defaults)
        let messages = (0..<(ConversationStore.maxTurns * 2 + 4)).map { i in
            ChatMessage(role: i.isMultiple(of: 2) ? .user : .assistant, content: "msg\(i)")
        }
        let record = ConversationRecord(name: "Long", messages: messages)
        store.save(record)

        defaults.set(RetentionMode.lastNTurns.rawValue, forKey: UserDefaultsKey.retentionMode)
        store.applyRetentionMode()

        let saved = try XCTUnwrap(store.conversations.first(where: { $0.id == record.id }))
        XCTAssertEqual(saved.messages.count, ConversationStore.maxTurns * 2)
        XCTAssertEqual(saved.messages.first?.content, "msg4")
    }

    // Gap 1b: applyRetentionMode(.unlimited) re-saves with maxMessages cap.
    @MainActor
    func testApplyRetentionModeUnlimitedPreservesMessagesUpToCap() throws {
        let directory = try makeTemporaryDirectory()
        let defaults = makeTestUserDefaults()
        defaults.set(RetentionMode.lastNTurns.rawValue, forKey: UserDefaultsKey.retentionMode)

        let store = ConversationStore(directory: directory, userDefaults: defaults)
        let messages = (0..<ConversationStore.maxTurns * 2).map { i in
            ChatMessage(role: i.isMultiple(of: 2) ? .user : .assistant, content: "msg\(i)")
        }
        let record = ConversationRecord(name: "Capped", messages: messages)
        store.save(record)

        defaults.set(RetentionMode.unlimited.rawValue, forKey: UserDefaultsKey.retentionMode)
        store.applyRetentionMode()

        let saved = try XCTUnwrap(store.conversations.first(where: { $0.id == record.id }))
        XCTAssertEqual(saved.messages.count, ConversationStore.maxTurns * 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL(for: record.id).path))
    }

    // Gap 2: in-memory state is always updated after a successful write, regardless of
    // whether setAttributes succeeds. Regression test for the M1 fix.
    @MainActor
    func testSaveAlwaysUpdatesInMemoryStateAfterSuccessfulWrite() throws {
        let directory = try makeTemporaryDirectory()
        let defaults = makeTestUserDefaults()
        defaults.set(RetentionMode.unlimited.rawValue, forKey: UserDefaultsKey.retentionMode)

        let store = ConversationStore(directory: directory, userDefaults: defaults)
        var record = ConversationRecord(name: "V1", messages: [ChatMessage(role: .user, content: "first")])
        store.save(record)
        XCTAssertEqual(store.conversations.first(where: { $0.id == record.id })?.messages.first?.content, "first")

        record.messages = [ChatMessage(role: .user, content: "second")]
        store.save(record)

        // In-memory state must reflect the new content, even if setAttributes were to fail.
        XCTAssertEqual(store.conversations.first(where: { $0.id == record.id })?.messages.first?.content, "second")

        let data = try Data(contentsOf: store.fileURL(for: record.id))
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let persisted = try decoder.decode(ConversationRecord.self, from: data)
        XCTAssertEqual(persisted.messages.first?.content, "second")
    }
}
