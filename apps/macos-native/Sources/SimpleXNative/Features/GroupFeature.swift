import Foundation

// MARK: - Models

struct GroupProfile: Hashable, Sendable {
    let displayName: String
    let fullName: String
    let description: String
    let image: String?
    var isPublic: Bool
}

struct GroupMember: Identifiable, Hashable, Sendable {
    let id: Int64
    let memberId: Int64
    let displayName: String
    let memberRole: GroupMemberRole
    let memberStatus: GroupMemberStatus
    let blocked: Bool
    let image: String?

    var isActive: Bool {
        memberStatus == .active || memberStatus == .creator
    }
}

enum GroupMemberRole: String, Hashable, Sendable {
    case observer
    case author
    case member
    case admin
    case owner

    var displayName: String {
        switch self {
        case .observer: "Observer"
        case .author: "Author"
        case .member: "Member"
        case .admin: "Admin"
        case .owner: "Owner"
        }
    }

    static let assignable: [GroupMemberRole] = [.observer, .author, .member, .admin]
}

enum GroupMemberStatus: String, Hashable, Sendable {
    case invited
    case introduced
    case connected
    case active
    case creator
    case removed
    case left
    case unknown

    var displayName: String {
        switch self {
        case .invited: "Invited"
        case .introduced: "Introduced"
        case .connected: "Connected"
        case .active: "Active"
        case .creator: "Creator"
        case .removed: "Removed"
        case .left: "Left"
        case .unknown: "Unknown"
        }
    }
}

struct GroupLink: Hashable, Sendable {
    let connLinkContact: String
    let shortLinkDataSet: Bool
    let memberRole: GroupMemberRole
}

// MARK: - SimpleXCore extensions

extension SimpleXCore {
    func createGroup(userID: Int64, profile: GroupProfile, incognito: Bool) throws -> NativeChat {
        let profileJSON = try Self.jsonString([
            "displayName": profile.displayName,
            "fullName": profile.fullName,
            "description": profile.description,
            "image": profile.image as Any,
            "isPublic": profile.isPublic,
        ])
        let mode = incognito ? "on" : "off"
        let data = try sendCommand("/_group \(userID) incognito=\(mode) \(profileJSON)")
        try NativeChatParser.validateCommandResponse(data, expectedType: "groupCreated")
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let groupInfo = result["groupInfo"] as? [String: Any],
              let groupId = PeopleAndDevicesParser.int64(groupInfo["groupId"]) else {
            throw NativeChatError.invalidResponse("The group was created but its details could not be decoded.")
        }
        return NativeChat(
            id: "#\(groupId)",
            apiID: groupId,
            kind: .group,
            displayName: profile.displayName,
            image: profile.image,
            preview: "",
            timestamp: Date(),
            unreadCount: 0,
            sendAsGroup: false,
            chatTagIds: []
        )
    }

    func updateGroupProfile(groupID: Int64, profile: GroupProfile) throws {
        let profileJSON = try Self.jsonString([
            "displayName": profile.displayName,
            "fullName": profile.fullName,
            "description": profile.description,
            "image": profile.image as Any,
            "isPublic": profile.isPublic,
        ])
        let data = try sendCommand("/_group_profile #\(groupID) \(profileJSON)")
        try NativeChatParser.validateCommandResponse(data, expectedType: "groupUpdated")
    }

    func getGroupMembers(groupID: Int64) throws -> [GroupMember] {
        let data = try sendCommand("/_members #\(groupID)")
        try NativeChatParser.validateCommandResponse(data, expectedType: "groupMembers")
        return try GroupFeatureParser.members(from: data)
    }

    func addGroupMember(groupID: Int64, contactID: Int64, role: GroupMemberRole) throws {
        let data = try sendCommand("/_add #\(groupID) \(contactID) \(role.rawValue)")
        try NativeChatParser.validateCommandResponse(data, expectedType: "sentGroupInvitation")
    }

    func removeGroupMembers(groupID: Int64, memberIDs: [Int64], messages: Bool) throws {
        let ids = memberIDs.map(String.init).joined(separator: ",")
        let mode = messages ? "on" : "off"
        let data = try sendCommand("/_remove #\(groupID) \(ids) messages=\(mode)")
        try NativeChatParser.validateCommandResponse(data, expectedType: "userDeletedMembers")
    }

