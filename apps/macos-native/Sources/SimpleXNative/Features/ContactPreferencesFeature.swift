import Foundation

enum FeatureAllowed: String, Sendable, CaseIterable {
    case yes
    case no
    case always

    var label: String {
        switch self {
        case .yes: "Yes"
        case .no: "No"
        case .always: "Always"
        }
    }
}

enum ChatFeature: String, Sendable, CaseIterable {
    case timedMessages
    case fullDelete
    case reactions
    case voice
    case files
    case calls

    var label: String {
        switch self {
        case .timedMessages: "Disappearing messages"
        case .fullDelete: "Full deletion"
        case .reactions: "Reactions"
        case .voice: "Voice messages"
        case .files: "Files & media"
        case .calls: "Audio/video calls"
        }
    }

    var icon: String {
        switch self {
        case .timedMessages: "timer"
        case .fullDelete: "trash"
        case .reactions: "face.smiling"
        case .voice: "mic"
        case .files: "doc"
        case .calls: "phone"
        }
    }
}

struct SimpleChatPreference: Sendable {
    let allow: FeatureAllowed
}

struct TimedMessagesChatPreference: Sendable {
    let allow: FeatureAllowed
    let ttl: Int?
}

struct FeatureEnabled: Sendable {
    let forUser: Bool
    let forContact: Bool
}

enum ContactUserPref: Sendable {
    case user(SimpleChatPreference)
    case contact(SimpleChatPreference)
}

struct ContactUserPreference: Sendable {
    let enabled: FeatureEnabled
    let userPreference: ContactUserPref
    let contactPreference: SimpleChatPreference
}

struct ContactUserPreferenceTimed: Sendable {
    let enabled: FeatureEnabled
    let userPreference: ContactUserPref
    let contactPreference: TimedMessagesChatPreference
}

struct ContactUserPreferences: Sendable {
    let timedMessages: ContactUserPreferenceTimed
    let fullDelete: ContactUserPreference
    let reactions: ContactUserPreference
    let voice: ContactUserPreference
    let files: ContactUserPreference
    let calls: ContactUserPreference
}

enum ContactFeatureAllowed: Sendable, Hashable {
    case userDefault(FeatureAllowed)
    case always
    case yes
    case no

    var label: String {
        switch self {
        case .userDefault(let def): "Default (\(def.label))"
        case .always: "Always"
        case .yes: "Yes"
        case .no: "No"
        }
    }

    var allOptions: [ContactFeatureAllowed] {
        [.userDefault(.yes), .userDefault(.no), .userDefault(.always), .always, .yes, .no]
    }
}

struct ContactFeaturesAllowed: Sendable {
    var timedMessagesAllowed: Bool
    var timedMessagesTTL: Int?
    var fullDelete: ContactFeatureAllowed
    var reactions: ContactFeatureAllowed
    var voice: ContactFeatureAllowed
    var files: ContactFeatureAllowed
    var calls: ContactFeatureAllowed
}

enum ContactPreferencesParser {
    static func parsePreferences(from data: Data) throws -> ContactUserPreferences {
        let result = try NativeChatParser.validateCommandResponse(data, expectedType: "contactPrefsUpdated")
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let toContact = result["toContact"] as? [String: Any],
              let merged = toContact["mergedPreferences"] as? [String: Any] else {
            throw NativeChatError.invalidResponse("Could not parse contact preferences.")
        }
        return try parseMergedPreferences(merged)
    }

    static func parseMergedPreferences(_ merged: [String: Any]) throws -> ContactUserPreferences {
        ContactUserPreferences(
            timedMessages: parseTimedPref(merged["timedMessages"]),
            fullDelete: parsePref(merged["fullDelete"]),
            reactions: parsePref(merged["reactions"]),
            voice: parsePref(merged["voice"]),
            files: parsePref(merged["files"]),
            calls: parsePref(merged["calls"])
        )
    }

    static func parsePreferencesFromContact(_ contact: [String: Any]) -> ContactUserPreferences? {
        guard let merged = contact["mergedPreferences"] as? [String: Any] else { return nil }
        return try? parseMergedPreferences(merged)
    }

    private static func parsePref(_ value: Any?) -> ContactUserPreference {
        guard let obj = value as? [String: Any] else {
            return ContactUserPreference(
                enabled: FeatureEnabled(forUser: false, forContact: false),
                userPreference: .user(SimpleChatPreference(allow: .no)),
                contactPreference: SimpleChatPreference(allow: .no)
            )
        }
        let enabled = parseEnabled(obj["enabled"])
        let userPref = parseUserPref(obj["userPreference"], allow: string((obj["userPreference"] as? [String: Any])?["allow"]))
        let contactAllow = parseAllow((obj["contactPreference"] as? [String: Any])?["allow"])
        return ContactUserPreference(
            enabled: enabled,
            userPreference: userPref,
            contactPreference: SimpleChatPreference(allow: contactAllow)
        )
    }

