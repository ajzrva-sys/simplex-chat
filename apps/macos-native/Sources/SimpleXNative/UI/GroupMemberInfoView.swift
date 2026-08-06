import SwiftUI

struct GroupMemberInfoView: View {
    @ObservedObject var model: AppModel
    let chat: NativeChat
    let member: GroupMember
    let onMemberUpdated: () async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedRole: GroupMemberRole
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var destructiveConfirmation: DestructiveAction?

    init(model: AppModel, chat: NativeChat, member: GroupMember, onMemberUpdated: @escaping () async -> Void) {
        self.model = model
        self.chat = chat
        self.member = member
        self.onMemberUpdated = onMemberUpdated
        _selectedRole = State(initialValue: member.memberRole)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        ProfileAvatar(image: member.image, name: member.displayName, size: 56)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(member.displayName)
                                .font(.title3.weight(.semibold))
                            Text(member.memberStatus.displayName)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Role") {
                    Picker("Role", selection: $selectedRole) {
                        ForEach(GroupMemberRole.assignable, id: \.self) { role in
                            Text(role.displayName).tag(role)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(member.memberStatus == .creator)

                    Button("Change Role") {
                        Task { await changeRole() }
                    }
                    .disabled(selectedRole == member.memberRole || member.memberStatus == .creator || isLoading)
                }

                Section("Actions") {
                    if member.blocked {
                        Button("Unblock Member") {
                            Task { await blockMember(blocked: false) }
                        }
                        .disabled(isLoading)
                    } else {
                        Button("Block Member") {
                            Task { await blockMember(blocked: true) }
                        }
                        .disabled(member.memberStatus == .creator || isLoading)
                    }

                    Button("Remove Member…", role: .destructive) {
                        destructiveConfirmation = .remove
                    }
                    .disabled(member.memberStatus == .creator || isLoading)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Member Info")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
            .disabled(isLoading)
            .overlay {
                if isLoading {
                    ProgressView()
                }
            }
        }
        .frame(minWidth: 440, minHeight: 420)
        .confirmationDialog(
            "Remove this member from the group?",
            isPresented: Binding(
                get: { destructiveConfirmation != nil },
                set: { if !$0 { destructiveConfirmation = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove Member", role: .destructive) {
                Task { await removeMember() }
                destructiveConfirmation = nil
            }
            Button("Cancel", role: .cancel) { destructiveConfirmation = nil }
        } message: {
            Text("They will be removed from the group and won't be able to rejoin unless invited again.")
        }
    }

    private func changeRole() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await model.changeMemberRole(
                groupID: chat.apiID,
                memberIDs: [member.memberId],
                role: selectedRole
            )
            await onMemberUpdated()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func blockMember(blocked: Bool) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await model.blockGroupMembers(
                groupID: chat.apiID,
                memberIDs: [member.memberId],
                blocked: blocked
            )
            await onMemberUpdated()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeMember() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await model.removeGroupMembers(
                groupID: chat.apiID,
                memberIDs: [member.memberId],
                messages: false
            )
            await onMemberUpdated()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private enum DestructiveAction {
        case remove
    }
}
