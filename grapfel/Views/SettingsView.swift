import Carbon
import SwiftUI

struct SettingsView: View {
    @AppStorage(UserDefaultsKey.defaultTemperature) private var defaultTemperature = 1.0
    @AppStorage(UserDefaultsKey.defaultMaxTokens) private var defaultMaxTokens = 2048

    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gear") }

            DefaultsTab(temperature: $defaultTemperature, maxTokens: $defaultMaxTokens)
                .tabItem { Label("Defaults", systemImage: "slider.horizontal.3") }

            PrivacyTab()
                .tabItem { Label("Privacy", systemImage: "lock.shield") }
        }
        .padding(20)
        .frame(width: 420)
    }
}

private struct GeneralTab: View {
    @AppStorage(UserDefaultsKey.permissiveContentTransformations)
    private var permissiveContentTransformations = PermissiveContentTransformationsPolicy.defaultEnabled
    @AppStorage(UserDefaultsKey.globalHotKeyKeyCode) private var globalHotKeyKeyCode = Int(GlobalHotKey.default.keyCode)
    @AppStorage(UserDefaultsKey.globalHotKeyModifiers) private var globalHotKeyModifiers = Int(GlobalHotKey.default.carbonModifiers)
    @State private var hotKey = GlobalHotKey.default
    @State private var hotKeyMessage: String? = nil

    var body: some View {
        Form {
            Section("global hotkey") {
                HotKeyRecorderField(hotKey: $hotKey) { capturedHotKey in
                    do {
                        guard let appDelegate = AppDelegate.shared else {
                            throw GlobalHotKeyError.registrationFailed(OSStatus(paramErr))
                        }
                        try appDelegate.applyGlobalHotKey(capturedHotKey)
                        hotKey = capturedHotKey
                        globalHotKeyKeyCode = Int(capturedHotKey.keyCode)
                        globalHotKeyModifiers = Int(capturedHotKey.carbonModifiers)
                        hotKeyMessage = "Saved \(capturedHotKey.displayString)."
                    } catch {
                        hotKey = GlobalHotKey.stored()
                        hotKeyMessage = error.localizedDescription
                    }
                } onValidationMessage: { message in
                    hotKeyMessage = message
                }
                .frame(width: 180, height: 32)

                Text("Click the field, then press a shortcut with at least one modifier key. grapfel replaces the previous registration only after the new shortcut is accepted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let hotKeyMessage {
                    Text(hotKeyMessage)
                        .font(.caption)
                        .foregroundStyle(hotKeyMessage.hasPrefix("Saved") ? Color.secondary : Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section("content policy") {
                LabeledContent("permissive transformations") {
                    Toggle("", isOn: $permissiveContentTransformations)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                Text("Off by default. Allows a narrower set of content transformations while Apple Intelligence's core safety protections remain active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 300)
        .onAppear {
            hotKey = GlobalHotKey.stored()
        }
        .onChange(of: permissiveContentTransformations) {
            ModelAvailabilityState.shared.refresh()
        }
    }
}

private struct DefaultsTab: View {
    @Binding var temperature: Double
    @Binding var maxTokens: Int

    var body: some View {
        Form {
            Section("generation") {
                LabeledContent("temperature") {
                    HStack {
                        Slider(value: $temperature, in: 0...2, step: 0.1)
                            .frame(width: 140)
                        Text(String(format: "%.1f", temperature))
                            .font(.caption.monospacedDigit())
                            .frame(width: 28)
                    }
                }
                LabeledContent("max tokens") {
                    Stepper("\(maxTokens)", value: $maxTokens, in: 128...4096, step: 128)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct PrivacyTab: View {
    @AppStorage(UserDefaultsKey.retentionMode) private var retentionModeRaw = RetentionMode.unlimited.rawValue
    @State private var draftRetentionModeRaw = RetentionMode.unlimited.rawValue
    @State private var pendingRetentionModeRaw: String? = nil
    @State private var showSessionOnlyConfirmation = false
    private var retentionMode: RetentionMode {
        RetentionMode(rawValue: draftRetentionModeRaw) ?? .unlimited
    }
    private var appSupportPath: String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("grapfel", isDirectory: true)
            .path ?? "~/Library/Application Support/grapfel"
    }
    private var systemPromptPresetPath: String {
        "\(appSupportPath)/system-prompts.json"
    }
    private var sparkleFeedURL: String {
        Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? "the configured Sparkle update feed"
    }

    var body: some View {
        Form {
            Section("what stays local") {
                Text("Prompts, responses, and selected file contents are processed by Apple's on-device Foundation Models framework. Grapfel does not send model prompts or attachments to an app-owned server or a third-party model provider.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Selected files are opened read-only when you attach them to a prompt. grapfel reads their text content for the current request and does not copy the original files into its own storage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("conversation history") {
                Picker("retention", selection: $draftRetentionModeRaw) {
                    ForEach(RetentionMode.allCases) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
                Text(retentionMode == .sessionOnly
                     ? "Conversations are never written to disk. History is lost when grapfel quits."
                     : "Conversations are stored in \(appSupportPath) with owner-only (0600/0700) permissions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("saved system prompt presets") {
                Text("Saved preset names and text are stored in \(systemPromptPresetPath) with owner-only (0600/0700) permissions. Presets are separate from conversation history, so changing its retention setting does not remove them. Delete a preset from its role or rules menu in the options panel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("network activity") {
                Text("Sparkle checks \(sparkleFeedURL) for signed app updates. If you install an update, the download comes from the release source referenced by that feed. Prompts, responses, and attached file contents are not included in update checks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("limits") {
                LabeledContent("max messages on disk") {
                    Text("\(ConversationStore.maxMessages)")
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                LabeledContent("max turns (last-n mode)") {
                    Text("\(ConversationStore.maxTurns)")
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 300)
        .onAppear {
            draftRetentionModeRaw = retentionModeRaw
        }
        .onChange(of: draftRetentionModeRaw) { oldValue, newValue in
            guard oldValue != newValue else { return }
            if newValue == RetentionMode.sessionOnly.rawValue,
               retentionModeRaw != RetentionMode.sessionOnly.rawValue {
                pendingRetentionModeRaw = newValue
                showSessionOnlyConfirmation = true
                draftRetentionModeRaw = retentionModeRaw
            } else {
                applyRetentionMode(newValue)
            }
        }
        .alert("Delete stored conversations?", isPresented: $showSessionOnlyConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingRetentionModeRaw = nil
                draftRetentionModeRaw = retentionModeRaw
            }
            Button("Delete and Continue", role: .destructive) {
                let newValue = pendingRetentionModeRaw ?? RetentionMode.sessionOnly.rawValue
                applyRetentionMode(newValue)
                pendingRetentionModeRaw = nil
            }
        } message: {
            Text("Switching to Session only immediately removes saved conversations from disk. Your open chat stays available until grapfel quits.")
        }
    }

    private func applyRetentionMode(_ newValue: String) {
        retentionModeRaw = newValue
        draftRetentionModeRaw = newValue
        ConversationStore.shared.applyRetentionMode()
    }
}

#Preview {
    SettingsView()
}
