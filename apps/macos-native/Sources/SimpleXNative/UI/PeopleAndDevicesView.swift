import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

struct PeopleAndDevicesView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSection = 0
    @State private var contactLink = ""
    @State private var useIncognito = false
    @State private var newDisplayName = ""
    @State private var newFullName = ""
    @State private var profileToHide: ManagedProfile?
    @State private var showRevealProfile = false
    @State private var showImagePicker = false
    @State private var showCreateGroup = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("People & Devices")
                    .font(.title2.weight(.semibold))
                Spacer()
                if model.isLoadingFeatures { ProgressView().controlSize(.small) }
                Button("Done", action: dismiss.callAsFunction)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)

            Picker("Section", selection: $selectedSection) {
                Text("Contacts").tag(0)
                Text("Profiles").tag(1)
                Text("Linked Devices").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Divider()
            Group {
                switch selectedSection {
                case 0: contacts
                case 1: profiles
                default: devices
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 560, minHeight: 480)
        .alert("Couldn’t Complete Action", isPresented: Binding(
            get: { model.featureError != nil },
            set: { if !$0 { model.featureError = nil } }
        )) {
            Button("OK") { model.featureError = nil }
        } message: {
            Text(model.featureError ?? "")
        }
        .sheet(isPresented: $model.showUserAddress) {
            UserAddressView(model: model)
        }
        .sheet(isPresented: $showCreateGroup) {
            CreateGroupView(model: model)
        }
        .task { model.reloadPeopleAndDevices() }
    }

    private var contacts: some View {
        Form {
            Section("New Contact") {
                TextField("Paste a SimpleX contact or group link", text: $contactLink)
                    .textFieldStyle(.roundedBorder)
                Toggle("Use an incognito profile", isOn: $useIncognito)
                Button("Connect") {
                    model.connectContact(link: contactLink, incognito: useIncognito)
                }
                .disabled(contactLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isLoadingFeatures)
            }
            Section("Groups") {
                Button("Create Group…") {
                    showCreateGroup = true
                }
            }
            Section("Your Address") {
                Button("Manage SimpleX Address…") {
                    model.showUserAddress = true
                }
            }
            Section("Contact Requests") {
                let requests = model.chats.filter { $0.kind == .contactRequest }
                if requests.isEmpty {
                    Text("No pending contact requests")
                        .foregroundStyle(.secondary)
                }
                ForEach(requests) { request in
                    HStack {
                        ProfileAvatar(image: request.image, name: request.displayName, size: 32)
                            .accessibilityHidden(true)
                        Text(request.displayName)
                        Spacer()
                        Button("Reject", role: .destructive) {
                            model.respondToContactRequest(request, accept: false, incognito: false)
                        }
                        Button("Accept") {
                            model.respondToContactRequest(request, accept: true, incognito: useIncognito)
                        }
                    }
                    .accessibilityElement(children: .contain)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var profiles: some View {
        Form {
            Section("Profiles") {
                let visibleProfiles = model.managedProfiles.filter { !$0.hidden }
                let hiddenProfiles = model.managedProfiles.filter { $0.hidden }

                ForEach(visibleProfiles) { profile in
                    HStack {
                        ProfileAvatar(image: profile.image, name: profile.displayName, size: 32)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading) {
                            Text(profile.displayName)
                            if profile.unreadCount > 0 {
                                Text("\(profile.unreadCount) unread")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if profile.active {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                        } else {
                            Button("Use") { model.activateProfile(profile) }
                            Button("Hide…") { profileToHide = profile }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !hiddenProfiles.isEmpty {
                    HStack {
                        Image(systemName: "eye.slash")
                            .foregroundStyle(.secondary)
                        Text("\(hiddenProfiles.count) hidden profile\(hiddenProfiles.count == 1 ? "" : "s")")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Reveal…") { showRevealProfile = true }
                    }
                }
            }
            Section("Edit Current Profile") {
                HStack {
                    ProfileAvatar(image: model.profile?.image, name: model.profile?.displayName ?? "Profile", size: 48)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading) {
                        Text(model.profile?.displayName ?? "Profile")
                            .font(.headline)
                        Text("Tap to change profile image")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Choose Image…") {
                        showImagePicker = true
                    }
                    if model.profile?.image != nil {
                        Button("Remove", role: .destructive) {
                            Task {
                                try await model.updateUserProfile(
                                    displayName: model.profile?.displayName ?? "",
                                    fullName: "",
                                    image: nil
                                )
                            }
                        }
                    }
                }
            }
            Section("Create Profile") {
                TextField("Display name", text: $newDisplayName)
                TextField("Full name (optional)", text: $newFullName)
                Button("Create Profile") {
                    model.createProfile(displayName: newDisplayName, fullName: newFullName)
                    newDisplayName = ""
                    newFullName = ""
                }
                .disabled(newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .formStyle(.grouped)
        .sheet(item: $profileToHide) { profile in
            HideProfileView(profile: profile) { password in
                Task { try await model.hideProfile(profile, password: password) }
            }
        }
        .sheet(isPresented: $showRevealProfile) {
            RevealProfileView { password in
                if let hidden = model.managedProfiles.first(where: { $0.hidden }) {
                    Task { try await model.revealHiddenProfile(userID: hidden.id, password: password) }
                }
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePickerView { image in
                let cropped = cropToSquare(image)
                if let base64 = compressImageToBase64(cropped) {
                    Task {
                        try await model.updateUserProfile(
                            displayName: model.profile?.displayName ?? "",
                            fullName: "",
                            image: base64
                        )
                    }
                }
            }
        }
    }

    private var devices: some View {
        Form {
            Section("This Conversation Source") {
                HStack {
                    Label("This Mac", systemImage: "desktopcomputer")
                    Spacer()
                    if model.currentRemoteHostID == nil { Image(systemName: "checkmark") }
                    else { Button("Use This Mac") { model.useRemoteHost(nil) } }
                }
            }
            Section("Linked Devices") {
                if model.linkedDevices.isEmpty {
                    Text("No linked mobile devices")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.linkedDevices) { device in
                    HStack {
                        Image(systemName: "iphone")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.name)
                            Text(deviceStatus(device))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.currentRemoteHostID == device.id {
                            Label("In Use", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                        } else if let actionTitle = deviceActionTitle(device) {
                            Button(actionTitle) { model.useRemoteHost(device.id) }
                        }
                        Button("Unlink", role: .destructive) {
                            model.removeRemoteHost(device)
                        }
                        .disabled(model.isLoadingFeatures)
                    }
                    .padding(.vertical, 4)
                }
            }
            Section("Link a Mobile Device") {
                Text("Your phone remains the chat host. Keep both devices on the same local network; while linked, use chats here instead of in the phone app.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if let pairing = model.remotePairing {
                    if let sessionCode = pairing.sessionCode, !sessionCode.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Compare this code with the one on your phone")
                                .font(.headline)
                            Text(sessionCode)
                                .font(.system(size: 32, weight: .semibold, design: .rounded))
                                .textSelection(.enabled)
                            Text("Confirm the matching code on your phone to finish linking.")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    } else if !pairing.invitation.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            if pairing.remoteHostID != nil {
                                // Reconnecting to existing device — multicast discovery
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text("Waiting for your phone to discover this Mac…")
                                        .font(.headline)
                                }
                                Text("Open SimpleX on your phone → Settings → Use from desktop, then choose this Mac. Both devices must be on the same local network.")
                                    .foregroundStyle(.secondary)
                                    .font(.callout)
                                DisclosureGroup("Show QR code (fallback)") {
                                    QRCodeView(value: pairing.invitation)
                                        .frame(width: 180, height: 180)
                                    Button("Copy Pairing Link") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(pairing.invitation, forType: .string)
                                    }
                                    .font(.caption)
                                }
                            } else {
                                // New device — QR code required
                                Text("On your phone, open SimpleX Settings → Use from desktop, then scan this code.")
                                    .font(.headline)
                                QRCodeView(value: pairing.invitation)
                                    .frame(width: 200, height: 200)
                                Button("Copy Pairing Link") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(pairing.invitation, forType: .string)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    } else {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Waiting for your phone…")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button("Cancel Pairing", role: .cancel, action: model.cancelRemotePairing)
                        .disabled(model.isLoadingFeatures)
                } else {
                    Button("Create Pairing Code", action: model.beginRemotePairing)
                        .disabled(model.isLoadingFeatures)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func deviceStatus(_ device: LinkedDevice) -> String {
        switch device.state {
        case .local:
            return "This Mac"
        case .starting:
            return "Starting connection…"
        case .connecting:
            return "Waiting for phone…"
        case let .pendingConfirmation(code):
            return code.isEmpty ? "Waiting for confirmation…" : "Compare code \(code)"
        case .confirmed:
            return "Confirmed on phone…"
        case .connected:
            return "Connected"
        case let .stopped(reason):
            return reason ?? "Not connected"
        }
    }

    private func deviceActionTitle(_ device: LinkedDevice) -> String? {
        switch device.state {
        case .connected:
            return "Use"
        case .stopped:
            return "Connect"
        case .local, .starting, .connecting, .pendingConfirmation, .confirmed:
            return nil
        }
    }
}

private struct QRCodeView: View {
    let value: String

    var body: some View {
        if let image = image {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        }
    }

    private var image: NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let representation = NSCIImageRep(ciImage: output)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}
