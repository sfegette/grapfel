import SwiftUI

struct OptionsPanel: View {
    @Binding var options: GenerationSettings
    @State private var isExpanded = false
    @State private var rolePresetID: UUID? = nil
    @State private var rulesPresetID: UUID? = nil
    @State private var lastComposed: String = ""
    @State private var showingSaveSheet = false
    @State private var persistenceErrorMessage: String?

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(spacing: 12) {
                // Temperature
                LabeledSlider(
                    label: "temperature",
                    value: $options.temperature,
                    range: 0...2,
                    step: 0.1,
                    formatted: String(format: "%.2f", options.temperature)
                )

                // Top-p
                LabeledSlider(
                    label: "top p",
                    value: $options.topP,
                    range: 0.05...1,
                    step: 0.05,
                    formatted: String(format: "%.2f", options.topP)
                )

                // Max tokens
                LabeledStepper(
                    label: "max tokens",
                    value: $options.maxTokens,
                    range: 128...4096,
                    step: 128
                )

                // Toggles row
                HStack(spacing: 16) {
                    Toggle("stream", isOn: $options.streaming)
                        .toggleStyle(.switch)
                        .labelsHidden()
                    Text("stream")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("json", isOn: $options.jsonMode)
                        .toggleStyle(.switch)
                        .labelsHidden()
                    Text("json")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()
                }

                // System prompt — preset pickers + editor
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        PresetSlotMenu(
                            slotLabel: "role",
                            categories: [.role, .general],
                            selectedID: $rolePresetID,
                            onSelect: applyComposition,
                            onPersistenceError: showPersistenceError
                        )
                        Divider().frame(height: 12)
                        PresetSlotMenu(
                            slotLabel: "rules",
                            categories: [.rules, .general],
                            selectedID: $rulesPresetID,
                            onSelect: applyComposition,
                            onPersistenceError: showPersistenceError
                        )
                        Spacer()
                        Button {
                            showingSaveSheet = true
                        } label: {
                            Image(systemName: "plus.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Save current text as a preset")
                        .disabled(options.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    TextEditor(text: $options.systemPrompt)
                        .font(.caption)
                        .frame(height: 56)
                        .scrollContentBackground(.hidden)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        .onChange(of: options.systemPrompt) { _, newValue in
                            if newValue != lastComposed {
                                rolePresetID = nil
                                rulesPresetID = nil
                            }
                        }
                }
                .sheet(isPresented: $showingSaveSheet) {
                    SavePresetSheet(isPresented: $showingSaveSheet, initialBody: options.systemPrompt)
                }
            }
            .padding(.top, 8)
        } label: {
            Text("options")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .alert("Couldn't Delete Saved Preset", isPresented: Binding(
            get: { persistenceErrorMessage != nil },
            set: { if !$0 { persistenceErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { persistenceErrorMessage = nil }
        } message: {
            Text(persistenceErrorMessage ?? "An unexpected storage error occurred.")
        }
    }

    private func applyComposition() {
        let store = SystemPromptStore.shared
        let role  = store.presets.first(where: { $0.id == rolePresetID })?.body ?? ""
        let rules = store.presets.first(where: { $0.id == rulesPresetID })?.body ?? ""
        let composed = [role, rules].filter { !$0.isEmpty }.joined(separator: "\n\n")
        options.systemPrompt = composed
        lastComposed = composed
    }

    private func showPersistenceError(_ error: Error) {
        persistenceErrorMessage = error.localizedDescription
    }
}

// MARK: - Preset slot menu

private struct PresetSlotMenu: View {
    let slotLabel: String
    let categories: [PresetCategory]
    @Binding var selectedID: UUID?
    let onSelect: () -> Void
    let onPersistenceError: (Error) -> Void

    var body: some View {
        let store = SystemPromptStore.shared
        let available = store.presets.filter { categories.contains($0.category) }
        let selectedName = store.presets.first(where: { $0.id == selectedID })?.name

        Menu {
            Button("None") {
                selectedID = nil
                onSelect()
            }
            if !available.isEmpty {
                Divider()
                ForEach(available) { preset in
                    Button(preset.name) {
                        selectedID = preset.id
                        onSelect()
                    }
                }
            }
            if let id = selectedID, available.contains(where: { $0.id == id }) {
                Divider()
                Button(role: .destructive) {
                    do {
                        try store.delete(id: id)
                        selectedID = nil
                        onSelect()
                    } catch {
                        onPersistenceError(error)
                    }
                } label: {
                    Label("Delete \"\(selectedName ?? "")\"", systemImage: "trash")
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(slotLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(.secondary)
                if let name = selectedName {
                    Text("· \(name)")
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

// MARK: - Save preset sheet

private struct SavePresetSheet: View {
    @Binding var isPresented: Bool
    let initialBody: String
    @State private var name: String = ""
    @State private var category: PresetCategory = .role
    @State private var persistenceErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save preset")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. Helpful assistant", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Category")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Category", selection: $category) {
                    ForEach(PresetCategory.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    let preset = SystemPromptPreset(name: name, body: initialBody, category: category)
                    do {
                        try SystemPromptStore.shared.save(preset)
                        isPresented = false
                    } catch {
                        persistenceErrorMessage = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 300)
        .alert("Couldn't Save Preset", isPresented: Binding(
            get: { persistenceErrorMessage != nil },
            set: { if !$0 { persistenceErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { persistenceErrorMessage = nil }
        } message: {
            Text(persistenceErrorMessage ?? "An unexpected storage error occurred.")
        }
    }
}

// MARK: - Sub-components

private struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let formatted: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Slider(value: $value, in: range, step: step)
            Text(formatted)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }
}

private struct LabeledStepper: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Spacer()
            Stepper("\(value)", value: $value, in: range, step: step)
                .labelsHidden()
            Text("\(value)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
    }
}
