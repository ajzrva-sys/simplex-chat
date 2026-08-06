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

enum LinkedDeviceEvent: Equatable, Sendable {
    case sessionCode(device: LinkedDevice?, code: String)
    case deviceCreated(LinkedDevice)
    case connected(LinkedDevice)
    case stopped(remoteHostID: Int64?, reason: String?)
    case ignored
}

enum PeopleAndDevicesParser {
    static func startRemoteHostCommand(_ id: Int64?) -> String {
        id.map { "/start remote host \($0) multicast=on" } ?? "/start remote host new"
    }

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
        return (result["remoteHosts"] as? [[String: Any]] ?? []).compactMap(linkedDevice)
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

    static func linkedDeviceEvent(from data: Data) -> LinkedDeviceEvent {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let type = string(result["type"]) else { return .ignored }

        switch type {
        case "remoteHostSessionCode":
            guard let code = string(result["sessionCode"]) else { return .ignored }
            let host = (result["remoteHost_"] as? [String: Any]).flatMap(linkedDevice)
            return .sessionCode(device: host, code: code)
        case "newRemoteHost":
            guard let host = result["remoteHost"] as? [String: Any],
                  let device = linkedDevice(host) else { return .ignored }
            return .deviceCreated(device)
        case "remoteHostConnected":
            guard let host = result["remoteHost"] as? [String: Any],
                  let device = linkedDevice(host) else { return .ignored }
            return .connected(device)
        case "remoteHostStopped":
            return .stopped(
                remoteHostID: int64(result["remoteHostId_"]),
                reason: remoteStopReason(result["rhStopReason"])
            )
        default:
            return .ignored
        }
    }

    static func storedRemoteFile(from data: Data) throws -> NativeCryptoFile {
        let result = try resultObject(from: data, type: "remoteFileStored")
        guard let value = result["remoteFileSource"] as? [String: Any],
              let file = cryptoFile(value) else {
            throw NativeChatError.invalidResponse("The phone did not return the stored attachment.")
        }
        return file
    }

    static func remoteFileJSON(
        userID: Int64,
        fileID: Int64,
        sent: Bool,
        fileSource: NativeCryptoFile
    ) throws -> String {
        let value: [String: Any] = [
            "userId": userID,
            "fileId": fileID,
            "sent": sent,
            "fileSource": cryptoFileObject(fileSource),
        ]
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else {
            throw NativeChatError.invalidResponse("The remote attachment request could not be encoded.")
        }
        return json
    }

