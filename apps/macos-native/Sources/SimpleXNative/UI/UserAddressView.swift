import SwiftUI

struct UserAddressView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var address: UserAddress?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var autoAcceptEnabled = false
    @State private var autoAcceptIncognito = false
    @State private var autoReplyText = ""
    @State private var showSimplexNameEditor = false

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let address {
                existingAddressView(address)
            } else {
                createAddressView
            }
        }
        .frame(width: 480, height: 520)
        .task { await loadAddress() }
    }

    @ViewBuilder
    private func existingAddressView(_ address: UserAddress) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Section("Your SimpleX Address") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Share this link so others can contact you:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text(address.connLinkContact.connFullLink)
                                .font(.caption)
                                .lineLimit(3)
                                .textSelection(.enabled)
                            Spacer()
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(address.connLinkContact.connFullLink, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .help("Copy link")
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }

                Divider()

                Section("SimpleX Name") {
                    Button("Set SimpleX Name…") {
                        showSimplexNameEditor = true
                    }
                    Text("A name others can use to find you instead of your link.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Divider()

                Section("Auto-Accept") {
                    Toggle("Automatically accept contact requests", isOn: $autoAcceptEnabled)
                        .onChange(of: autoAcceptEnabled) { _, _ in saveSettings() }

                    if autoAcceptEnabled {
                        Toggle("Accept with incognito profile", isOn: $autoAcceptIncognito)
                            .onChange(of: autoAcceptIncognito) { _, _ in saveSettings() }
                    }
                }

                Divider()

                Section("Auto-Reply") {
                    Text("Send this message when auto-accepting:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("Welcome message (optional)", text: $autoReplyText, axis: .vertical)
                        .lineLimit(2...5)
                        .onSubmit { saveSettings() }
                }

                Divider()

                HStack {
                    Button("Delete Address…", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                    Spacer()
                    Button("Done", action: dismiss.callAsFunction)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
        }
        .confirmationDialog(
            "Delete your SimpleX address?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Address", role: .destructive) {
                Task { await deleteAddress() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Others will no longer be able to contact you via this link. This cannot be undone.")
        }
        .sheet(isPresented: $showSimplexNameEditor) {
            SetSimplexNameView(
                nameType: .user,
                currentName: nil,
                onSave: { domain in
                    try await model.setSimplexName(domain: domain)
                }
            )
        }
    }

    private var createAddressView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "link.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Create a SimpleX Address")
                .font(.title2.weight(.semibold))
            Text("A long-term link others can use to send you contact requests. You can share it publicly.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            Button("Create Address") {
                Task { await createAddress() }
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

    private func loadAddress() async {
        isLoading = true
        defer { isLoading = false }
        do {
            address = try await model.loadUserAddress()
            if let addr = address {
                autoAcceptEnabled = addr.autoAccept != nil
                autoAcceptIncognito = addr.autoAccept?.acceptIncognito ?? false
                if let reply = addr.autoReply {
                    autoReplyText = reply.msgContent["text"] as? String ?? ""
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createAddress() async {
        isLoading = true
        defer { isLoading = false }
        do {
            address = try await model.createUserAddress()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteAddress() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await model.deleteUserAddress()
            address = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveSettings() {
        Task {
            do {
                address = try await model.saveAddressSettings(
                    autoAccept: autoAcceptEnabled,
                    incognito: autoAcceptIncognito,
                    autoReplyText: autoReplyText.isEmpty ? nil : autoReplyText
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
