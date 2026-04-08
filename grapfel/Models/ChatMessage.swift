import Foundation

struct ChatMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let role: Role
    var content: String

    init(id: UUID = UUID(), role: Role, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }

    enum Role: String, Codable {
        case system
        case user
        case assistant
    }
}
