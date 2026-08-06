import SwiftUI

struct MessageInfoView: View {
    let message: NativeMessage
    let chat: NativeChat
    let info: ChatItemInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Message") {
                    LabeledContent("Sent", value: message.sent ? "Yes" : "No")
                    if let ts = message.timestamp {
                        LabeledContent("Time", value: ts.formatted(date: .abbreviated, time: .shortened))
                    }
                    LabeledContent("ID", value: String(message.id))
                }

                if !info.itemVersions.isEmpty {
                    Section("History") {
                        ForEach(info.itemVersions) { version in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(version.displayText)
                                    .font(.body)
                                Text(version.itemVersionTs)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                if let statuses = info.memberDeliveryStatuses, !statuses.isEmpty {
                    Section("Delivery") {
                        ForEach(statuses) { member in
                            HStack {
                                Text(member.memberDisplayName)
                                    .font(.body)
                                Spacer()
                                Image(systemName: member.status.icon)
                                    .foregroundStyle(statusColor(member.status))
                                Text(member.status.label)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if info.itemVersions.isEmpty && (info.memberDeliveryStatuses?.isEmpty ?? true) {
                    Section {
                        Text("No additional information available for this message.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Message Info")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
        .frame(width: 420, height: 440)
    }

    private func statusColor(_ status: GroupSndStatus) -> Color {
        switch status {
        case .rcvdOk: .green
        case .error: .red
        case .warning, .rcvdBadHash: .orange
        default: .secondary
        }
    }
}
