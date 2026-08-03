import AppKit
import SwiftUI

struct AboutView: View {
    private let legalInfo = AppLegalInfo.current
    @State private var presentedDocument: BundledLegalDocument?
    @State private var showingThirdPartyLicenses = false

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text(AppIdentity.displayName)
                    .font(.title.bold())
                Text(legalInfo.versionDescription)
                    .foregroundStyle(.secondary)
            }

            Text("An independent macOS client compatible with the SimpleX network. Native Chat is not affiliated with or endorsed by SimpleX Chat Ltd.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Native Chat is free software released under the GNU Affero General Public License v3. There is no warranty. You may share and modify it under the license terms.")
                    Text(legalInfo.sourceDescription)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            HStack(spacing: 12) {
                Button("View License") {
                    presentedDocument = .license
                }
                Button("View Modifications") {
                    presentedDocument = .modifications
                }
                Link("View Source Code", destination: legalInfo.sourceURL)
            }

            HStack(spacing: 12) {
                Button("Copyright and Warranty") {
                    presentedDocument = .notice
                }
                Button("Third-Party Licenses") {
                    showingThirdPartyLicenses = true
                }
            }

            Text("Copyright © 2026 Native Chat contributors")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 540)
        .sheet(item: $presentedDocument) { document in
            LegalDocumentView(document: document)
        }
        .sheet(isPresented: $showingThirdPartyLicenses) {
            ThirdPartyLicensesView()
        }
    }
}

private struct LegalDocumentView: View {
    @Environment(\.dismiss) private var dismiss
    let document: BundledLegalDocument

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(document.title)
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)

            Divider()

            ScrollView {
                Text(document.text())
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
        }
        .frame(minWidth: 680, minHeight: 560)
    }
}

private struct ThirdPartyLicensesView: View {
    @Environment(\.dismiss) private var dismiss
    private let licenses: [ThirdPartyLicense]
    @State private var selectedID: ThirdPartyLicense.ID?

    init() {
        let licenses = ThirdPartyLicense.bundled()
        self.licenses = licenses
        _selectedID = State(initialValue: licenses.first?.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Third-Party Licenses")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)

            Divider()

            if licenses.isEmpty {
                ContentUnavailableView(
                    "No Licenses Found",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Third-party license files are not available in this development build.")
                )
            } else {
                NavigationSplitView {
                    List(licenses, selection: $selectedID) { license in
                        Text(license.name)
                            .tag(license.id)
                    }
                    .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
                } detail: {
                    if let selectedID,
                       let license = licenses.first(where: { $0.id == selectedID }) {
                        ScrollView {
                            Text(license.text)
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(20)
                        }
                        .navigationTitle(license.name)
                    } else {
                        ContentUnavailableView("Select a License", systemImage: "doc.text")
                    }
                }
            }
        }
        .frame(minWidth: 840, minHeight: 600)
    }
}
