import AppKit
import Foundation

enum DeviceMigrationMode: String, Identifiable, Sendable {
    case importFromPhone
    case exportToPhone

    var id: Self { self }
}

enum DeviceMigrationPhase: Equatable {
    case scanOrPaste
    case confirmExport
    case preparingImport
    case downloading(bytes: Int64, total: Int64?)
    case readyToReplace
    case replacingDatabase
    case enterPassphrase(error: String?)
    case openingDatabase
    case importComplete
    case preparingExport
    case uploading(bytes: Int64, total: Int64?)
    case exportReady(link: String)
    case exportComplete
    case resumingChat
    case failed(message: String)

    var preventsDismissal: Bool {
        switch self {
        case .scanOrPaste, .confirmExport, .importComplete, .failed:
            false
        case .preparingImport, .downloading, .readyToReplace, .replacingDatabase,
             .enterPassphrase, .openingDatabase, .preparingExport, .uploading,
             .exportReady, .exportComplete, .resumingChat:
            true
        }
    }
}

enum DeviceMigrationTransferEvent: Equatable, Sendable {
    case sendProgress(bytes: Int64, total: Int64, fileID: Int64)
    case sendComplete(fileID: Int64, link: String)
    case receiveProgress(bytes: Int64, total: Int64, fileID: Int64)
    case receiveComplete(fileID: Int64)
    case failed(String)
    case ignored
}

struct DeviceMigrationTransferParser {
    static func uploadStarted(_ data: Data) throws -> (fileID: Int64, total: Int64?) {
        let result = try responseResult(data, expectedType: "sndStandaloneFileCreated")
        let metadata = try dictionary(result["fileTransferMeta"], named: "file transfer")
        guard let fileID = int64(metadata["fileId"]) else {
            throw NativeChatError.invalidResponse("The upload response did not include a file identifier.")
        }
        return (fileID, int64(metadata["fileSize"]))
    }

    static func downloadStarted(_ data: Data) throws -> Int64 {
        let result = try responseResult(data, expectedType: "rcvStandaloneFileCreated")
        let transfer = try dictionary(result["rcvFileTransfer"], named: "file transfer")
        guard let fileID = int64(transfer["fileId"]) else {
            throw NativeChatError.invalidResponse("The download response did not include a file identifier.")
        }
        return fileID
    }

    static func event(_ data: Data) -> DeviceMigrationTransferEvent {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failed("SimpleX returned an invalid transfer event.")
        }
        if let error = root["error"] {
            return .failed("The transfer failed: \(briefDescription(error))")
        }
        guard let result = root["result"] as? [String: Any],
              let type = result["type"] as? String else { return .ignored }