    func changeMemberRole(groupID: Int64, memberIDs: [Int64], role: GroupMemberRole) throws {
        let ids = memberIDs.map(String.init).joined(separator: ",")
        let data = try sendCommand("/_member role #\(groupID) \(ids) \(role.rawValue)")
        try NativeChatParser.validateCommandResponse(data, expectedType: "membersRoleUser")
    }

    func blockGroupMembers(groupID: Int64, memberIDs: [Int64], blocked: Bool) throws {
        let ids = memberIDs.map(String.init).joined(separator: ",")
        let mode = blocked ? "on" : "off"
        let data = try sendCommand("/_block #\(groupID) \(ids) blocked=\(mode)")
        try NativeChatParser.validateCommandResponse(data, expectedType: "membersBlockedForAllUser")
    }

    func createGroupLink(groupID: Int64, role: GroupMemberRole) throws -> GroupLink {
        let data = try sendCommand("/_create link #\(groupID) \(role.rawValue)")
        try NativeChatParser.validateCommandResponse(data, expectedType: "groupLinkCreated")
        return try GroupFeatureParser.groupLink(from: data, role: role)
    }

    func getGroupLink(groupID: Int64) throws -> GroupLink? {
        let data = try sendCommand("/_get link #\(groupID)")
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              result["type"] as? String == "groupLink" else {
            return nil
        }
        return try GroupFeatureParser.groupLink(from: result)
    }

    func deleteGroupLink(groupID: Int64) throws {
        let data = try sendCommand("/_delete link #\(groupID)")
        try NativeChatParser.validateCommandResponse(data, expectedType: "groupLinkDeleted")
    }
}

// MARK: - Parser

enum GroupFeatureParser {
    static func members(from data: Data) throws -> [GroupMember] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let members = result["members"] as? [[String: Any]] else {
            throw NativeChatError.invalidResponse("The group member list was missing from the core response.")
        }
        return members.compactMap(parseMember)
    }

    static func groupLink(from data: Data, role: GroupMemberRole? = nil) throws -> GroupLink {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any] else {
            throw NativeChatError.invalidResponse("The group link was missing from the core response.")
        }
        return try groupLink(from: result, role: role)
    }

    static func groupLink(from result: [String: Any], role: GroupMemberRole? = nil) throws -> GroupLink {
        guard let connLink = result["connLinkContact"] as? [String: Any] else {
            throw NativeChatError.invalidResponse("The group link connection details were missing.")
        }
        let fullLink = PeopleAndDevicesParser.string(connLink["connFullLink"]) ?? ""
        let shortLinkDataSet = PeopleAndDevicesParser.bool(result["shortLinkDataSet"]) ?? false
        let resolvedRole = role
            ?? (result["memberRole"] as? String).flatMap(GroupMemberRole.init(rawValue:))
            ?? .member
        return GroupLink(
            connLinkContact: fullLink,
            shortLinkDataSet: shortLinkDataSet,
            memberRole: resolvedRole
        )
    }

    private static func parseMember(_ object: [String: Any]) -> GroupMember? {
        guard let memberId = PeopleAndDevicesParser.int64(object["memberId"]) else { return nil }
        let profile = object["memberProfile"] as? [String: Any]
        let displayName = PeopleAndDevicesParser.string(profile?["displayName"])
            ?? PeopleAndDevicesParser.string(object["localDisplayName"])
            ?? "Unknown"
        let role = (PeopleAndDevicesParser.string(object["memberRole"]) ?? "member")
        let status = (PeopleAndDevicesParser.string(object["memberStatus"]) ?? "unknown")
        let blocked = PeopleAndDevicesParser.bool(object["blockedByAdmin"]) ?? false
        return GroupMember(
            id: memberId,
            memberId: memberId,
            displayName: displayName,
            memberRole: GroupMemberRole(rawValue: role) ?? .member,
            memberStatus: GroupMemberStatus(rawValue: status) ?? .unknown,
            blocked: blocked,
            image: PeopleAndDevicesParser.string(profile?["image"])
        )
    }
}
