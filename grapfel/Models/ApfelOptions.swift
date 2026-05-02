import Foundation

enum UserDefaultsKey {
    static let serverPort = "serverPort"
    static let defaultTemperature = "defaultTemperature"
    static let defaultMaxTokens = "defaultMaxTokens"
    static let apfelBinaryPath = "apfelBinaryPath"
    static let apfelPermissive = "apfelPermissive"
}

/// All generation options exposed to the user, mapped to apfel CLI flags / API fields.
struct ApfelOptions: Equatable {
    var temperature: Double = 1.0       // --temperature
    var maxTokens: Int = 2048           // --max-tokens
    var seed: Int? = nil                // --seed (nil = not set)
    var streaming: Bool = true           // --stream
    var jsonMode: Bool = false           // response_format: json_object
    var systemPrompt: String = ""       // -s / --system
    var contextStrategy: ContextStrategy = .newestFirst  // --context-strategy
    var contextMaxTurns: Int? = nil     // --context-max-turns

    static let defaults = ApfelOptions()
}

enum ContextStrategy: String, CaseIterable, Identifiable {
    case newestFirst = "newest-first"
    case oldestFirst = "oldest-first"
    case slidingWindow = "sliding-window"
    case summarize = "summarize"
    case strict = "strict"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .newestFirst:   return "newest first"
        case .oldestFirst:   return "oldest first"
        case .slidingWindow: return "sliding window"
        case .summarize:     return "summarize"
        case .strict:        return "strict"
        }
    }
}