        switch type {
        case "sndFileProgressXFTP":
            guard let bytes = int64(result["sentSize"]),
                  let total = int64(result["totalSize"]),
                  let metadata = result["fileTransferMeta"] as? [String: Any],
                  let fileID = int64(metadata["fileId"]) else { return .ignored }
            return .sendProgress(bytes: bytes, total: total, fileID: fileID)
        case "sndStandaloneFileComplete":
            guard let metadata = result["fileTransferMeta"] as? [String: Any],
                  let fileID = int64(metadata["fileId"]),
                  let link = (result["rcvURIs"] as? [String])?.first else { return .ignored }
            return .sendComplete(fileID: fileID, link: link)
        case "rcvFileProgressXFTP":
            guard let bytes = int64(result["receivedSize"]),
                  let total = int64(result["totalSize"]),
                  let transfer = result["rcvFileTransfer"] as? [String: Any],
                  let fileID = int64(transfer["fileId"]) else { return .ignored }
            return .receiveProgress(bytes: bytes, total: total, fileID: fileID)
        case "rcvStandaloneFileComplete":
            guard let transfer = result["rcvFileTransfer"] as? [String: Any],
                  let fileID = int64(transfer["fileId"]) else { return .ignored }
            return .receiveComplete(fileID: fileID)
        case "sndFileError":
            return .failed(result["errorMessage"] as? String ?? "The archive upload failed.")
        case "rcvFileError":
            return .failed("The archive is no longer available or its link is invalid.")
        default:
            return .ignored
        }
    }

    static func isFileLink(_ value: String) -> Bool {
        let link = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return link.hasPrefix("simplex:/file") || link.hasPrefix("https://simplex.chat/file")
    }

    static func uploadCommand(userID: Int64, fileName: String) -> String {
        "/_upload \(userID) \(fileName)"
    }

    static func downloadCommand(userID: Int64, link: String, fileName: String) -> String {
        "/_download \(userID) \(link) \(fileName)"
    }

    private static func responseResult(_ data: Data, expectedType: String) throws -> [String: Any] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeChatError.invalidResponse("SimpleX returned invalid transfer JSON.")
        }
        if let error = root["error"] {
            throw NativeChatError.core("The transfer could not start: \(briefDescription(error))")
        }
        guard let result = root["result"] as? [String: Any],
              result["type"] as? String == expectedType else {
            throw NativeChatError.invalidResponse("SimpleX did not start the requested transfer.")
        }
        return result
    }

    private static func dictionary(_ value: Any?, named name: String) throws -> [String: Any] {
        guard let value = value as? [String: Any] else {
            throw NativeChatError.invalidResponse("The \(name) details were missing.")
        }
        return value
    }

    private static func int64(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        if let value = value as? String { return Int64(value) }
        return nil
    }

    private static func briefDescription(_ value: Any) -> String {
        if let object = value as? [String: Any] {
            if let type = object["type"] as? String { return type }
            for nested in object.values {
                let description = briefDescription(nested)
                if description != "unknown error" { return description }
            }
        }
        if let string = value as? String { return string }
        return "unknown error"
    }
}

@MainActor
final class DeviceMigrationCoordinator: ObservableObject {
    @Published private(set) var phase: DeviceMigrationPhase = .scanOrPaste
    @Published private(set) var mode: DeviceMigrationMode = .importFromPhone

    private let core: SimpleXCore
    private let passphraseStore: any DatabasePassphraseStore
    private let canStorePassphrase: Bool
    private let pauseMainEvents: @MainActor () -> Void
    private let resumeMainEvents: @MainActor () -> Void
    private let applyImportedProfile: @MainActor (NativeProfile, [NativeChat], Bool) async -> Void
    private var operation: Task<Void, Never>?
    private var archiveURL: URL?
    private var transferFileID: Int64?
    private var mainChatStopped = false
    private var mainEventsPaused = false

    init(
        core: SimpleXCore,
        passphraseStore: any DatabasePassphraseStore,
        canStorePassphrase: Bool,
        pauseMainEvents: @escaping @MainActor () -> Void,
        resumeMainEvents: @escaping @MainActor () -> Void,
        applyImportedProfile: @escaping @MainActor (NativeProfile, [NativeChat], Bool) async -> Void
    ) {
        self.core = core
        self.passphraseStore = passphraseStore
        self.canStorePassphrase = canStorePassphrase
        self.pauseMainEvents = pauseMainEvents
        self.resumeMainEvents = resumeMainEvents
        self.applyImportedProfile = applyImportedProfile
    }

    deinit {
        operation?.cancel()
    }

    var dismissalDisabled: Bool { phase.preventsDismissal }
    var keychainStorageAvailable: Bool { canStorePassphrase }

    func present(_ mode: DeviceMigrationMode) {
        guard operation == nil else { return }
        self.mode = mode
        phase = mode == .importFromPhone ? .scanOrPaste : .confirmExport
    }

