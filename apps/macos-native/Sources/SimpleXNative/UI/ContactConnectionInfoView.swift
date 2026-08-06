import SwiftUI

struct VerifyCodeView: View {
    let contactName: String
    let connectionCode: String?
    let connectionVerified: Bool
    let verify: (String?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Security Code")
                .font(.headline)

            if connectionVerified {
                HStack {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                    Text("\(contactName) is verified")
                        .font(.subheadline)
                }
            } else {
                HStack {
                    Image(systemName: "shield")
                        .foregroundStyle(.secondary)
                    Text("\(contactName) is not verified")
                        .font(.subheadline)
                }
            }

            if let code = connectionCode {
                Divider()

                Text(code)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Button("Copy Code") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)

                Text("Compare this code with the one on your contact's device to verify end-to-end encryption.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Divider()

            HStack {
                if connectionVerified {
                    Button("Clear Verification", role: .destructive) {
                        verify(nil)
                        dismiss()
                    }
                } else if let code = connectionCode {
                    Button("Mark as Verified") {
                        verify(code)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                Spacer()
                Button("Done", action: dismiss.callAsFunction)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 380)
    }
}

struct ContactConnectionInfoView: View {
    let contactName: String
    let connectionCode: String?
    let connectionVerified: Bool
    let verify: (String?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Connection Info")
                .font(.headline)

            HStack {
                Text("Contact:")
                    .foregroundStyle(.secondary)
                Text(contactName)
                    .fontWeight(.medium)
            }

            if let code = connectionCode {
                Divider()

                VStack(spacing: 8) {
                    Text("Security Code")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(code)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    HStack {
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(code, forType: .string)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)

                        Spacer()

                        if connectionVerified {
                            Label("Verified", systemImage: "checkmark.shield.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        } else {
                            Button("Verify…") {
                                verify(code)
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.tint)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Done", action: dismiss.callAsFunction)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 360)
    }
}
