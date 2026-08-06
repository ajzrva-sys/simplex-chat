import SwiftUI

struct AddGroupMembersView: View {
    @ObservedObject var model: AppModel
    let chat: NativeChat
    let existingMemberIDs: Set<Int64>
    let onMemberAdded: () async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var contacts: [NativeChat] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedRole: GroupMemberRole = .member
    @State private var addingContactID: NativeChat.ID?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && contacts.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredContacts.isEmpty {
                    ContentUnavailableView(
                        "No Contacts to Invite",
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text(searchText.isEmpty
                            ? "All your contacts are already members of this group."
                            : "No contacts match your search.")
                    )
                } else {
                    contactList
                }
            }
            .navigationTitle("Invite Members")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
            .searchable(text: $searchText, prompt: "Search contacts")
        }
        .frame(minWidth: 440, minHeight: 480)
        .task { loadContacts() }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var filteredContacts: [NativeChat] {
        let eligible = contacts.filter { contact in
            !existingMemberIDs.contains(contact.apiID)
        }
        if searchText.isEmpty { return eligible }
        return eligible.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
    }

    private var contactList: some View {
        List {
            Section("Role") {
                Picker("Invite as", selection: $selectedRole) {
                    ForEach(GroupMemberRole.assignable, id: \.self) { role in
                        Text(role.displayName).tag(role)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Contacts") {
                ForEach(filteredContacts) { contact in
                    HStack(spacing: 12) {
                        ProfileAvatar(image: contact.image, name: contact.displayName, size: 32)
                            .accessibilityHidden(true)
                        Text(contact.displayName)
                        Spacer()
                        if addingContactID == contact.id {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button("Invite") {
                                Task { await inviteContact(contact) }
                            }
                            .disabled(addingContactID != nil)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func loadContacts() {
        isLoading = true
        defer { isLoading = false }
        contacts = model.chats.filter { $0.kind == .direct }
    }

    private func inviteContact(_ contact: NativeChat) async {
        addingContactID = contact.id
        errorMessage = nil
        defer { addingContactID = nil }
        do {
            try await model.addGroupMember(
                groupID: chat.apiID,
                contactID: contact.apiID,
                role: selectedRole
            )
            await onMemberAdded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