    func startImport(link rawLink: String) {
        let link = rawLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard DeviceMigrationTransferParser.isFileLink(link) else {
            phase = .failed(message: "That QR code is not a SimpleX archive link.")
            return
        }
        runOperation { [weak self] in
            guard let self else { return }
            phase = .preparingImport
            let network = try await core.networkConfigurationJSON()
            let archive = try await core.prepareMigrationArchiveURL()
            archiveURL = archive
            let userID = try await core.startMigrationController(networkConfigurationJSON: network)
            let response = try await core.sendMigrationCommand(
                DeviceMigrationTransferParser.downloadCommand(
                    userID: userID,
                    link: link,
                    fileName: archive.lastPathComponent
                )
            )
            transferFileID = try DeviceMigrationTransferParser.downloadStarted(response)
            phase = .downloading(bytes: 0, total: nil)
            try await receiveDownloadEvents()
        }
    }

    func replaceDatabase() {
        guard let archiveURL else { return }
        runOperation { [weak self] in
            guard let self else { return }
            phase = .replacingDatabase
            pauseEventsIfNeeded()
            try await core.stopMainChatForMigration()
            mainChatStopped = true
            try await core.installMigrationArchive(at: archiveURL)
            transferFileID = nil
            phase = .enterPassphrase(error: nil)
        }
    }

    func openImportedDatabase(passphrase: String, remember: Bool) {
        guard !passphrase.isEmpty else {
            phase = .enterPassphrase(error: "Enter the database passphrase used on your phone.")
            return
        }
        runOperation { [weak self] in
            guard let self else { return }
            phase = .openingDatabase
            do {
                let (profile, chats) = try await core.resetAndOpen(passphrase: passphrase)
                let shouldRemember = remember && canStorePassphrase
                var rememberedPassphrase = false
                if shouldRemember {
                    do {
                        try await passphraseStore.save(passphrase)
                        rememberedPassphrase = true
                    } catch {
                        // The imported database is already open. A locked Keychain should not
                        // turn a successful migration into a failed migration.
                    }
                } else if canStorePassphrase {
                    try? await passphraseStore.delete()
                }
                mainChatStopped = false
                mainEventsPaused = false
                await applyImportedProfile(profile, chats, rememberedPassphrase)
                await core.cleanUpMigrationFiles()
                phase = .importComplete
            } catch {
                phase = .enterPassphrase(error: error.localizedDescription)
            }
        }
    }

    func startExport() {
        runOperation { [weak self] in
            guard let self else { return }
            phase = .preparingExport
            let network = try await core.networkConfigurationJSON()
            let archive = try await core.prepareMigrationArchiveURL()
            archiveURL = archive
            pauseEventsIfNeeded()
            try await core.stopMainChatForMigration()
            mainChatStopped = true
            try await core.exportDatabase(to: archive.path)
            let total = try Self.fileSize(archive)
            let userID = try await core.startMigrationController(networkConfigurationJSON: network)
            let response = try await core.sendMigrationCommand(
                DeviceMigrationTransferParser.uploadCommand(
                    userID: userID,
                    fileName: archive.lastPathComponent
                )
            )
            let started = try DeviceMigrationTransferParser.uploadStarted(response)
            transferFileID = started.fileID
            phase = .uploading(bytes: 0, total: started.total ?? total)
            try await receiveUploadEvents()
        }
    }

    func finalizeExport() {
        runOperation { [weak self] in
            guard let self else { return }
            if let transferFileID {
                _ = try? await core.sendMigrationCommand("/fcancel \(transferFileID)")
            }
            transferFileID = nil
            await core.cleanUpMigrationFiles()
            phase = .exportComplete
        }
    }

    func resumeChatOnMac() {
        runOperation { [weak self] in
            guard let self else { return }
            phase = .resumingChat
            try await core.resumeMainChatAfterMigration()
            mainChatStopped = false
            resumeEventsIfNeeded()
            phase = .confirmExport
        }
    }

