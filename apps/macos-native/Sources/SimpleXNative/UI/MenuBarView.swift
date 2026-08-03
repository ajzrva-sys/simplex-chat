import AppKit
import SwiftUI

struct MenuBarStatus: Equatable {
    let unreadCount: Int
    let description: String

    init(chats: [NativeChat], phase: AppModel.Phase) {
        unreadCount = chats.reduce(0) { total, chat in
            let count = max(0, chat.unreadCount)
            let (sum, overflow) = total.addingReportingOverflow(count)
            return overflow ? Int.max : sum
        }

        switch phase {
        case .locked:
            description = "Database locked"
        case .opening:
            description = "Opening database"
        case .failed:
            description = "Needs attention"
        case .ready where unreadCount == 0:
            description = "No unread messages"
        case .ready where unreadCount == 1:
            description = "1 unread message"
        case .ready:
            description = "\(unreadCount) unread messages"
        }
    }

    var symbolName: String {
        unreadCount > 0
            ? "bubble.left.and.bubble.right.fill"
            : "bubble.left.and.bubble.right"
    }

    var accessibilityLabel: String {
        "\(AppIdentity.displayName), \(description)"
    }
}

struct NativeChatMenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let status = MenuBarStatus(chats: model.chats, phase: model.phase)
        Image(systemName: status.symbolName)
            .accessibilityLabel(status.accessibilityLabel) // [VERIFY] confirm menu-bar announcement
    }
}

struct NativeChatMenuBarMenu: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: AppModel

    private var status: MenuBarStatus {
        MenuBarStatus(chats: model.chats, phase: model.phase)
    }

    var body: some View {
        if let profile = model.profile {
            Text(profile.displayName)
        }
        Text(status.description)

        Divider()

        Button("Show Native Chat") {
            showWindow(id: MainWindowCommands.windowID)
        }

        Button("Refresh") {
            model.refresh()
        }
        .disabled(model.phase != .ready)

        Divider()

        Button("About Native Chat") {
            showWindow(id: AboutCommands.windowID)
        }

        Button("Quit Native Chat") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func showWindow(id: String) {
        openWindow(id: id)
        NSApp.activate(ignoringOtherApps: true)
    }
}
