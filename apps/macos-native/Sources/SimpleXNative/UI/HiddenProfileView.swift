import SwiftUI

struct HideProfileView: View {
    let profile: ManagedProfile
    let onConfirm: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Hide Profile")
                .font(.headline)

            Text("\"\(profile.displayName)\" will be hidden from the profile list. You'll need a password to reveal it.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            SecureField("Password to show", text: $password)
                .textFieldStyle(.roundedBorder)
            SecureField("Confirm password", text: $confirmPassword)
                .textFieldStyle(.roundedBorder)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Hide Profile") {
                    let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed != password {
                        errorMessage = "Password must not have leading or trailing spaces."
                    } else if trimmed.isEmpty {
                        errorMessage = "Enter a password."
                    } else if password != confirmPassword {
                        errorMessage = "Passwords do not match."
                    } else {
                        onConfirm(trimmed)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(password.isEmpty || confirmPassword.isEmpty)
            }
        }
        .padding()
        .frame(width: 340)
    }
}

struct RevealProfileView: View {
    let onReveal: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Reveal Hidden Profile")
                .font(.headline)

            Text("Enter the password for the hidden profile.")
                .foregroundStyle(.secondary)

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Reveal") {
                    let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        errorMessage = "Enter the password."
                    } else {
                        onReveal(trimmed)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(password.isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
    }
}
