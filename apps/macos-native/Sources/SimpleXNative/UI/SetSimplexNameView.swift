import SwiftUI

struct SetSimplexNameView: View {
    let nameType: SimplexNameType
    let currentName: String?
    let onSave: (String) async throws -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var nameText: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    enum SimplexNameType {
        case user
        case channel

        var prefix: String {
            switch self {
            case .user: "@"
            case .channel: "#"
            }
        }

        var placeholder: String {
            switch self {
            case .user: "yourname"
            case .channel: "channelname"
            }
        }

        var title: String {
            switch self {
            case .user: "SimpleX Name"
            case .channel: "Channel Name"
            }
        }
    }

    private static func isValidLabel(_ label: String) -> Bool {
        guard !label.isEmpty else { return false }
        var prev: Character = "\0"
        for ch in label {
            let valid = ch.isLetter || ch.isNumber || ch == "-"
            if !valid { return false }
            if ch == "-" && prev == "-" { return false }
            prev = ch
        }
        return !label.hasSuffix("-")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(nameType.prefix)
                            .foregroundStyle(.secondary)
                        TextField(nameType.placeholder, text: $nameText)
                            .textFieldStyle(.plain)
                            .autocorrectionDisabled()
                    }

                    if !nameText.isEmpty {
                        HStack(spacing: 4) {
                            if isValid {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Valid name")
                                    .foregroundStyle(.green)
                            } else {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                                Text(validationError)
                                    .foregroundStyle(.red)
                            }
                        }
                        .font(.callout)
                    }
                }

                Section {
                    Text("Your SimpleX name lets others find you by name instead of link. Names are case-insensitive and end in .simplex.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
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
            .navigationTitle(nameType.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid || isSaving)
                }
            }
            .disabled(isSaving)
            .overlay {
                if isSaving {
                    ProgressView()
                }
            }
            .onAppear {
                if let current = currentName {
                    nameText = current
                        .replacingOccurrences(of: "@", with: "")
                        .replacingOccurrences(of: "#", with: "")
                        .replacingOccurrences(of: ".simplex", with: "")
                }
            }
        }
        .frame(width: 400, height: 300)
    }

    private var normalized: String {
        let base = nameText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if base.hasSuffix(".simplex") { return base }
        return "\(base).simplex"
    }

    private var labels: [String] {
        normalized.split(separator: ".").map(String.init)
    }

    private var isValid: Bool {
        let parts = labels
        guard parts.count >= 2 else { return false }
        guard normalized.count <= 253 else { return false }
        for label in parts {
            guard label.count >= 1 && label.count <= 63 else { return false }
            guard Self.isValidLabel(label) else { return false }
        }
        return true
    }

    private var validationError: String {
        let parts = labels
        if parts.count < 2 { return "Need at least two labels (e.g., name.simplex)" }
        if normalized.count > 253 { return "Name too long (max 253 characters)" }
        for label in parts {
            if label.count < 1 || label.count > 63 {
                return "Each label must be 1–63 characters"
            }
            if !Self.isValidLabel(label) {
                return "Labels can only contain letters, numbers, and hyphens"
            }
        }
        return "Invalid name"
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                try await onSave(normalized)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
