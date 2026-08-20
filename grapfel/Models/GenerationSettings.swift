import Foundation

enum UserDefaultsKey {
    static let defaultTemperature = "defaultTemperature"
    static let defaultMaxTokens = "defaultMaxTokens"
    static let retentionMode = "retentionMode"
    static let globalHotKeyKeyCode = "globalHotKeyKeyCode"
    static let globalHotKeyModifiers = "globalHotKeyModifiers"

    // Preserve the shipped key so existing explicit choices survive the native-model migration.
    static let permissiveContentTransformations = "apfelPermissive"
}

enum PermissiveContentTransformationsPolicy {
    /// Standard Foundation Models guardrails remain active unless the user opts in.
    static let defaultEnabled = false

    /// Registration supplies a fallback only, so an existing saved preference is preserved.
    static func registerDefault(in userDefaults: UserDefaults = .standard) {
        userDefaults.register(defaults: [
            UserDefaultsKey.permissiveContentTransformations: defaultEnabled,
        ])
    }
}

/// Generation controls supported by Apple's Foundation Models framework.
struct GenerationSettings: Equatable, Sendable {
    var temperature: Double = 1.0
    var topP: Double = 1.0
    var maxTokens: Int = 2048
    var seed: Int? = nil
    var streaming: Bool = true
    var jsonMode: Bool = false
    var systemPrompt: String = ""
    var permissiveContentTransformations: Bool = false

    static let defaults = GenerationSettings()
}
