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
        }
        .padding(20)
        .frame(width: 420)
    }
}

private struct GeneralTab: View {
    @Binding var serverPort: Int
    @Binding var apfelBinaryPath: String
    @AppStorage(UserDefaultsKey.apfelPermissive) private var apfelPermissive = true
    @State private var isRestarting = false
    private var serverState = ServerState.shared

    init(serverPort: Binding<Int>, apfelBinaryPath: Binding<String>) {
        self._serverPort = serverPort
        self._apfelBinaryPath = apfelBinaryPath
    }

    var body: some View {
        Form {
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

#Preview {
    SettingsView()
}
