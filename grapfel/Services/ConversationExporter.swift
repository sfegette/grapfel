import AppKit
import Foundation
import UniformTypeIdentifiers

struct ConversationExporter {
    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private struct ConversationArchive: Codable {
        let schemaVersion: Int
        let exportedAt: Date
        let conversations: [ConversationRecord]
    }

    static func markdown(for record: ConversationRecord) -> String {
        let exportedAt = exportDateFormatter.string(from: Date())

        let sections = record.messages.map { message in
            let speaker: String
            switch message.role {
            case .assistant:
                speaker = "grapfel"
            case .user:
                speaker = "You"
            case .system:
                speaker = "System"
            }
            return "**\(speaker):**\n\n\(message.content)"
        }

        let body = sections.joined(separator: "\n\n---\n\n")
        return [
            "# \(record.name)",
            "_Exported from grapfel - \(exportedAt)_",
            "",
            "---",
            "",
            body,
            "",
        ].joined(separator: "\n")
    }

    static func archiveData(for records: [ConversationRecord]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let archive = ConversationArchive(schemaVersion: 1, exportedAt: Date(), conversations: records)
        return try encoder.encode(archive)
    }

    @MainActor
    static func copyMarkdown(_ record: ConversationRecord) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown(for: record), forType: .string)
    }

    @MainActor
    static func saveMarkdown(_ record: ConversationRecord) {
        let panel = NSSavePanel()
        panel.title = "Export Conversation"
        panel.nameFieldStringValue = suggestedFileName(for: record.name, extension: "md")
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try markdown(for: record).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            presentWriteError(error, title: "Export Failed")
        }
    }

    @MainActor
    static func saveAllConversations(_ records: [ConversationRecord]) {
        let panel = NSSavePanel()
        panel.title = "Export All Conversations"
        panel.nameFieldStringValue = "grapfel-conversations.json"
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try archiveData(for: records)
            try data.write(to: url, options: .atomic)
        } catch {
            presentWriteError(error, title: "Export Failed")
        }
    }

    private static func suggestedFileName(for title: String, extension fileExtension: String) -> String {
        let fallback = "conversation"
        let allowedCharacters = CharacterSet.alphanumerics
            .union(.whitespaces)
            .union(CharacterSet(charactersIn: "-_."))
        let sanitized = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .unicodeScalars
            .map { allowedCharacters.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { $0.append($1) }
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let base = sanitized.isEmpty ? fallback : sanitized
        return "\(base).\(fileExtension)"
    }

    @MainActor
    private static func presentWriteError(_ error: Error, title: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
