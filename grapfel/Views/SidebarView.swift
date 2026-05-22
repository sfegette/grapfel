import SwiftUI

struct SidebarView: View {
    @State private var store = ConversationStore.shared
    @State private var editingID: UUID? = nil
    @State private var editingName: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Chats")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: { store.createAndActivate() }) {
                    Image(systemName: "square.and.pencil")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("New conversation")
                .accessibilityLabel("New conversation")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(store.conversations) { record in
                        ConversationRow(
                            record: record,
                            isActive: record.id == store.activeID,
                            isEditing: editingID == record.id,
                            editingName: $editingName,
                            onSelect: {
                                editingID = nil
                                store.activate(record.id)
                            },
                            onDelete: { store.delete(record) },
                            onStartEdit: {
                                editingID = record.id
                                editingName = record.name
                            },
                            onCommitEdit: {
                                let name = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !name.isEmpty { store.rename(record.id, to: name) }
                                editingID = nil
                            }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(width: 200)
        .background(.ultraThinMaterial)
    }
}

private struct ConversationRow: View {
    let record: ConversationRecord
    let isActive: Bool
    let isEditing: Bool
    @Binding var editingName: String
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onStartEdit: () -> Void
    let onCommitEdit: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if isEditing {
                TextField("Name", text: $editingName)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .onSubmit { onCommitEdit() }
                    .onExitCommand { onCommitEdit() }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.name)
                        .font(.callout)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(record.updatedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .accessibilityElement(children: .combine)
            }

            if isActive && !isEditing {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete \(record.name)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isActive ? Color.primary.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .contextMenu {
            Button("Rename", action: onStartEdit)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}