    private static func parseTimedPref(_ value: Any?) -> ContactUserPreferenceTimed {
        guard let obj = value as? [String: Any] else {
            return ContactUserPreferenceTimed(
                enabled: FeatureEnabled(forUser: false, forContact: false),
                userPreference: .user(SimpleChatPreference(allow: .no)),
                contactPreference: TimedMessagesChatPreference(allow: .no, ttl: nil)
            )
        }
        let enabled = parseEnabled(obj["enabled"])
        let userPref = parseUserPref(obj["userPreference"], allow: nil)
        let contactObj = obj["contactPreference"] as? [String: Any]
        let contactAllow = parseAllow(contactObj?["allow"])
        let contactTTL = int(contactObj?["ttl"])
        return ContactUserPreferenceTimed(
            enabled: enabled,
            userPreference: userPref,
            contactPreference: TimedMessagesChatPreference(allow: contactAllow, ttl: contactTTL)
        )
    }

    private static func parseEnabled(_ value: Any?) -> FeatureEnabled {
        guard let obj = value as? [String: Any] else {
            return FeatureEnabled(forUser: false, forContact: false)
        }
        return FeatureEnabled(
            forUser: bool(obj["forUser"]) ?? false,
            forContact: bool(obj["forContact"]) ?? false
        )
    }

    private static func parseUserPref(_ value: Any?, allow: String?) -> ContactUserPref {
        guard let obj = value as? [String: Any] else {
            return .user(SimpleChatPreference(allow: parseAllow(allow)))
        }
        let type = string(obj["type"])
        let prefAllow = parseAllow((obj["preference"] as? [String: Any])?["allow"])
        let pref = SimpleChatPreference(allow: prefAllow)
        if type == "contact" {
            return .contact(pref)
        }
        return .user(pref)
    }

    private static func parseAllow(_ value: Any?) -> FeatureAllowed {
        guard let str = value as? String else { return .no }
        return FeatureAllowed(rawValue: str) ?? .no
    }

    static func contactUserPrefsToFeaturesAllowed(_ prefs: ContactUserPreferences) -> ContactFeaturesAllowed {
        ContactFeaturesAllowed(
            timedMessagesAllowed: prefs.timedMessages.enabled.forUser && prefs.timedMessages.enabled.forContact,
            timedMessagesTTL: prefs.timedMessages.contactPreference.ttl,
            fullDelete: userPrefToFeatureAllowed(prefs.fullDelete.userPreference, globalAllow: prefs.fullDelete.enabled),
            reactions: userPrefToFeatureAllowed(prefs.reactions.userPreference, globalAllow: prefs.reactions.enabled),
            voice: userPrefToFeatureAllowed(prefs.voice.userPreference, globalAllow: prefs.voice.enabled),
            files: userPrefToFeatureAllowed(prefs.files.userPreference, globalAllow: prefs.files.enabled),
            calls: userPrefToFeatureAllowed(prefs.calls.userPreference, globalAllow: prefs.calls.enabled)
        )
    }

    private static func userPrefToFeatureAllowed(_ pref: ContactUserPref, globalAllow: FeatureEnabled) -> ContactFeatureAllowed {
        switch pref {
        case .user(let p): .userDefault(p.allow)
        case .contact(let p):
            switch p.allow {
            case .yes: .yes
            case .no: .no
            case .always: .always
            }
        }
    }

    static func featuresAllowedToPrefsJSON(_ allowed: ContactFeaturesAllowed) throws -> String {
        var prefs: [String: Any] = [:]
        prefs["timedMessages"] = timedMessagesJSON(allowed)
        prefs["fullDelete"] = featurePrefJSON(allowed.fullDelete)
        prefs["reactions"] = featurePrefJSON(allowed.reactions)
        prefs["voice"] = featurePrefJSON(allowed.voice)
        prefs["files"] = featurePrefJSON(allowed.files)
        prefs["calls"] = featurePrefJSON(allowed.calls)
        return try SimpleXCore.jsonString(prefs)
    }

    private static func timedMessagesJSON(_ allowed: ContactFeaturesAllowed) -> [String: Any] {
        if allowed.timedMessagesAllowed {
            var pref: [String: Any] = ["allow": "always"]
            if let ttl = allowed.timedMessagesTTL {
                pref["ttl"] = ttl
            }
            return pref
        }
        return ["allow": "no"]
    }

    private static func featurePrefJSON(_ allowed: ContactFeatureAllowed) -> [String: Any]? {
        switch allowed {
        case .userDefault: nil
        case .yes: ["allow": "yes"]
        case .no: ["allow": "no"]
        case .always: ["allow": "always"]
        }
    }

    private static func string(_ value: Any?) -> String? { value as? String }
    private static func bool(_ value: Any?) -> Bool? { value as? Bool }
    private static func int(_ value: Any?) -> Int? {
        if let v = value as? Int { return v }
        if let v = value as? NSNumber { return v.intValue }
        return nil
    }
}

extension SimpleXCore {
    func apiSetContactPrefs(contactID: Int64, preferences: String) throws -> Data {
        try sendCommand("/_set prefs @\(contactID) \(preferences)")
    }
}