    private static func resultObject(from data: Data, type expectedType: String) throws -> [String: Any] {
        try NativeChatParser.validateCommandResponse(data, expectedType: expectedType)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any] else {
            throw NativeChatError.invalidResponse("The chat service returned no feature data.")
        }
        return result
    }

    private static func linkedDevice(_ host: [String: Any]) -> LinkedDevice? {
        guard let id = int64(host["remoteHostId"]) else { return nil }
        return LinkedDevice(
            id: id,
            name: string(host["hostDeviceName"]) ?? "Linked mobile device",
            state: remoteState(host["sessionState"])
        )
    }

    private static func remoteState(_ value: Any?) -> RemoteHostState {
        guard let state = value as? [String: Any], let type = string(state["type"]) else { return .stopped(reason: nil) }
        switch type {
        case "starting": return .starting
        case "connecting": return .connecting(invitation: string(state["invitation"]) ?? "")
        case "pendingConfirmation": return .pendingConfirmation(code: string(state["sessionCode"]) ?? "")
        case "confirmed": return .confirmed(code: string(state["sessionCode"]) ?? "")
        case "connected": return .connected(code: string(state["sessionCode"]))
        case "stopped": return .stopped(reason: nil)
        default: return .stopped(reason: type)
        }
    }

    private static func remoteStopReason(_ value: Any?) -> String? {
        guard let reason = value as? [String: Any],
              let type = string(reason["type"]) else { return nil }
        switch type {
        case "disconnected":
            return nil
        case "connectionFailed":
            return "The connection to the phone failed. Keep both devices on the same local network and try again."
        case "crashed":
            return "The linked-device session stopped unexpectedly. Open SimpleX on the phone and reconnect."
        default:
            return "The linked-device session stopped (\(type))."
        }
    }

    private static func cryptoFile(_ value: [String: Any]) -> NativeCryptoFile? {
        guard let path = string(value["filePath"]) else { return nil }
        let args: NativeCryptoFileArgs?
        if let crypto = value["cryptoArgs"] as? [String: Any],
           let key = string(crypto["fileKey"]),
           let nonce = string(crypto["fileNonce"]) {
            args = NativeCryptoFileArgs(fileKey: key, fileNonce: nonce)
        } else {
            args = nil
        }
        return NativeCryptoFile(filePath: path, cryptoArgs: args)
    }

    static func cryptoFileObject(_ file: NativeCryptoFile) -> [String: Any] {
        let cryptoArgs: Any
        if let args = file.cryptoArgs {
            cryptoArgs = ["fileKey": args.fileKey, "fileNonce": args.fileNonce]
        } else {
            cryptoArgs = NSNull()
        }
        return ["filePath": file.filePath, "cryptoArgs": cryptoArgs]
    }

    static func string(_ value: Any?) -> String? { value as? String }
    static func bool(_ value: Any?) -> Bool? { value as? Bool }
    static func int(_ value: Any?) -> Int? { (value as? NSNumber)?.intValue }
    static func int64(_ value: Any?) -> Int64? { (value as? NSNumber)?.int64Value }
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

    func updateProfile(userID: Int64, displayName: String, fullName: String, image: String?) throws -> NativeProfile {
        let profile: [String: Any] = [
            "displayName": displayName,
            "fullName": fullName,
            "image": image as Any,
        ]
        let data = try JSONSerialization.data(withJSONObject: profile)
        guard let json = String(data: data, encoding: .utf8) else {
            throw NativeChatError.invalidResponse("The profile could not be encoded.")
        }
        return try NativeChatParser.profile(from: sendCommand("/_profile \(userID) \(json)"))
    }

    func listLinkedDevices() throws -> [LinkedDevice] {
        try PeopleAndDevicesParser.linkedDevices(from: sendCommand("/list remote hosts", forceLocal: true))
    }

    func startRemotePairing() throws -> RemotePairing {
        try startRemoteHost(nil)
    }

    func startRemoteHost(_ id: Int64?) throws -> RemotePairing {
        return try PeopleAndDevicesParser.pairing(
            from: sendCommand(PeopleAndDevicesParser.startRemoteHostCommand(id), forceLocal: true)
        )
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

    func storeRemoteFile(
        remoteHostID: Int64,
        storeEncrypted: Bool?,
        localPath: String
    ) throws -> NativeCryptoFile {
        let encryption = storeEncrypted.map { "encrypt=\($0 ? "on" : "off") " } ?? ""
        return try PeopleAndDevicesParser.storedRemoteFile(from: sendCommand(
            "/store remote file \(remoteHostID) \(encryption)\(localPath)",
            forceLocal: true
        ))
    }

    func getRemoteFile(
        remoteHostID: Int64,
        userID: Int64,
        fileID: Int64,
        sent: Bool,
        fileSource: NativeCryptoFile
    ) throws {
        let json = try PeopleAndDevicesParser.remoteFileJSON(
            userID: userID,
            fileID: fileID,
            sent: sent,
            fileSource: fileSource
        )
        try NativeChatParser.validateCommandResponse(sendCommand(
            "/get remote file \(remoteHostID) \(json)",
            forceLocal: true
        ))
    }

    func hideUser(userID: Int64, viewPwd: String) throws -> NativeProfile {
        let json = try Self.jsonString(["viewPwd": viewPwd])
        let data = try sendCommand("/_hide user \(userID) \(json)")
        try NativeChatParser.validateCommandResponse(data, expectedType: "userPrivacy")
        return try NativeChatParser.profile(from: data)
    }

    func unhideUser(userID: Int64, viewPwd: String) throws -> NativeProfile {
        let json = try Self.jsonString(["viewPwd": viewPwd])
        let data = try sendCommand("/_unhide user \(userID) \(json)")
        try NativeChatParser.validateCommandResponse(data, expectedType: "userPrivacy")
        return try NativeChatParser.profile(from: data)
    }

    func switchToHiddenProfile(userID: Int64, viewPwd: String) throws -> NativeProfile {
        let json = try Self.jsonString(["viewPwd": viewPwd])
        let data = try sendCommand("/_user \(userID) \(json)")
        return try NativeChatParser.profile(from: data)
    }

    func getContactInfo(contactID: Int64) throws -> (connectionCode: String?, verified: Bool) {
        let data = try sendCommand("/_info @\(contactID)")
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any] else {
            return (nil, false)
        }
        let connection = result["connection"] as? [String: Any]
        let code = PeopleAndDevicesParser.string(connection?["connectionCode"])
        let verified = PeopleAndDevicesParser.bool(connection?["connectionVerified"]) ?? false
        return (code, verified)
    }

    func getContactInfoRaw(contactID: Int64) throws -> Data {
        try sendCommand("/_info @\(contactID)")
    }

    func verifyContact(contactID: Int64, code: String?) throws -> Bool {
        let codeArg = code.map { " \($0)" } ?? ""
        let data = try sendCommand("/_verify code @\(contactID)\(codeArg)")
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any] else {
            return false
        }
        return PeopleAndDevicesParser.bool(result["connectionVerified"]) ?? false
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

    func setUserDomain(userID: Int64, domain: String) throws {
        let json = try Self.jsonString(["simplexDomain": domain])
        try NativeChatParser.validateCommandResponse(sendCommand("/_set domain \(userID) \(json)"))
    }

    func getServersSummary(userID: Int64) throws -> ServersSummary {
        let data = try sendCommand("/_servers summary \(userID)")
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any] else {
            throw NativeChatError.invalidResponse("Could not parse servers summary.")
        }
        let smp = parseServerGroup(result["smpServers"])
        let xftp = parseServerGroup(result["xftpServers"])
        return ServersSummary(smpServers: smp, xftpServers: xftp)
    }

    private func parseServerGroup(_ value: Any?) -> [ServerSummary] {
        guard let group = value as? [String: Any],
              let servers = group["servers"] as? [[String: Any]] else { return [] }
        return servers.compactMap { obj in
            guard let server = PeopleAndDevicesParser.string(obj["server"]) else { return nil }
            let sessions = obj["sessions"] as? [String: Any]
            let subs = obj["subs"] as? [String: Any]
            let stats = obj["stats"] as? [String: Any]
            return ServerSummary(
                server: server,
                connected: PeopleAndDevicesParser.int(sessions?["ssConnected"]) ?? 0,
                errors: PeopleAndDevicesParser.int(sessions?["ssErrors"]) ?? 0,
                connecting: PeopleAndDevicesParser.int(sessions?["ssConnecting"]) ?? 0,
                activeSubs: PeopleAndDevicesParser.int(subs?["active"]) ?? 0,
                deletedSubs: PeopleAndDevicesParser.int(subs?["deleted"]) ?? 0,
                sentDirect: PeopleAndDevicesParser.int(stats?["sentDirect"]) ?? 0,
                sentViaProxy: PeopleAndDevicesParser.int(stats?["sentViaProxy"]) ?? 0,
                sentProxied: PeopleAndDevicesParser.int(stats?["sentProxied"]) ?? 0,
                recvDirect: PeopleAndDevicesParser.int(stats?["recvDirect"]) ?? 0,
                recvViaProxy: PeopleAndDevicesParser.int(stats?["recvViaProxy"]) ?? 0,
                recvProxied: PeopleAndDevicesParser.int(stats?["recvProxied"]) ?? 0
            )
        }
    }

    func reportMessage(groupID: Int64, itemID: Int64, reason: ReportReason) throws {
        let json = try Self.jsonString(["reason": reason.rawValue])
        try NativeChatParser.validateCommandResponse(sendCommand("/_report #\(groupID) \(itemID) \(json)"))
    }

    func deleteReceivedReports(groupID: Int64) throws {
        try NativeChatParser.validateCommandResponse(sendCommand("/_delete reports #\(groupID)"))
    }

    func getChatItemInfo(chatRef: String, itemID: Int64) throws -> ChatItemInfo {
        let data = try sendCommand("/_get item info \(chatRef) \(itemID)")
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let info = result["chatItemInfo"] as? [String: Any] else {
            throw NativeChatError.invalidResponse("Could not parse message info.")
        }
        let versions = (info["itemVersions"] as? [[String: Any]] ?? []).compactMap { obj -> ChatItemVersion? in
            guard let id = PeopleAndDevicesParser.int64(obj["chatItemVersionId"]),
                  let ts = PeopleAndDevicesParser.string(obj["itemVersionTs"]),
                  let created = PeopleAndDevicesParser.string(obj["createdAt"]) else { return nil }
            return ChatItemVersion(
                id: id,
                msgContent: obj["msgContent"] as? [String: Any] ?? [:],
                itemVersionTs: ts,
                createdAt: created
            )
        }
        let statuses = (info["memberDeliveryStatuses"] as? [[String: Any]])?.compactMap { obj -> MemberDeliveryStatus? in
            guard let memberId = PeopleAndDevicesParser.int64(obj["groupMemberId"]) else { return nil }
            let statusStr = PeopleAndDevicesParser.string(obj["memberDeliveryStatus"])
            return MemberDeliveryStatus(
                groupMemberId: memberId,
                memberDisplayName: PeopleAndDevicesParser.string(obj["memberDisplayName"]) ?? "Member \(memberId)",
                status: GroupSndStatus.from(statusStr),
                sentViaProxy: PeopleAndDevicesParser.bool(obj["sentViaProxy"])
            )
        }
        return ChatItemInfo(
            itemVersions: versions,
            memberDeliveryStatuses: statuses
        )
    }
}
