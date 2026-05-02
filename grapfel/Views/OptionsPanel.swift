import SwiftUI

struct OptionsPanel: View {
    @Binding var options: ApfelOptions
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(spacing: 12) {
                // Temperature
                LabeledSlider(
                    label: "temperature",
                    value: $options.temperature,
                    range: 0...2,
                    step: 0.1,
                    formatted: String(format: "%.1f", options.temperature)
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

                // System prompt
                VStack(alignment: .leading, spacing: 4) {
                    Text("system prompt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $options.systemPrompt)
                        .font(.caption)
                        .frame(height: 48)
                        .scrollContentBackground(.hidden)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
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
