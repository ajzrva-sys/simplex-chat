import Foundation

struct ChatTag: Identifiable, Hashable, Sendable {
    let id: Int64
    let chatTagId: Int64
    let chatTagText: String
    let chatTagEmoji: String?

    var displayEmoji: String { chatTagEmoji ?? "" }
    var hasEmoji: Bool { !(chatTagEmoji ?? "").isEmpty }
}

struct ChatTagData: Sendable {
    let emoji: String?
    let text: String
}

struct SetChatTagsResult: Sendable {
    let userTags: [ChatTag]
    let chatTagIds: [Int64]
}

extension SimpleXCore {
    func getChatTags(userID: Int64) throws -> [ChatTag] {
        let data = try sendCommand("/_get tags \(userID)")
        return try PeopleAndDevicesParser.chatTags(from: data)
    }

    func createChatTag(userID: Int64, tag: ChatTagData) throws -> [ChatTag] {
        let json = try Self.jsonString(["emoji": tag.emoji as Any, "text": tag.text])
        let data = try sendCommand("/_create tag \(json)")
        return try PeopleAndDevicesParser.chatTags(from: data)
    }

    func updateChatTag(tagId: Int64, tag: ChatTagData) throws {
        let json = try Self.jsonString(["emoji": tag.emoji as Any, "text": tag.text])
        try NativeChatParser.validateCommandResponse(sendCommand("/_update tag \(tagId) \(json)"))
    }

    func deleteChatTag(tagId: Int64) throws {
        try NativeChatParser.validateCommandResponse(sendCommand("/_delete tag \(tagId)"))
    }

    func setChatTags(chatID: String, tagIds: [Int64]?) throws -> SetChatTagsResult {
        let tagList = tagIds.map { ids in ids.map(String.init).joined(separator: ",") } ?? ""
        let data = try sendCommand("/_tags \(chatID) \(tagList)")
        return try PeopleAndDevicesParser.setChatTagsResult(from: data)
    }

    func reorderChatTags(tagIds: [Int64]) throws {
        let tagList = tagIds.map(String.init).joined(separator: ",")
        try NativeChatParser.validateCommandResponse(sendCommand("/_reorder tags \(tagList)"))
    }
}

extension PeopleAndDevicesParser {
    static func chatTags(from data: Data) throws -> [ChatTag] {
        try NativeChatParser.validateCommandResponse(data, expectedType: "chatTags")
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let tagsArray = result["userTags"] as? [[String: Any]] else {
            return []
        }
        return tagsArray.compactMap(parseChatTag)
    }

    static func setChatTagsResult(from data: Data) throws -> SetChatTagsResult {
        try NativeChatParser.validateCommandResponse(data, expectedType: "tagsUpdated")
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any] else {
            return SetChatTagsResult(userTags: [], chatTagIds: [])
        }
        let userTags = (result["userTags"] as? [[String: Any]] ?? []).compactMap(parseChatTag)
        let chatTagIds = (result["chatTagIds"] as? [NSNumber] ?? []).map { $0.int64Value }
        return SetChatTagsResult(userTags: userTags, chatTagIds: chatTagIds)
    }

    static func parseChatTag(_ object: [String: Any]) -> ChatTag? {
        guard let tagId = int64(object["chatTagId"]) else { return nil }
        return ChatTag(
            id: tagId,
            chatTagId: tagId,
            chatTagText: string(object["chatTagText"]) ?? "",
            chatTagEmoji: string(object["chatTagEmoji"])
        )
    }
}
