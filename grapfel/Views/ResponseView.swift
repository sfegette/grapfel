import SwiftUI

struct ResponseView: View {
    let text: String
    let isLoading: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if isLoading && text.isEmpty {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("thinking...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else if !text.isEmpty {
                        Text(text)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .id("response-end")
                    } else {
                        Text("response will appear here")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .onChange(of: text) {
                withAnimation {
                    proxy.scrollTo("response-end", anchor: .bottom)
                }
            }
        }
        .background(.quaternary.opacity(0.5), in: Rectangle())
    }
}
