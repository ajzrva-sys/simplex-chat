import Foundation

struct UserAddress: Hashable, Sendable {
    let connLinkContact: ConnLinkContact
    let shortLinkDataSet: Bool
    let autoAccept: AutoAccept?
    let autoReply: AutoReply?

    struct ConnLinkContact: Hashable, Sendable {
        let connFullLink: String
        let connShortLink: String?
    }

    struct AutoAccept: Hashable, Sendable {
        let acceptIncognito: Bool
    }

    struct AutoReply: Hashable, Sendable {
        let msgContent: [String: Any]

        static func == (lhs: AutoReply, rhs: AutoReply) -> Bool {
            NSDictionary(dictionary: lhs.msgContent).isEqual(to: rhs.msgContent)
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(NSDictionary(dictionary: msgContent).hash)
        }
    }
}

extension SimpleXCore {
    func getUserAddress() throws -> UserAddress? {
        let data = try sendCommand("/_show_address 1")
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              result["type"] as? String == "userContactLink" else {
            return nil
        }
        return PeopleAndDevicesParser.userAddress(from: result)
    }

    func createUserAddress() throws -> UserAddress {
        let data = try sendCommand("/_address 1")
        try NativeChatParser.validateCommandResponse(data, expectedType: "userContactLinkCreated")
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any] else {
            throw NativeChatError.invalidResponse("The address was not returned.")
        }
        let connLink = result["connLinkContact"] as? [String: Any] ?? [:]
        let fullLink = PeopleAndDevicesParser.string(connLink["connFullLink"]) ?? ""
        let shortLink = PeopleAndDevicesParser.string(connLink["connShortLink"])
        return UserAddress(
            connLinkContact: UserAddress.ConnLinkContact(connFullLink: fullLink, connShortLink: shortLink),
            shortLinkDataSet: shortLink != nil,
            autoAccept: nil,
            autoReply: nil
        )
    }

    func deleteUserAddress() throws {
        try NativeChatParser.validateCommandResponse(sendCommand("/_delete_address 1"))
    }

    func setProfileAddress(enabled: Bool) throws {
        try NativeChatParser.validateCommandResponse(sendCommand("/_profile_address 1 \(enabled ? "on" : "off")"))
    }

    func setAddressSettings(autoAccept: Bool?, incognito: Bool?, autoReplyText: String?) throws -> UserAddress? {
        var settings: [String: Any] = [:]
        if let autoAccept {
            if autoAccept {
                settings["autoAccept"] = ["acceptIncognito": incognito ?? false] as [String: Any]
            } else {
                settings["autoAccept"] = NSNull()
            }
        }
        if let autoReplyText {
            if autoReplyText.isEmpty {
                settings["autoReply"] = NSNull()
            } else {
                settings["autoReply"] = ["type": "text", "text": autoReplyText] as [String: Any]
            }
        }
        let json = try Self.jsonString(settings)
        let data = try sendCommand("/_address_settings 1 \(json)")
        try NativeChatParser.validateCommandResponse(data, expectedType: "userContactLinkUpdated")
        return try getUserAddress()
    }
}

extension PeopleAndDevicesParser {
    static func userAddress(from result: [String: Any]) -> UserAddress? {
        guard let connLink = result["connLinkContact"] as? [String: Any] else { return nil }
        let fullLink = string(connLink["connFullLink"]) ?? ""
        let shortLink = string(connLink["connShortLink"])
        let shortLinkDataSet = bool(result["shortLinkDataSet"]) ?? false

        let autoAcceptDict = result["autoAccept"] as? [String: Any]
        let autoAccept: UserAddress.AutoAccept?
        if let autoAcceptDict {
            autoAccept = UserAddress.AutoAccept(acceptIncognito: bool(autoAcceptDict["acceptIncognito"]) ?? false)
        } else {
            autoAccept = nil
        }

        let autoReplyDict = result["autoReply"] as? [String: Any]
        let autoReply: UserAddress.AutoReply?
        if let autoReplyDict, let msgContent = autoReplyDict["msgContent"] as? [String: Any] {
            autoReply = UserAddress.AutoReply(msgContent: msgContent)
        } else {
            autoReply = nil
        }

        return UserAddress(
            connLinkContact: UserAddress.ConnLinkContact(connFullLink: fullLink, connShortLink: shortLink),
            shortLinkDataSet: shortLinkDataSet,
            autoAccept: autoAccept,
            autoReply: autoReply
        )
    }
}