    func cancel() async {
        operation?.cancel()
        operation = nil
        if let transferFileID {
            _ = try? await core.sendMigrationCommand("/fcancel \(transferFileID)")
        }
        transferFileID = nil
        await core.cleanUpMigrationFiles()
        archiveURL = nil
        if mainChatStopped {
            do {
                try await core.resumeMainChatAfterMigration()
                mainChatStopped = false
            } catch {
                phase = .failed(message: error.localizedDescription)
                return
            }
        }
        resumeEventsIfNeeded()
        phase = mode == .importFromPhone ? .scanOrPaste : .confirmExport
    }

    func resetFailure() {
        phase = mode == .importFromPhone ? .scanOrPaste : .confirmExport
    }

    private func receiveDownloadEvents() async throws {
        while !Task.isCancelled {
            guard let data = await core.receiveMigrationEvent() else { continue }
            switch DeviceMigrationTransferParser.event(data) {
            case let .receiveProgress(bytes, total, fileID):
                transferFileID = fileID
                phase = .downloading(bytes: bytes, total: total)
            case .receiveComplete:
                await core.closeMigrationController()
                transferFileID = nil
                phase = .readyToReplace
                return
            case let .failed(message):
                throw NativeChatError.core(message)
            case .sendProgress, .sendComplete, .ignored:
                continue
            }
        }
        throw CancellationError()
    }

    private func receiveUploadEvents() async throws {
        while !Task.isCancelled {
            guard let data = await core.receiveMigrationEvent() else { continue }
            switch DeviceMigrationTransferParser.event(data) {
            case let .sendProgress(bytes, total, fileID):
                transferFileID = fileID
                phase = .uploading(bytes: bytes, total: total)
            case let .sendComplete(fileID, link):
                transferFileID = fileID
                phase = .exportReady(link: link)
                return
            case let .failed(message):
                throw NativeChatError.core(message)
            case .receiveProgress, .receiveComplete, .ignored:
                continue
            }
        }
        throw CancellationError()
    }

    private func runOperation(_ body: @escaping @MainActor () async throws -> Void) {
        guard operation == nil else { return }
        operation = Task { [weak self] in
            guard let self else { return }
            defer { operation = nil }
            do {
                try await body()
            } catch is CancellationError {
                return
            } catch {
                if mainChatStopped {
                    do {
                        try await core.resumeMainChatAfterMigration()
                        mainChatStopped = false
                    } catch {
                        phase = .failed(message: "\(error.localizedDescription)\n\nThe chat could not be restarted automatically.")
                        return
                    }
                }
                resumeEventsIfNeeded()
                await core.cleanUpMigrationFiles()
                phase = .failed(message: error.localizedDescription)
            }
        }
    }

    private func pauseEventsIfNeeded() {
        guard !mainEventsPaused else { return }
        mainEventsPaused = true
        pauseMainEvents()
    }

    private func resumeEventsIfNeeded() {
        guard mainEventsPaused else { return }
        mainEventsPaused = false
        resumeMainEvents()
    }

    private static func fileSize(_ url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize else {
            throw NativeChatError.unavailable("The exported archive could not be read.")
        }
        return Int64(size)
    }
}

extension SimpleXCore {
    func prepareMigrationArchiveURL() throws -> URL {
        cleanUpMigrationFiles()
        try FileManager.default.createDirectory(
            at: migrationFilesDirectory,
            withIntermediateDirectories: true
        )
        return migrationFilesDirectory
            .appendingPathComponent("simplex-chat-\(UUID().uuidString).zip")
    }

    func stopMainChatForMigration() throws {
        try NativeChatParser.validateCommandResponse(
            sendCommand("/_stop", forceLocal: true),
            expectedType: "chatStopped"
        )
    }

    func resumeMainChatAfterMigration() throws {
        try NativeChatParser.validateCommandResponse(
            sendCommand("/_start main=on snd_files=on", forceLocal: true)
        )
    }

    func installMigrationArchive(at archiveURL: URL) throws {
        try importDatabase(from: archiveURL.path)
        discardMainControllerAfterMigration()
    }
}
