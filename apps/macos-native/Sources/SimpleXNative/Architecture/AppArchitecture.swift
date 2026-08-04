import Foundation
import Observation

enum AppIdentity {
    static let displayName = "Native Chat"
    static let compatibilityName = "SimpleX"
    static let temporaryBundleIdentifier = "io.github.ajzrva.nativechat"
    static let keychainService = "io.github.ajzrva.nativechat.database"
    static let legacyKeychainService = "chat.simplex.native.database"
    static let keychainAccount = "database-passphrase-v1"
}

struct UserContext: Hashable, Sendable {
    let userID: Int64
    let remoteHostID: Int64?
}

enum AppRoute: Hashable, Sendable {
    case chat(UserContext, chatID: String, messageID: Int64?)
    case contacts(UserContext)
    case profile(Int64)
    case linkedDevices
    case settings(SettingsSection)
    case call(UUID)
}

enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case general
    case privacy
    case notifications
    case network
    case servers
    case database

    var id: Self { self }
}

enum RemoteHostState: Hashable, Sendable {
    case local
    case starting
    case connecting(invitation: String)
    case pendingConfirmation(code: String)
    case confirmed(code: String)
    case connected(code: String?)
    case stopped(reason: String?)
}

struct PagedChatItems: Equatable, Sendable {
    var items: [NativeMessage]
    var hasOlderItems: Bool
    var oldestItemID: Int64? { items.first?.id }

    mutating func prepend(_ olderItems: [NativeMessage], requestedCount: Int) {
        let existing = Set(items.map(\.id))
        items.insert(contentsOf: olderItems.filter { !existing.contains($0.id) }, at: 0)
        hasOlderItems = olderItems.count >= requestedCount
    }
}

enum TransferState: Hashable, Sendable {
    case queued
    case transferring(bytesTransferred: Int64, totalBytes: Int64?)
    case paused(bytesTransferred: Int64, totalBytes: Int64?)
    case complete(URL?)
    case failed(String)
    case cancelled

    var fractionCompleted: Double? {
        let values: (Int64, Int64?)?
        switch self {
        case let .transferring(done, total), let .paused(done, total): values = (done, total)
        default: values = nil
        }
        guard let (done, total) = values, let total, total > 0 else { return nil }
        return min(max(Double(done) / Double(total), 0), 1)
    }

    var bytesTransferred: Int64? {
        switch self {
        case let .transferring(bytesTransferred, _), let .paused(bytesTransferred, _):
            bytesTransferred
        case .complete:
            nil
        case .queued, .failed, .cancelled:
            nil
        }
    }

    var totalBytes: Int64? {
        switch self {
        case let .transferring(_, totalBytes), let .paused(_, totalBytes):
            totalBytes
        case .queued, .complete, .failed, .cancelled:
            nil
        }
    }
}

struct CallSession: Identifiable, Equatable, Sendable {
    enum Direction: Sendable { case incoming, outgoing }
    enum Media: Sendable { case audio, video }
    enum State: Sendable { case ringing, connecting, active, ended, failed }

    let id: UUID
    let context: UserContext
    let contactID: Int64
    var displayName: String
    var direction: Direction
    var media: Media
    var state: State
    var microphoneMuted = false
    var cameraEnabled = true
}

struct SettingsSnapshot: Equatable, Sendable {
    var showLinkPreviews = true
    var sanitizeLinks = true
    var autoAcceptImages = true
    var showChatPreviews = true
    var saveDrafts = true
    var encryptLocalFiles = true
    var protectIPAddress = true
    var showEncryptionIndicators = false
    var deliveryReceiptsContacts = true
    var deliveryReceiptsGroups = false
    var notificationPreviewMode: NotificationPreviewMode = .message
    var notificationSounds = true
    var messageRetentionDays: Int?
}

@MainActor
@Observable
final class AppRouter {
    var presentedRoute: AppRoute?
    private(set) var pendingRoutes: [AppRoute] = []

    func route(to route: AppRoute, ready: Bool) {
        if ready {
            presentedRoute = route
        } else if !pendingRoutes.contains(route) {
            pendingRoutes.append(route)
        }
    }

    func consumePendingRoutes() -> [AppRoute] {
        defer { pendingRoutes.removeAll() }
        return pendingRoutes
    }
}

protocol ProfileRepository: Sendable {
    func profiles(remoteHostID: Int64?) async throws -> [NativeProfile]
    func switchProfile(userID: Int64, remoteHostID: Int64?) async throws -> NativeProfile
}

protocol ContactRepository: Sendable {
    func connect(using link: String, context: UserContext) async throws
    func acceptRequest(_ requestID: Int64, incognito: Bool, context: UserContext) async throws
    func rejectRequest(_ requestID: Int64, context: UserContext) async throws
}

protocol ChatRepository: Sendable {
    func chats(context: UserContext) async throws -> [NativeChat]
    func messages(chatID: String, before itemID: Int64?, count: Int, context: UserContext) async throws -> [NativeMessage]
}

protocol FileTransferRepository: Sendable {
    func receive(fileID: Int64, context: UserContext) async throws
    func cancel(fileID: Int64, context: UserContext) async throws
    func retry(fileID: Int64, context: UserContext) async throws
}

protocol CallRepository: Sendable {
    func start(contactID: Int64, media: CallSession.Media, context: UserContext) async throws -> CallSession
    func end(_ session: CallSession) async throws
}

protocol SettingsRepository: Sendable {
    func load(context: UserContext) async throws -> SettingsSnapshot
    func save(_ settings: SettingsSnapshot, context: UserContext) async throws
}
