import SwiftUI

struct GroupLinkView: View {
    @ObservedObject var model: AppModel
    let chat: NativeChat
    @Environment(\.dismiss) private var dismiss

    @State private var groupLink: GroupLink?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var selectedRole: GroupMemberRole = .member

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let link = groupLink {
                    existingLinkView(link)
                } else {
                    createLinkView
                }
            }
            .navigationTitle("Group Link")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(width: 480, height: 400)
        .task { await loadLink() }
    }

    @ViewBuilder
    private func existingLinkView(_ link: GroupLink) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Section("Group Invitation Link") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Share this link to invite people to the group:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text(link.connLinkContact)
                                .font(.caption)
                                .lineLimit(3)
                                .textSelection(.enabled)
                            Spacer()
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(link.connLinkContact, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .help("Copy link")
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    HStack {
                        Text("Role:")
                            .foregroundStyle(.secondary)
                        Text(link.memberRole.displayName)
                    }
                    .font(.callout)
                }

                Divider()

                HStack {
                    Button("Create New Link") {
                        Task { await createLink() }
                    }
                    Spacer()
                    Button("Delete Link…", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
            .padding()
        }
        .confirmationDialog(
            "Delete the group link?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Link", role: .destructive) {
                Task { await deleteLink() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("People will no longer be able to join using this link. This cannot be undone.")
        }
    }

    private var createLinkView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "link.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Create a Group Link")
                .font(.title2.weight(.semibold))
            Text("Generate a link you can share so others can join this group.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            Picker("Invite as", selection: $selectedRole) {
                ForEach(GroupMemberRole.assignable, id: \.self) { role in
                    Text(role.displayName).tag(role)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 200)

            Button("Create Link") {
                Task { await createLink() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
            Spacer()
        }
        .padding()
    }

    private func loadLink() async {
        isLoading = true
        defer { isLoading = false }
        do {
            groupLink = try await model.getGroupLink(groupID: chat.apiID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createLink() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            groupLink = try await model.createGroupLink(groupID: chat.apiID, role: selectedRole)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteLink() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await model.deleteGroupLink(groupID: chat.apiID)
            groupLink = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
