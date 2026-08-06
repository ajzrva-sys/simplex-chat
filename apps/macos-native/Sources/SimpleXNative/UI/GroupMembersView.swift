import SwiftUI

struct GroupMembersView: View {
    @ObservedObject var model: AppModel
    let chat: NativeChat
    @Environment(\.dismiss) private var dismiss

    @State private var members: [GroupMember] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedMember: GroupMember?
    @State private var showAddMember = false
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && members.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if members.isEmpty {
                    ContentUnavailableView(
                        "No Members",
                        systemImage: "person.2",
                        description: Text("This group has no members yet.")
                    )
                } else {
                    memberList
                }
            }
            .navigationTitle("Members")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddMember = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                    .help("Invite a contact")
                }
            }
            .searchable(text: $searchText, prompt: "Search members")
        }
        .frame(minWidth: 440, minHeight: 480)
        .task { await loadMembers() }
        .sheet(item: $selectedMember) { member in
            GroupMemberInfoView(
                model: model,
                chat: chat,
                member: member,
                onMemberUpdated: { await loadMembers() }
            )
        }
        .sheet(isPresented: $showAddMember) {
            AddGroupMembersView(
                model: model,
                chat: chat,
                existingMemberIDs: Set(members.map(\.id)),
                onMemberAdded: { await loadMembers() }
            )
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var memberList: some View {
        List {
            if !filteredActiveMembers.isEmpty {
                Section("Active") {
                    ForEach(filteredActiveMembers) { member in
                        memberRow(member)
                    }
                }
            }

            if !filteredInactiveMembers.isEmpty {
                Section("Inactive") {
                    ForEach(filteredInactiveMembers) { member in
                        memberRow(member)
                    }
                }
            }
        }
    }

    private var filteredActiveMembers: [GroupMember] {
        let active = members.filter { $0.isActive }
        if searchText.isEmpty { return active }
        return active.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredInactiveMembers: [GroupMember] {
        let inactive = members.filter { !$0.isActive }
        if searchText.isEmpty { return inactive }
        return inactive.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
    }

    private func memberRow(_ member: GroupMember) -> some View {
        Button {
            selectedMember = member
        } label: {
            HStack(spacing: 12) {
                ProfileAvatar(image: member.image, name: member.displayName, size: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.displayName)
                    HStack(spacing: 4) {
                        Text(member.memberRole.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if member.blocked {
                            Text("Blocked")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(member.displayName), \(member.memberRole.displayName)")
    }

    private func loadMembers() async {
        isLoading = true
        defer { isLoading = false }
        do {
            members = try await model.getGroupMembers(groupID: chat.apiID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
