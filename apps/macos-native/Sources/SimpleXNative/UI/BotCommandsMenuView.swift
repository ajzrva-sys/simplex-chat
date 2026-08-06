import SwiftUI

struct BotCommandsMenuView: View {
    let commands: [ChatBotCommand]
    let filter: String
    let onSelect: (ChatBotCommand) -> Void
    @State private var menuPath: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !menuPath.isEmpty {
                HStack {
                    Button {
                        menuPath.removeLast()
                    } label: {
                        Image(systemName: "chevron.left")
                        Text(menuPath.last ?? "Back")
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    Divider()
                }
            }

            let filtered = filteredCommands
            if filtered.isEmpty {
                Text("No matching commands")
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ForEach(Array(filtered.enumerated()), id: \.offset) { _, cmd in
                    Button {
                        onSelect(cmd)
                    } label: {
                        HStack {
                            Text(cmd.displayLabel)
                                .foregroundStyle(.primary)
                            Spacer()
                            if case .menu = cmd {
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }

    private var currentCommands: [ChatBotCommand] {
        var cmds = commands
        for label in menuPath {
            guard case .menu(_, let children) = cmds.first(where: {
                if case .menu(let l, _) = $0 { return l == label }
                return false
            }) else { break }
            cmds = children
        }
        return cmds
    }

    private var filteredCommands: [ChatBotCommand] {
        let prefix = filter.hasPrefix("/") ? String(filter.dropFirst()) : filter
        if prefix.isEmpty { return currentCommands }
        return currentCommands.filter { cmd in
            switch cmd {
            case .command(let keyword, let label, _):
                keyword.localizedCaseInsensitiveContains(prefix)
                    || label.localizedCaseInsensitiveContains(prefix)
            case .menu(let label, _):
                label.localizedCaseInsensitiveContains(prefix)
            }
        }
    }
}
