import Foundation

extension SimpleXCore {
    func setEncryptLocalFiles(_ enabled: Bool) throws {
        try NativeChatParser.validateCommandResponse(sendCommand("/_files_encrypt \(enabled ? "on" : "off")"))
    }

    func setDeliveryReceipts(userID: Int64, contacts: Bool, groups: Bool) throws {
        try NativeChatParser.validateCommandResponse(sendCommand(
            "/_set receipts contacts \(userID) \(contacts ? "on" : "off") clear_overrides=off"
        ))
        try NativeChatParser.validateCommandResponse(sendCommand(
            "/_set receipts groups \(userID) \(groups ? "on" : "off") clear_overrides=off"
        ))
    }

    func setMessageRetention(userID: Int64, days: Int?) throws {
        let value = days.map { String($0 * 86_400) } ?? "none"
        try NativeChatParser.validateCommandResponse(sendCommand("/_ttl \(userID) \(value)"))
    }

    func networkConfigurationJSON(forceLocal: Bool = false) throws -> String {
        try resultJSON(command: "/network", expectedType: "networkConfig", valueKey: "networkConfig", forceLocal: forceLocal)
    }

    func saveNetworkConfiguration(json: String) throws {
        try Self.validateJSONObject(json)
        try NativeChatParser.validateCommandResponse(sendCommand("/_network \(json)"))
    }

    func serverConfigurationJSON(userID: Int64) throws -> String {
        try resultJSON(command: "/_servers \(userID)", expectedType: "userServers", valueKey: "userServers")
    }

    func saveServerConfiguration(userID: Int64, json: String) throws {
        try Self.validateJSONArray(json)
        let validation = try sendCommand("/_validate_servers \(userID) \(json)")
        try NativeChatParser.validateCommandResponse(validation)
        try NativeChatParser.validateCommandResponse(sendCommand("/_servers \(userID) \(json)"))
    }

    func reconnectServers() throws {
        try NativeChatParser.validateCommandResponse(sendCommand("/reconnect"))
    }

    func exportDatabase(to archivePath: String, forceLocal: Bool = false) throws {
        let payload = try Self.jsonString(["archivePath": archivePath])
        try NativeChatParser.validateCommandResponse(sendCommand("/_db export \(payload)", forceLocal: forceLocal))
    }

    func importDatabase(from archivePath: String, forceLocal: Bool = false) throws {
        let payload = try Self.jsonString(["archivePath": archivePath])
        try NativeChatParser.validateCommandResponse(sendCommand("/_db import \(payload)", forceLocal: forceLocal))
    }

    func changeDatabasePassphrase(current: String, new: String) throws {
        let payload = try Self.jsonString(["currentKey": current, "newKey": new])
        try NativeChatParser.validateCommandResponse(sendCommand("/_db encryption \(payload)"))
    }

    private func resultJSON(command: String, expectedType: String, valueKey: String, forceLocal: Bool = false) throws -> String {
        let data = try sendCommand(command, forceLocal: forceLocal)
        try NativeChatParser.validateCommandResponse(data, expectedType: expectedType)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let value = result[valueKey] else {
            throw NativeChatError.invalidResponse("The requested settings were missing from the response.")
        }
        let encoded = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        return String(data: encoded, encoding: .utf8) ?? "{}"
    }

    private static func validateJSONObject(_ string: String) throws {
        let value = try JSONSerialization.jsonObject(with: Data(string.utf8))
        guard value is [String: Any] else {
            throw NativeChatError.invalidResponse("Network settings must be a JSON object.")
        }
    }

    private static func validateJSONArray(_ string: String) throws {
        let value = try JSONSerialization.jsonObject(with: Data(string.utf8))
        guard value is [[String: Any]] else {
            throw NativeChatError.invalidResponse("Server settings must be a JSON array.")
        }
    }

    static func jsonString(_ value: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw NativeChatError.invalidResponse("The database operation could not be encoded.")
        }
        return string
    }
}

enum NativeSettingsPersistence {
    private static let key = "nativeChat.settings.v1"

    static func load() -> SettingsSnapshot {
        guard let data = UserDefaults.standard.data(forKey: key),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return SettingsSnapshot()
        }
        var value = SettingsSnapshot()
        value.showLinkPreviews = object["showLinkPreviews"] as? Bool ?? value.showLinkPreviews
        value.sanitizeLinks = object["sanitizeLinks"] as? Bool ?? value.sanitizeLinks
        value.autoAcceptImages = object["autoAcceptImages"] as? Bool ?? value.autoAcceptImages
        value.showChatPreviews = object["showChatPreviews"] as? Bool ?? value.showChatPreviews
        value.saveDrafts = object["saveDrafts"] as? Bool ?? value.saveDrafts
        value.encryptLocalFiles = object["encryptLocalFiles"] as? Bool ?? value.encryptLocalFiles
        value.protectIPAddress = object["protectIPAddress"] as? Bool ?? value.protectIPAddress
        value.showEncryptionIndicators = object["showEncryptionIndicators"] as? Bool ?? value.showEncryptionIndicators
        value.deliveryReceiptsContacts = object["deliveryReceiptsContacts"] as? Bool ?? value.deliveryReceiptsContacts
        value.deliveryReceiptsGroups = object["deliveryReceiptsGroups"] as? Bool ?? value.deliveryReceiptsGroups
        value.messageRetentionDays = object["messageRetentionDays"] as? Int
        value.mediaBlurRadius = object["mediaBlurRadius"] as? Int ?? value.mediaBlurRadius
        value.accentColorName = object["accentColorName"] as? String ?? value.accentColorName
        value.fontScale = object["fontScale"] as? Double ?? value.fontScale
        return value
    }

    static func save(_ value: SettingsSnapshot) {
        var object: [String: Any] = [
            "showLinkPreviews": value.showLinkPreviews,
            "sanitizeLinks": value.sanitizeLinks,
            "autoAcceptImages": value.autoAcceptImages,
            "showChatPreviews": value.showChatPreviews,
            "saveDrafts": value.saveDrafts,
            "encryptLocalFiles": value.encryptLocalFiles,
            "protectIPAddress": value.protectIPAddress,
            "showEncryptionIndicators": value.showEncryptionIndicators,
            "deliveryReceiptsContacts": value.deliveryReceiptsContacts,
            "deliveryReceiptsGroups": value.deliveryReceiptsGroups,
            "mediaBlurRadius": value.mediaBlurRadius,
            "accentColorName": value.accentColorName,
            "fontScale": value.fontScale,
        ]
        if let days = value.messageRetentionDays { object["messageRetentionDays"] = days }
        if let data = try? JSONSerialization.data(withJSONObject: object) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
