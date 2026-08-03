import AppKit
import SwiftUI

@main
struct SimpleXNativeApp: App {
    private let instanceGuard: SingleInstanceGuard
    @StateObject private var model: AppModel
    @StateObject private var notifications: NativeNotificationManager

    init() {
        guard let instanceGuard = SingleInstanceGuard() else {
            SingleInstanceGuard.activateExistingApplication()
            Darwin.exit(EXIT_SUCCESS)
        }
        self.instanceGuard = instanceGuard
        let notifications = NativeNotificationManager()
        _notifications = StateObject(wrappedValue: notifications)
        _model = StateObject(wrappedValue: AppModel(notificationManager: notifications))
    }

    var body: some Scene {
        Window(AppIdentity.displayName, id: MainWindowCommands.windowID) {
            RootView(model: model, notifications: notifications)
                .frame(minWidth: 760, minHeight: 520)
        }
        .defaultSize(width: 1120, height: 720)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            AboutCommands()
            MainWindowCommands()
            SidebarCommands()
            CommandGroup(replacing: .pasteboard) {
                Button("Cut") { sendFirstResponderAction("cut:") }
                    .keyboardShortcut("x")
                Button("Copy") {
                    switch DesktopCopyCommandRoute.resolve(
                        transcriptFocused: model.transcriptFocused,
                        selectedMessageCount: model.selectedMessageIDs.count
                    ) {
                    case .selectedMessages:
                        model.copySelectedMessages()
                    case .firstResponder:
                        sendFirstResponderAction("copy:")
                    }
                }
                .keyboardShortcut("c")
                Button("Paste") { sendFirstResponderAction("paste:") }
                    .keyboardShortcut("v")
                Button("Select All") {
                    if model.transcriptFocused {
                        model.selectAllMessages()
                    } else {
                        sendFirstResponderAction("selectAll:")
                    }
                }
                .keyboardShortcut("a")
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Find in Conversation") { model.beginConversationSearch() }
                    .keyboardShortcut("f")
                    .disabled(model.selectedChat == nil)
                Button("Search Chats") { model.sidebarSearchPresented = true }
                    .keyboardShortcut("k")
                    .disabled(model.phase != .ready)
            }
            CommandGroup(after: .textEditing) {
                Button("Reply to Selected Message") { model.replyToSelectedMessage() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(!model.canReplyToSelectedMessage)
                Button("Delete Selected Messages") { model.requestDeleteSelectedMessages() }
                    .keyboardShortcut(.delete, modifiers: [])
                    .disabled(!model.transcriptFocused || !model.canDeleteSelectedMessages)
                Button("Cancel Current Action") { model.dismissNearestState() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .disabled(!model.canDismissNearestState)
            }
            CommandMenu("Conversation") {
                Button("Refresh") { model.refresh() }
                    .keyboardShortcut("r")
                Divider()
                Picker("Density", selection: $model.density) {
                    ForEach(DesktopChatDensity.allCases) { density in
                        Text(density.title).tag(density)
                    }
                }
            }
        }

        Window("About \(AppIdentity.displayName)", id: AboutCommands.windowID) {
            AboutView()
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            NativeChatMenuBarMenu(model: model)
        } label: {
            NativeChatMenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            NativeSettingsView(model: model, notifications: notifications)
        }
    }

    private func sendFirstResponderAction(_ name: String) {
        NSApp.sendAction(Selector(name), to: nil, from: nil)
    }

}
