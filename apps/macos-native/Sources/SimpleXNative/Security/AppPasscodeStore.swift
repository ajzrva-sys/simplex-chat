import Foundation
import Security

protocol AppPasscodeStore: Sendable {
    func loadPasscode() async throws -> String?
    func savePasscode(_ passcode: String) async throws
    func deletePasscode() async throws
    func loadSelfDestructPasscode() async throws -> String?
    func saveSelfDestructPasscode(_ passcode: String) async throws
    func deleteSelfDestructPasscode() async throws
}

actor AppPasscodeKeychain: AppPasscodeStore {
    private let service: String
    private let passcodeAccount: String
    private let selfDestructAccount: String

    init(
        service: String = AppIdentity.keychainService,
        passcodeAccount: String = "app-passcode-v1",
        selfDestructAccount: String = "app-self-destruct-v1"
    ) {
        self.service = service
        self.passcodeAccount = passcodeAccount
        self.selfDestructAccount = selfDestructAccount
    }

    // MARK: - App Passcode

    func loadPasscode() async throws -> String? {
        try load(account: passcodeAccount)
    }

    func savePasscode(_ passcode: String) async throws {
        try save(passcode, account: passcodeAccount)
    }

    func deletePasscode() async throws {
        try delete(account: passcodeAccount)
    }

    // MARK: - Self-Destruct Passcode

    func loadSelfDestructPasscode() async throws -> String? {
        try load(account: selfDestructAccount)
    }

    func saveSelfDestructPasscode(_ passcode: String) async throws {
        try save(passcode, account: selfDestructAccount)
    }

    func deleteSelfDestructPasscode() async throws {
        try delete(account: selfDestructAccount)
    }

    // MARK: - Private Keychain Operations

    private func load(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let passcode = String(data: data, encoding: .utf8) else {
                throw AppPasscodeKeychainError.unexpectedData
            }
            return passcode
        case errSecItemNotFound:
            return nil
        case errSecInteractionNotAllowed:
            throw AppPasscodeKeychainError.interactionNotAllowed
        default:
            throw AppPasscodeKeychainError.unhandledStatus(status)
        }
    }

    private func save(_ passcode: String, account: String) throws {
        let data = Data(passcode.utf8)
        let query = baseQuery(account: account)
        var addQuery = query
        addQuery[kSecValueData] = data
        addQuery[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let updates: [CFString: Any] = [kSecValueData: data]
            let updateStatus = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
            switch updateStatus {
            case errSecSuccess:
                return
            case errSecInteractionNotAllowed:
                throw AppPasscodeKeychainError.interactionNotAllowed
            default:
                throw AppPasscodeKeychainError.unhandledStatus(updateStatus)
            }
        case errSecInteractionNotAllowed:
            throw AppPasscodeKeychainError.interactionNotAllowed
        default:
            throw AppPasscodeKeychainError.unhandledStatus(addStatus)
        }
    }

    private func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        case errSecInteractionNotAllowed:
            throw AppPasscodeKeychainError.interactionNotAllowed
        default:
            throw AppPasscodeKeychainError.unhandledStatus(status)
        }
    }

    private func baseQuery(account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecUseDataProtectionKeychain: true,
        ]
    }
}

enum AppPasscodeKeychainError: LocalizedError, Equatable, Sendable {
    case interactionNotAllowed
    case unexpectedData
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .interactionNotAllowed:
            "The Mac Keychain is locked. Unlock your Mac and try again."
        case .unexpectedData:
            "The saved app passcode could not be read."
        case let .unhandledStatus(status):
            SecCopyErrorMessageString(status, nil) as String?
                ?? "The Mac Keychain returned error \(status)."
        }
    }
}
