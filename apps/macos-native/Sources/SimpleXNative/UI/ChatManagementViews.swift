import SwiftUI

struct ForwardMessagesView: View {
    @ObservedObject var model: AppModel
    let sourceChat: NativeChat
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(destinations) { chat in
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
            }
            .overlay {
                if destinations.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .searchable(text: $searchText, placement: .toolbar, prompt: "Search chats")
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
                && (searchText.isEmpty || $0.displayName.localizedCaseInsensitiveContains(searchText))
        }
    }
}

struct ChatDetailsView: View {
    @ObservedObject var model: AppModel
    let chat: NativeChat
    @Environment(\.dismiss) private var dismiss
    @State private var destructiveConfirmation: DestructiveAction?
    @State private var showEditGroupProfile = false
    @State private var showGroupMembers = false
    @State private var showGroupPreferences = false
    @State private var showGroupLink = false
    @State private var showSecurityCode = false
    @State private var showWallpaperEditor = false
    @State private var showContactPreferences = false
    @State private var showGroupReports = false
    @State private var connectionCode: String? = nil
    @State private var connectionVerified = false

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

                if chat.kind == .group {
                    Section("Group") {
                        Button("Edit Group Profile…") { showEditGroupProfile = true }
                        Button("Members…") { showGroupMembers = true }
                        Button("Preferences…") { showGroupPreferences = true }
                        Button("Group Link…") { showGroupLink = true }
                        Button("View Reports…") { showGroupReports = true }
                    }
                }

                if chat.kind == .direct {
                    Section("Contact") {
                        Button("Preferences…") { showContactPreferences = true }
                    }
                    Section("Security") {
                        Button("Security Code…") {
                            showSecurityCode = true
                        }
                    }
                }

                Section("Actions") {
                    Button("Chat Wallpaper…") {
                        showWallpaperEditor = true
                    }
                    Button("Tags…") {
                        model.tagAssignmentChat = chat
                    }
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
        .sheet(isPresented: $showEditGroupProfile) {
            GroupProfileEditView(model: model, chat: chat)
        }
        .sheet(isPresented: $showGroupMembers) {
            GroupMembersView(model: model, chat: chat)
        }
        .sheet(isPresented: $showGroupPreferences) {
            GroupPreferencesView(model: model, chat: chat)
        }
        .sheet(isPresented: $showGroupLink) {
            GroupLinkView(model: model, chat: chat)
        }
        .sheet(isPresented: $showSecurityCode) {
            VerifyCodeView(
                contactName: chat.displayName,
                connectionCode: connectionCode,
                connectionVerified: connectionVerified,
                verify: { code in
                    Task {
                        connectionVerified = try await model.verifyContactCode(contactID: chat.apiID, code: code)
                    }
                }
            )
        }
        .sheet(isPresented: $showWallpaperEditor) {
            ChatWallpaperEditorView(chatID: chat.id, chatName: chat.displayName)
        }
        .sheet(isPresented: $showContactPreferences) {
            ContactPreferencesView(model: model, chat: chat)
        }
        .sheet(isPresented: $showGroupReports) {
            GroupReportsView(model: model, chat: chat)
        }
        .task {
            if chat.kind == .direct {
                if let info = try? await model.getContactConnectionInfo(contactID: chat.apiID) {
                    connectionCode = info.connectionCode
                    connectionVerified = info.verified
                }
            }
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
