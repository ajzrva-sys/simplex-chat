import SwiftUI

struct NativeSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var notifications: NativeNotificationManager
    @State private var currentPassphrase = ""
    @State private var newPassphrase = ""
    @State private var confirmPassphrase = ""
    @State private var rememberNewPassphrase = true
    @State private var confirmImport = false
    @State private var migrationRequest: DeviceMigrationMode?
    @State private var showSetAppPasscode = false

    var body: some View {
        TabView {
            general
                .tabItem { Label("General", systemImage: "gear") }
            privacy
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
            notificationsView
                .tabItem { Label("Notifications", systemImage: "bell") }
            network
                .tabItem { Label("Network", systemImage: "network") }
            servers
                .tabItem { Label("Servers", systemImage: "server.rack") }
            database
                .tabItem { Label("Database", systemImage: "externaldrive") }
        }
        .padding(20)
        .frame(width: 640, height: 560)
        .overlay(alignment: .top) {
            if model.isSavingSettings { ProgressView().padding(8) }
        }
        .alert("Settings Error", isPresented: Binding(
            get: { model.settingsError != nil },
            set: { if !$0 { model.settingsError = nil } }
        )) {
            Button("OK") { model.settingsError = nil }
        } message: {
            Text(model.settingsError ?? "")
        }
        .task { model.loadAdvancedSettings() }
        .sheet(item: $migrationRequest) { mode in
            DeviceMigrationView(
                coordinator: model.deviceMigrationCoordinator,
                initialMode: mode
            )
        }
        .sheet(isPresented: $showAppearanceSettings) {
            AppearanceSettingsView(model: model)
        }
    }

    @State private var showAppearanceSettings = false
    @AppStorage("nativeChat.updateChannel") private var updateChannel = "stable"

    private var general: some View {
        Form {
            Section("Interface") {
                Button("Appearance…") { showAppearanceSettings = true }
                LabeledContent("Profile", value: model.profile?.displayName ?? "Locked")
                Picker("Chat density", selection: $model.density) {
                    ForEach(DesktopChatDensity.allCases) { density in
                        Text(density.title).tag(density)
                    }
                }
                .pickerStyle(.radioGroup)
                Toggle("Save conversation drafts", isOn: $model.settingsSnapshot.saveDrafts)
                Toggle("Show message previews in chat list", isOn: $model.settingsSnapshot.showChatPreviews)
            }
            Section("Account") {
                Button("Manage Profiles, Contacts & Linked Devices") {
                    model.featureCenterPresented = true
                }
            }
            Section("Updates") {
                Picker("Update channel", selection: $updateChannel) {
                    Text("Stable").tag("stable")
                    Text("Beta").tag("beta")
                    Text("Disabled").tag("disabled")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var privacy: some View {
        Form {
            Section("App Lock") {
                LabeledContent("App passcode", value: model.appPasscodeEnabled ? "Enabled" : "Disabled")
                LabeledContent("Self-destruct passcode", value: model.selfDestructPasscodeEnabled ? "Set" : "Not set")
                Button(model.appPasscodeEnabled ? "Change App Passcode" : "Set App Passcode") {
                    showSetAppPasscode = true
                }
            }
            Section("Message Content") {
                Toggle("Show link previews", isOn: $model.settingsSnapshot.showLinkPreviews)
                Toggle("Remove tracking information from links", isOn: $model.settingsSnapshot.sanitizeLinks)
                Toggle("Automatically accept images", isOn: $model.settingsSnapshot.autoAcceptImages)
                Toggle("Show encryption indicators", isOn: $model.settingsSnapshot.showEncryptionIndicators)
                Picker("Media blur", selection: $model.settingsSnapshot.mediaBlurRadius) {
                    Text("Off").tag(0)
                    Text("Soft").tag(12)
                    Text("Medium").tag(24)
                    Text("Strong").tag(48)
                }
            }
            Section("Files and Network Privacy") {
                Toggle("Encrypt local files", isOn: $model.settingsSnapshot.encryptLocalFiles)
                Toggle("Protect IP address with relays", isOn: $model.settingsSnapshot.protectIPAddress)
            }
            Section("Delivery Receipts") {
                Toggle("Contacts", isOn: $model.settingsSnapshot.deliveryReceiptsContacts)
                Toggle("Groups", isOn: $model.settingsSnapshot.deliveryReceiptsGroups)
            }
            Section("Automatic Message Deletion") {
                Picker("Keep messages", selection: $model.settingsSnapshot.messageRetentionDays) {
                    Text("Forever").tag(Int?.none)
                    Text("1 day").tag(Int?.some(1))
                    Text("7 days").tag(Int?.some(7))
                    Text("30 days").tag(Int?.some(30))
                    Text("90 days").tag(Int?.some(90))
                }
            }
            Button("Save Privacy Settings", action: model.savePrivacySettings)
                .disabled(model.isSavingSettings)
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showSetAppPasscode) {
            SetAppPasscodeView(model: model)
        }
    }

    private var notificationsView: some View {
        Form {
            Section("Mac Notifications") {
                LabeledContent("Permission", value: notifications.permissionState.title)
                Picker("Show previews", selection: $notifications.previewMode) {
                    ForEach(NotificationPreviewMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Toggle("Play notification sounds", isOn: $notifications.soundsEnabled)
                Button("Open Mac Notification Settings", action: notifications.openSystemSettings)
            }
        }
        .formStyle(.grouped)
    }

    private var network: some View {
        Form {
            Section("Network Configuration") {
                Text("Proxy, onion-routing, session, transport, and ICE settings are represented by the core’s validated configuration.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $model.networkConfigurationText)
                    .font(.body.monospaced())
                    .frame(minHeight: 300)
                    .accessibilityLabel("Network configuration JSON")
                HStack {
                    Button("Reload", action: model.loadAdvancedSettings)
                    Spacer()
                    Button("Validate & Save", action: model.saveNetworkSettings)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var servers: some View {
        Form {
            Section("SMP and XFTP Servers") {
                Text("Edit the ordered server list. Native Chat validates the list with the core before saving it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $model.serverConfigurationText)
                    .font(.body.monospaced())
                    .frame(minHeight: 300)
                    .accessibilityLabel("Server configuration JSON")
                HStack {
                    Button("Reconnect All", action: model.reconnectServers)
                    Spacer()
                    Button("Validate & Save", action: model.saveServerSettings)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var database: some View {
        Form {
            Section("Mac Keychain") {
                LabeledContent("Database passphrase", value: keychainPassphraseStatus)
                Button("Forget Saved Passphrase", role: .destructive, action: model.forgetSavedPassphrase)
                    .disabled(!model.keychainPassphraseStorageAvailable || !model.hasStoredPassphrase)
                if let message = model.keychainStatusMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Change Database Passphrase") {
                SecureField("Current passphrase", text: $currentPassphrase)
                SecureField("New passphrase", text: $newPassphrase)
                SecureField("Confirm new passphrase", text: $confirmPassphrase)
                Toggle("Remember new passphrase in Mac Keychain", isOn: $rememberNewPassphrase)
                Button("Change Passphrase") {
                    guard newPassphrase == confirmPassphrase else {
                        model.settingsError = "The new passphrases do not match."
                        return
                    }
                    model.changeDatabasePassphrase(
                        current: currentPassphrase,
                        new: newPassphrase,
                        remember: rememberNewPassphrase
                    )
                    currentPassphrase = ""
                    newPassphrase = ""
                    confirmPassphrase = ""
                }
                .disabled(currentPassphrase.isEmpty || newPassphrase != confirmPassphrase)
            }
            Section("Backup and Restore") {
                Button("Export Encrypted Database…", action: model.exportDatabase)
                Button("Import Database…", role: .destructive) { confirmImport = true }
                Button("Show Database Folder", action: model.openDatabaseFolder)
            }
            Section("Move Between Devices") {
                Button("Import from Phone with QR Code…") {
                    migrationRequest = .importFromPhone
                }
                Button("Export to Phone with QR Code…") {
                    migrationRequest = .exportToPhone
                }
                Text("Transfers use an encrypted archive and a one-time SimpleX file link.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Importing replaces the current database. Continue?",
            isPresented: $confirmImport,
            titleVisibility: .visible
        ) {
            Button("Choose Backup…", role: .destructive, action: model.importDatabase)
            Button("Cancel", role: .cancel) {}
        }
    }

    private var keychainPassphraseStatus: String {
        guard model.keychainPassphraseStorageAvailable else { return "Unavailable in this build" }
        return model.hasStoredPassphrase ? "Saved in Mac Keychain" : "Not saved"
    }
}
