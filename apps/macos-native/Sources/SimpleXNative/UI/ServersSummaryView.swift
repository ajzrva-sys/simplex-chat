import SwiftUI

struct ServersSummaryView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var summary: ServersSummary?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.top, 40)
                    } else if let summary {
                        serverSection(title: "SMP Servers", servers: summary.smpServers)
                        serverSection(title: "XFTP Servers", servers: summary.xftpServers)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.callout)
                            .padding()
                    }
                }
                .padding()
            }
            .navigationTitle("Servers")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .automatic) {
                    Button("Refresh") { Task { await load() } }
                }
            }
        }
        .frame(width: 520, height: 480)
        .task { await load() }
    }

    @ViewBuilder
    private func serverSection(title: String, servers: [ServerSummary]) -> some View {
        Section(title) {
            if servers.isEmpty {
                Text("No servers configured")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(servers) { server in
                    serverRow(server)
                }
            }
        }
    }

    @ViewBuilder
    private func serverRow(_ server: ServerSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(server.isHealthy ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
                Text(serverShortName(server.server))
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                Spacer()
                Text("\(server.connected)/\(server.connected + server.errors + server.connecting)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Label("\(server.activeSubs)", systemImage: "person.2")
                    .font(.caption)
                Label("\(server.totalSent)", systemImage: "arrow.up")
                    .font(.caption)
                Label("\(server.totalRecv)", systemImage: "arrow.down")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func serverShortName(_ server: String) -> String {
        guard let host = server.components(separatedBy: "://").last?.components(separatedBy: ":").first else {
            return server
        }
        return host
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            summary = try await model.loadServersSummary()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
