import Foundation

struct ManagedProfile: Identifiable, Hashable, Sendable {
    let id: Int64
    let displayName: String
    let image: String?
    let active: Bool
    let hidden: Bool
    let notificationsEnabled: Bool
    let unreadCount: Int
}

struct LinkedDevice: Identifiable, Hashable, Sendable {
    let id: Int64
    let name: String
    let state: RemoteHostState
}

struct RemotePairing: Equatable, Sendable {
    let remoteHostID: Int64?
    let invitation: String
    let sessionCode: String?
}

enum PeopleAndDevicesParser {
    static func profiles(from data: Data) throws -> [ManagedProfile] {
        let result = try resultObject(from: data, type: "usersList")
        let values = result["users"] as? [[String: Any]] ?? []
        return values.compactMap { entry in
            let user = entry["user"] as? [String: Any] ?? entry
            let profile = user["profile"] as? [String: Any]
            guard let id = int64(user["userId"]),
                  let name = string(profile?["displayName"]) ?? string(user["localDisplayName"]) else { return nil }
            return ManagedProfile(
                id: id,
                displayName: name,
                image: string(profile?["image"]),
                active: bool(user["activeUser"]) ?? false,
                hidden: user["viewPwdHash"] != nil && !(user["viewPwdHash"] is NSNull),
                notificationsEnabled: bool(user["showNtfs"]) ?? true,
                unreadCount: int(entry["unreadCount"]) ?? 0
            )
        }
    }

    static func linkedDevices(from data: Data) throws -> [LinkedDevice] {
        let result = try resultObject(from: data, type: "remoteHostList")
        return (result["remoteHosts"] as? [[String: Any]] ?? []).compactMap { host in
            guard let id = int64(host["remoteHostId"]) else { return nil }
            return LinkedDevice(
                id: id,
                name: string(host["hostDeviceName"]) ?? "Linked Mac or mobile device",
                state: remoteState(host["sessionState"])
            )
        }
    }

    static func pairing(from data: Data) throws -> RemotePairing {
        let result = try resultObject(from: data, type: "remoteHostStarted")
        let host = result["remoteHost_"] as? [String: Any]
        return RemotePairing(
            remoteHostID: int64(host?["remoteHostId"]),
            invitation: string(result["invitation"]) ?? "",
            sessionCode: nil
        )
    }

    private static func resultObject(from data: Data, type expectedType: String) throws -> [String: Any] {
        try NativeChatParser.validateCommandResponse(data, expectedType: expectedType)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any] else {
            throw NativeChatError.invalidResponse("The chat service returned no feature data.")
        }
        return result
    }

    private static func remoteState(_ value: Any?) -> RemoteHostState {
        guard let state = value as? [String: Any], let type = string(state["type"]) else { return .stopped(reason: nil) }
        switch type {
        case "starting": return .starting
        case "connecting": return .connecting(invitation: string(state["invitation"]) ?? "")
        case "pendingConfirmation": return .pendingConfirmation(code: string(state["sessionCode"]) ?? "")
        case "confirmed", "connected": return .connected(code: string(state["sessionCode"]))
        default: return .stopped(reason: type)
        }
    }

    private static func string(_ value: Any?) -> String? { value as? String }
    private static func bool(_ value: Any?) -> Bool? { value as? Bool }
    private static func int(_ value: Any?) -> Int? { (value as? NSNumber)?.intValue }
    private static func int64(_ value: Any?) -> Int64? { (value as? NSNumber)?.int64Value }
}

extension SimpleXCore {
    func listProfiles() throws -> [ManagedProfile] {
        try PeopleAndDevicesParser.profiles(from: sendCommand("/users"))
    }

    func createProfile(displayName: String, fullName: String) throws -> NativeProfile {
        let value: [String: Any] = [
            "profile": [
                "displayName": displayName,
                "fullName": fullName,
                "shortDescr": NSNull(),
                "image": NSNull(),
            ],
            "pastTimestamp": false,
            "userChatRelay": false,
        ]
        let data = try JSONSerialization.data(withJSONObject: value)
        guard let json = String(data: data, encoding: .utf8) else {
            throw NativeChatError.invalidResponse("The new profile could not be encoded.")
        }
        return try NativeChatParser.profile(from: sendCommand("/_create user \(json)"))
    }

    func listLinkedDevices() throws -> [LinkedDevice] {
        try PeopleAndDevicesParser.linkedDevices(from: sendCommand("/list remote hosts", forceLocal: true))
    }

    func startRemotePairing() throws -> RemotePairing {
        try PeopleAndDevicesParser.pairing(from: sendCommand("/start remote host new", forceLocal: true))
    }

    func stopRemoteHost(_ id: Int64?) throws {
        try NativeChatParser.validateCommandResponse(sendCommand(
            "/stop remote host \(id.map(String.init) ?? "new")",
            forceLocal: true
        ))
    }

    func deleteRemoteHost(_ id: Int64) throws {
        try NativeChatParser.validateCommandResponse(sendCommand("/delete remote host \(id)", forceLocal: true))
    }

    func connectContact(userID: Int64, link: String, incognito: Bool) throws {
        let mode = incognito ? "on" : "off"
        try NativeChatParser.validateCommandResponse(sendCommand("/_connect \(userID) incognito=\(mode) \(link)"))
    }

    func createOneTimeContactInvitation(userID: Int64, incognito: Bool) throws -> String {
        let mode = incognito ? "on" : "off"
        let data = try sendCommand("/_connect \(userID) incognito=\(mode)")
        try NativeChatParser.validateCommandResponse(data)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let result = root?["result"] as? [String: Any]
        return (result?["connLink"] as? String) ?? (result?["connectionLink"] as? String) ?? ""
    }

    func acceptContactRequest(_ id: Int64, incognito: Bool) throws {
        try NativeChatParser.validateCommandResponse(sendCommand("/_accept incognito=\(incognito ? "on" : "off") \(id)"))
    }

    func rejectContactRequest(_ id: Int64) throws {
        try NativeChatParser.validateCommandResponse(sendCommand("/_reject \(id)"))
    }
}
