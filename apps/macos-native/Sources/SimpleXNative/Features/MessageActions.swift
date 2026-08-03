import Foundation

extension SimpleXCore {
    func editMessage(_ messageID: Int64, text: String, in chat: NativeChat) throws {
        let payload: [String: Any] = [
            "msgContent": ["type": "text", "text": text],
            "mentions": [:],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw NativeChatError.invalidResponse("The edited message could not be encoded.")
        }
        try NativeChatParser.validateCommandResponse(sendCommand(
            "/_update item \(chat.id) \(messageID) live=off json \(json)"
        ))
    }

    func setReaction(_ emoji: String, add: Bool, messageID: Int64, in chat: NativeChat) throws {
        let normalized = emoji == "❤️" ? "❤" : emoji
        let payload = ["type": "emoji", "emoji": normalized]
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw NativeChatError.invalidResponse("The reaction could not be encoded.")
        }
        try NativeChatParser.validateCommandResponse(sendCommand(
            "/_reaction \(chat.id) \(messageID) \(add ? "on" : "off") \(json)"
        ))
    }

    func forwardMessages(_ messageIDs: [Int64], from source: NativeChat, to destination: NativeChat) throws {
        guard !messageIDs.isEmpty else { return }
        let groupOption = destination.sendAsGroup ? " as_group=on" : ""
        try NativeChatParser.validateCommandResponse(sendCommand(
            "/_forward \(destination.id)\(groupOption) \(source.id) \(messageIDs.map(String.init).joined(separator: ",")) ttl=default"
        ))
    }

    func clearChat(_ chat: NativeChat) throws {
        try NativeChatParser.validateCommandResponse(sendCommand("/_clear chat \(chat.id)"))
    }

    func deleteChat(_ chat: NativeChat, notify: Bool) throws {
        try NativeChatParser.validateCommandResponse(sendCommand(
            "/_delete \(chat.id) full notify=\(notify ? "on" : "off")"
        ))
    }

    func leaveGroup(_ chat: NativeChat) throws {
        guard chat.kind == .group else { return }
        try NativeChatParser.validateCommandResponse(sendCommand("/_leave \(chat.id)"))
    }
}
