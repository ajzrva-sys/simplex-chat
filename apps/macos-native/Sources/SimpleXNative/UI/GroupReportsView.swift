import SwiftUI

struct GroupReportsView: View {
    @ObservedObject var model: AppModel
    let chat: NativeChat
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(reportMessages) { message in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(message.author ?? "Unknown")
                                .font(.caption.weight(.medium))
                            Spacer()
                            if let ts = message.timestamp {
                                Text(ts.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(message.text)
                            .font(.body)
                    }
                    .padding(.vertical, 4)
                }
            }
            .overlay {
                if reportMessages.isEmpty {
                    ContentUnavailableView(
                        "No Reports",
                        systemImage: "exclamationmark.bubble",
                        description: Text("No reported messages in this group.")
                    )
                }
            }
            .navigationTitle("Member Reports")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .automatic) {
                    Button("Archive All") {
                        Task {
                            try? await model.deleteReceivedReports(groupID: chat.apiID)
                            dismiss()
                        }
                    }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 400)
    }

    private var reportMessages: [NativeMessage] {
        model.messages.filter { msg in
            msg.content == .text && msg.text.contains("report")
        }
    }
}
