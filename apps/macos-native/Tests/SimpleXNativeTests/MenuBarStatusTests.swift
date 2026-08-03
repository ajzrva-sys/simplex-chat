import Testing
@testable import SimpleXNative

@Test func menuBarStatusReflectsUnreadActivity() {
    let chats = [
        menuBarTestChat(id: "@1", unreadCount: 2),
        menuBarTestChat(id: "@2", unreadCount: 3),
    ]

    let status = MenuBarStatus(chats: chats, phase: .ready)

    #expect(status.unreadCount == 5)
    #expect(status.description == "5 unread messages")
    #expect(status.symbolName == "bubble.left.and.bubble.right.fill")
    #expect(status.accessibilityLabel == "Native Chat, 5 unread messages")
}

@Test func menuBarStatusCommunicatesLockedStateWithoutUnreadMessages() {
    let status = MenuBarStatus(chats: [], phase: .locked(message: nil))

    #expect(status.unreadCount == 0)
    #expect(status.description == "Database locked")
    #expect(status.symbolName == "bubble.left.and.bubble.right")
    #expect(status.accessibilityLabel == "Native Chat, Database locked")
}

private func menuBarTestChat(id: String, unreadCount: Int) -> NativeChat {
    NativeChat(
        id: id,
        apiID: Int64(id.dropFirst()) ?? 0,
        kind: .direct,
        displayName: id,
        image: nil,
        preview: "",
        timestamp: nil,
        unreadCount: unreadCount,
        sendAsGroup: false
    )
}
