import SwiftUI

struct GroupPreferencesView: View {
    @ObservedObject var model: AppModel
    let chat: NativeChat
    @Environment(\.dismiss) private var dismiss

    @State private var voiceAllowed = true
    @State private var filesAllowed = true
    @State private var directMessagesAllowed = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Messaging") {
                    Toggle("Voice messages", isOn: $voiceAllowed)
                    Toggle("Files & media", isOn: $filesAllowed)
                    Toggle("Direct messages between members", isOn: $directMessagesAllowed)
                }

                Section {
                    Text("These settings control what members can do in this group.")
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
            .navigationTitle("Group Preferences")
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
        .frame(width: 400, height: 340)
    }
}
