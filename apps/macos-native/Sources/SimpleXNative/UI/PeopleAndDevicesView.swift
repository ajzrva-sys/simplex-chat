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
                ForEach(model.managedProfiles) { profile in
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
                        if profile.hidden { Image(systemName: "eye.slash").help("Hidden profile") }
                        if profile.active {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                        } else {
                            Button("Use") { model.activateProfile(profile) }
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
                        Label(device.name, systemImage: "iphone")
                        Spacer()
                        if model.currentRemoteHostID == device.id {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                        } else {
                            Button("Use") { model.useRemoteHost(device.id) }
                        }
                        Button("Unlink", role: .destructive) { model.removeRemoteHost(device) }
                    }
                }
            }
            Section("Link a Mobile Device") {
                Button("Create Pairing Code", action: model.beginRemotePairing)
                if let pairing = model.remotePairing, !pairing.invitation.isEmpty {
                    QRCodeView(value: pairing.invitation)
                        .frame(width: 180, height: 180)
                        .accessibilityLabel("Mobile pairing QR code")
                    Text(pairing.invitation)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
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
