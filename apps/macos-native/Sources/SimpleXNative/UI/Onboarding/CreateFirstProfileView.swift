import SwiftUI

struct CreateFirstProfileView: View {
    @ObservedObject var model: AppModel

    @State private var displayName = ""
    @State private var fullName = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "person.circle")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)

                Text("Create Your Profile")
                    .font(.title.weight(.semibold))

                Text("Choose a display name. You can change it later.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                TextField("Display Name", text: $displayName)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .frame(maxWidth: 320)

                TextField("Full Name (optional)", text: $fullName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }

            Spacer()

            HStack {
                Button("Back") {
                    model.onboardingStage = .simpleXInfo
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Create") {
                    Task { await createProfile() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .disabled(isCreating)
        .overlay {
            if isCreating {
                ProgressView("Creating profile…")
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func createProfile() async {
        isCreating = true
        errorMessage = nil
        do {
            _ = try await model.createFirstProfile(
                displayName: displayName.trimmingCharacters(in: .whitespaces),
                fullName: fullName.trimmingCharacters(in: .whitespaces).isEmpty ? "" : fullName.trimmingCharacters(in: .whitespaces)
            )
            model.onboardingStage = .complete
        } catch {
            errorMessage = error.localizedDescription
            isCreating = false
        }
    }
}
