import SwiftUI

struct CreateGroupView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var fullName = ""
    @State private var description = ""
    @State private var isPublic = false
    @State private var incognito = false
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

                Section("Options") {
                    Toggle("Use incognito profile", isOn: $incognito)
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
            .navigationTitle("Create Group")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await createGroup() }
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
        .frame(width: 440, height: 400)
    }

    private func createGroup() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await model.createGroup(
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                fullName: fullName,
                description: description,
                isPublic: isPublic,
                incognito: incognito
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
