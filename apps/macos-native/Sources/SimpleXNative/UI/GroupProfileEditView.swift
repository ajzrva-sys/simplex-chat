import SwiftUI

struct GroupProfileEditView: View {
    @ObservedObject var model: AppModel
    let chat: NativeChat
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var fullName = ""
    @State private var description = ""
    @State private var isPublic = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Group Profile") {
                    TextField("Group name", text: $displayName)
                    TextField("Full name (optional)", text: $fullName)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                    Toggle("Public group", isOn: $isPublic)
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
            .navigationTitle("Edit Group Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveProfile() }
                    }
                    .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
            }
            .disabled(isLoading)
            .overlay {
                if isLoading {
                    ProgressView()
                }
            }
        }
        .frame(width: 440, height: 380)
        .task { loadProfile() }
    }

    private func loadProfile() {
        displayName = chat.displayName
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                if let profile = try await model.getGroupProfile(groupID: chat.apiID) {
                    displayName = profile.displayName
                    fullName = profile.fullName
                    description = profile.description
                    isPublic = profile.isPublic
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func saveProfile() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await model.updateGroupProfile(
                groupID: chat.apiID,
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                fullName: fullName,
                description: description,
                isPublic: isPublic
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
