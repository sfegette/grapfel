import Carbon
import SwiftUI

struct SettingsView: View {
    @AppStorage(UserDefaultsKey.serverPort) private var serverPort = 11434
    @AppStorage(UserDefaultsKey.defaultTemperature) private var defaultTemperature = 1.0
    @AppStorage(UserDefaultsKey.defaultMaxTokens) private var defaultMaxTokens = 2048
    @AppStorage(UserDefaultsKey.apfelBinaryPath) private var apfelBinaryPath = ""

    var body: some View {
        TabView {
            GeneralTab(serverPort: $serverPort, apfelBinaryPath: $apfelBinaryPath)
                .tabItem { Label("General", systemImage: "gear") }

            MCPTab()
                .tabItem { Label("Tools", systemImage: "hammer") }

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
    @Binding var serverPort: Int
    @Binding var apfelBinaryPath: String
    @AppStorage(UserDefaultsKey.apfelPermissive) private var apfelPermissive = true
    @AppStorage(UserDefaultsKey.globalHotKeyKeyCode) private var globalHotKeyKeyCode = Int(GlobalHotKey.default.keyCode)
    @AppStorage(UserDefaultsKey.globalHotKeyModifiers) private var globalHotKeyModifiers = Int(GlobalHotKey.default.carbonModifiers)
    @State private var isRestarting = false
    @State private var hotKey = GlobalHotKey.default
    @State private var hotKeyMessage: String? = nil
    private var serverState = ServerState.shared

    init(serverPort: Binding<Int>, apfelBinaryPath: Binding<String>) {
        self._serverPort = serverPort
        self._apfelBinaryPath = apfelBinaryPath
    }

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
            Section("apfel server") {
                LabeledContent("port") {
                    TextField("11434", value: $serverPort, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("permissive mode") {
                    Toggle("", isOn: $apfelPermissive)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                Text("disables content safety filtering for all requests — effective on restart")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    isRestarting = true
                    Task {
                        await serverState.restart()
                        isRestarting = false
                    }
                } label: {
                    if isRestarting {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Restarting…")
                        }
                    } else {
                        Text("Restart Server")
                    }
                }
                .disabled(isRestarting)
            }
            Section("binary") {
                LabeledContent("path override") {
                    TextField("/opt/homebrew/bin/apfel", text: $apfelBinaryPath)
                        .textFieldStyle(.roundedBorder)
                }
                Text("leave blank to auto-detect from PATH")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 300)
        .onAppear {
            hotKey = GlobalHotKey.stored()
        }
    }
}

private struct MCPTab: View {
    @State private var mcpPaths: [String] = []
    @State private var newMCPPath: String = ""

    var body: some View {
        Form {
            Section("MCP servers") {
                if mcpPaths.isEmpty {
                    Text("No MCP servers configured.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                ForEach(mcpPaths, id: \.self) { path in
                    HStack {
                        Text(path)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            mcpPaths.removeAll { $0 == path }
                            saveMCPPaths()
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("/path/to/mcp-server or https://…", text: $newMCPPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let trimmed = newMCPPath.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty, !mcpPaths.contains(trimmed) else { return }
                        mcpPaths.append(trimmed)
                        saveMCPPaths()
                        newMCPPath = ""
                    }
                    .disabled(newMCPPath.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("apfel proxies tool calls through each configured MCP server — effective on restart")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 300)
        .onAppear {
            mcpPaths = UserDefaults.standard.array(forKey: UserDefaultsKey.mcpServers) as? [String] ?? []
        }
    }

    private func saveMCPPaths() {
        UserDefaults.standard.set(mcpPaths, forKey: UserDefaultsKey.mcpServers)
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
    @AppStorage(UserDefaultsKey.serverPort) private var serverPort = 11434
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
    private var sparkleFeedURL: String {
        Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? "the configured Sparkle update feed"
    }

    var body: some View {
        Form {
            Section("what stays local") {
                Text("Prompts, responses, and selected file contents are sent only to apfel over http://127.0.0.1:\(serverPort)/v1. grapfel does not send model prompts or attachments to OpenAI or another cloud LLM provider.")
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
