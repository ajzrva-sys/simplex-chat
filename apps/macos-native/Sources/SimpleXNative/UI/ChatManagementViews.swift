import SwiftUI

struct ForwardMessagesView: View {
    @ObservedObject var model: AppModel
    let sourceChat: NativeChat
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List(destinations) { chat in
                Button {
                    model.forwardSelectedMessages(to: chat)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        ProfileAvatar(image: chat.image, name: chat.displayName, size: 36)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(chat.displayName)
                            Text(chat.kind.toolbarSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Forward to \(chat.displayName)")
            }
            .searchable(text: $search, prompt: "Search conversations")
            .navigationTitle("Forward Messages")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 480)
    }

    private var destinations: [NativeChat] {
        model.chats.filter {
            $0.id != sourceChat.id && $0.kind.canSend
                && (search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search))
        }
    }
}

struct ChatDetailsView: View {
    @ObservedObject var model: AppModel
    let chat: NativeChat
    @Environment(\.dismiss) private var dismiss
    @State private var destructiveConfirmation: DestructiveAction?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        ProfileAvatar(image: chat.image, name: chat.displayName, size: 64)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(chat.displayName)
                                .font(.title2.weight(.semibold))
                            Text(chat.kind.toolbarSubtitle)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Conversation") {
                    LabeledContent("Type", value: chat.kind.toolbarSubtitle)
                    LabeledContent("Unread", value: String(chat.unreadCount))
                    if chat.kind == .group {
                        LabeledContent("Group identifier", value: String(chat.apiID))
                    }
                }

                Section("Actions") {
                    Button("Clear Messages…") { destructiveConfirmation = .clear }
                    if chat.kind == .group {
                        Button("Leave Group…", role: .destructive) { destructiveConfirmation = .leave }
                    }
                    Button("Delete Conversation…", role: .destructive) { destructiveConfirmation = .delete }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Conversation Details")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
        .frame(minWidth: 440, minHeight: 420)
        .confirmationDialog(
            destructiveConfirmation?.title ?? "Confirm",
            isPresented: Binding(
                get: { destructiveConfirmation != nil },
                set: { if !$0 { destructiveConfirmation = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(destructiveConfirmation?.buttonTitle ?? "Continue", role: .destructive) {
                switch destructiveConfirmation {
                case .clear: model.clearSelectedChat()
                case .delete: model.deleteSelectedChat()
                case .leave: model.leaveSelectedGroup()
                case nil: break
                }
                destructiveConfirmation = nil
            }
            Button("Cancel", role: .cancel) { destructiveConfirmation = nil }
        }
    }

    private enum DestructiveAction {
        case clear, delete, leave

        var title: String {
            switch self {
            case .clear: "Clear all messages in this conversation?"
            case .delete: "Delete this conversation from Native Chat?"
            case .leave: "Leave this group?"
            }
        }

        var buttonTitle: String {
            switch self {
            case .clear: "Clear Messages"
            case .delete: "Delete Conversation"
            case .leave: "Leave Group"
            }
        }
    }
}
