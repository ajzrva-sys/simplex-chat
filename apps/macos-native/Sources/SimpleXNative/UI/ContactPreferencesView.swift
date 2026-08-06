import SwiftUI

struct ContactPreferencesView: View {
    @ObservedObject var model: AppModel
    let chat: NativeChat
    @Environment(\.dismiss) private var dismiss

    @State private var prefs = ContactFeaturesAllowed(
        timedMessagesAllowed: false,
        timedMessagesTTL: nil,
        fullDelete: .userDefault(.no),
        reactions: .userDefault(.yes),
        voice: .userDefault(.yes),
        files: .userDefault(.yes),
        calls: .userDefault(.yes)
    )
    @State private var mergedPrefs: ContactUserPreferences?
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if let merged = mergedPrefs {
                    featureSection(
                        feature: .voice,
                        enabled: merged.voice.enabled,
                        binding: $prefs.voice
                    )
                    featureSection(
                        feature: .files,
                        enabled: merged.files.enabled,
                        binding: $prefs.files
                    )
                    featureSection(
                        feature: .reactions,
                        enabled: merged.reactions.enabled,
                        binding: $prefs.reactions
                    )
                    featureSection(
                        feature: .fullDelete,
                        enabled: merged.fullDelete.enabled,
                        binding: $prefs.fullDelete
                    )
                    timedMessagesSection(merged: merged.timedMessages)
                    featureSection(
                        feature: .calls,
                        enabled: merged.calls.enabled,
                        binding: $prefs.calls
                    )
                }

                if isLoading {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }

                Section {
                    Text("Per-contact preferences override your defaults for this contact. Changes are sent to the contact.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Preferences")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isSaving || isLoading)
                }
            }
            .disabled(isSaving)
            .overlay {
                if isSaving {
                    ProgressView()
                }
            }
            .task { await loadPreferences() }
        }
        .frame(width: 440, height: 520)
    }

    @ViewBuilder
    private func featureSection(
        feature: ChatFeature,
        enabled: FeatureEnabled,
        binding: Binding<ContactFeatureAllowed>
    ) -> some View {
        Section {
            Picker(selection: binding) {
                ForEach([ContactFeatureAllowed.userDefault(.yes), .userDefault(.no), .always, .yes, .no], id: \.self) { option in
                    Text(option.label).tag(option)
                }
            } label: {
                Label(feature.label, systemImage: feature.icon)
            }

            HStack {
                Text("Contact allows")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(contactAllowsText(feature: feature))
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        }
    }

    @ViewBuilder
    private func timedMessagesSection(merged: ContactUserPreferenceTimed) -> some View {
        Section {
            Toggle(isOn: Binding(
                get: { prefs.timedMessagesAllowed },
                set: { prefs.timedMessagesAllowed = $0 }
            )) {
                Label("Disappearing messages", systemImage: "timer")
            }

            if prefs.timedMessagesAllowed {
                Picker("Timer", selection: Binding(
                    get: { prefs.timedMessagesTTL ?? 86400 },
                    set: { prefs.timedMessagesTTL = $0 }
                )) {
                    Text("1 minute").tag(60)
                    Text("5 minutes").tag(300)
                    Text("1 hour").tag(3600)
                    Text("1 day").tag(86400)
                    Text("1 week").tag(604800)
                }
            }

            HStack {
                Text("Contact allows")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(merged.enabled.forContact ? "Yes" : "No")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        }
    }

    private func contactAllowsText(feature: ChatFeature) -> String {
        guard let merged = mergedPrefs else { return "—" }
        let enabled: FeatureEnabled
        switch feature {
        case .timedMessages: enabled = merged.timedMessages.enabled
        case .fullDelete: enabled = merged.fullDelete.enabled
        case .reactions: enabled = merged.reactions.enabled
        case .voice: enabled = merged.voice.enabled
        case .files: enabled = merged.files.enabled
        case .calls: enabled = merged.calls.enabled
        }
        if enabled.forContact && enabled.forUser { return "Yes" }
        if enabled.forContact { return "Yes (you: no)" }
        if enabled.forUser { return "No (you: yes)" }
        return "No"
    }

    private func loadPreferences() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let parsed = try await model.loadContactMergedPreferences(contactID: chat.apiID)
            mergedPrefs = parsed
            prefs = ContactPreferencesParser.contactUserPrefsToFeaturesAllowed(parsed)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                let json = try ContactPreferencesParser.featuresAllowedToPrefsJSON(prefs)
                try await model.setContactPreferences(contactID: chat.apiID, preferences: json)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
