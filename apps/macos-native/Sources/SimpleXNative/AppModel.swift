import AppKit
import Foundation

typealias DeleteMessagesOperation = @Sendable ([Int64], NativeChat) async throws -> [NativeMessage]
typealias SendTextOperation = @Sendable (String, Int64?, NativeChat) async throws -> NativeSendReceipt
typealias SendAttachmentOperation = @Sendable (PendingAttachment, String, Int64?, NativeChat) async throws -> NativeSendReceipt
typealias LoadMessageOperation = @Sendable (NativeChat.ID, Int64) async throws -> NativeMessage?
typealias LoadMessagesOperation = @Sendable (NativeChat.ID, Int64?) async throws -> [NativeMessage]
typealias LoadChatsOperation = @Sendable (Int64) async throws -> [NativeChat]
typealias MarkChatReadOperation = @Sendable (NativeChat.ID) async throws -> Void
typealias ReceiveFileOperation = @Sendable (Int64) async throws -> Void
typealias OpenAttachmentOperation = @Sendable (NativeCryptoFile, String?) async throws -> Void
typealias PrepareAttachmentOperation = @Sendable (NativeCryptoFile, String?) async throws -> URL
typealias WindowFocusedOperation = @MainActor @Sendable () -> Bool

@MainActor
final class AppModel: ObservableObject {
    let voiceRecorder = VoiceRecordingController()
    let fileTransfers: FileTransferViewModel
    enum Phase: Equatable {
        case locked(message: String?)
        case opening
        case ready
        case failed(String)
    }

    private struct ConversationComposerState {
        var draft = ""
        var attachments: [PendingAttachment] = []
        var reply: NativeMessage?

        var isEmpty: Bool {
            draft.isEmpty && attachments.isEmpty && reply == nil
        }
    }

    private struct AttachmentOpeningKey: Hashable {
        let userID: Int64?
        let remoteHostID: Int64?
        let chatID: NativeChat.ID
        let messageID: Int64
    }

    @Published var phase: Phase = .locked(message: nil)
    @Published var profile: NativeProfile?
    @Published private(set) var currentRemoteHostID: Int64?
    @Published var chats: [NativeChat] = []
    @Published var selectedChatID: NativeChat.ID?
    @Published var messages: [NativeMessage] = []
    @Published var draft = ""
    @Published var searchText = ""
    @Published var sidebarSearchPresented = false
    @Published var featureCenterPresented = false
    @Published private(set) var managedProfiles: [ManagedProfile] = []
    @Published private(set) var linkedDevices: [LinkedDevice] = []
    @Published private(set) var remotePairing: RemotePairing?
    @Published var featureError: String?
    @Published private(set) var isLoadingFeatures = false
    @Published var conversationSearchText = ""
    @Published var conversationSearchPresented = false
    @Published var isLoadingConversation = false
    @Published private(set) var isLoadingOlderMessages = false
    @Published private(set) var hasOlderMessages = true
    @Published private(set) var isRefreshing = false
    @Published var isSending = false
    @Published private(set) var sendingChatID: NativeChat.ID?
    @Published private(set) var isDeletingMessages = false
    @Published var selectedMessageIDs: Set<Int64> = []
    @Published var transcriptFocused = false
    @Published var pendingAttachments: [PendingAttachment] = []
    @Published var attachmentError: String?
    @Published var attachmentOpenError: String?
    @Published var quickLookURL: URL?
    @Published var quoteNavigationError: String?
    @Published var replyContextError: String?
    @Published var sendStatusMessage: String?
    @Published private var openingAttachmentKeys: Set<AttachmentOpeningKey> = []
    @Published private var inlineAudioURLs: [AttachmentOpeningKey: URL] = [:]
    @Published private var inlineImageURLs: [AttachmentOpeningKey: URL] = [:]
    @Published var replyingTo: NativeMessage?
    @Published var editingMessage: NativeMessage?
    @Published var forwardingPresented = false
    @Published var chatDetailsPresented = false
    @Published private(set) var isPerformingMessageAction = false
    @Published var settingsSnapshot = NativeSettingsPersistence.load()
    @Published var networkConfigurationText = "{}"
    @Published var serverConfigurationText = "[]"
    @Published var settingsError: String?
    @Published private(set) var isSavingSettings = false
    @Published var composerFocusRequest = 0
    @Published var showingDeleteConfirmation = false
    @Published var targetMessageID: Int64?
    @Published var hasStoredPassphrase = false
    @Published var keychainStatusMessage: String?
    @Published private(set) var keychainPassphraseStorageAvailable: Bool
    @Published var density: DesktopChatDensity {
        didSet { UserDefaults.standard.set(density.rawValue, forKey: Self.densityKey) }
    }

    private let core: SimpleXCore
    private let previewMode: Bool
    private let passphraseStore: any DatabasePassphraseStore
    private let deleteMessagesOperation: DeleteMessagesOperation?
    private let sendTextOperation: SendTextOperation?
    private let sendAttachmentOperation: SendAttachmentOperation?
    private let loadMessageOperation: LoadMessageOperation?
    private let loadMessagesOperation: LoadMessagesOperation?
    private let loadChatsOperation: LoadChatsOperation?
    private let markChatReadOperation: MarkChatReadOperation?
    private let receiveFileOperation: ReceiveFileOperation?
    private let openAttachmentOperation: OpenAttachmentOperation?
    private let prepareAttachmentOperation: PrepareAttachmentOperation?
    private let windowFocusedOperation: WindowFocusedOperation?
    private weak var notificationManager: NativeNotificationManager?
    private var eventTask: Task<Void, Never>?
    private var notificationContextTask: Task<Void, Never>?
    private var featureTask: Task<Void, Never>?
    private var messageActionTask: Task<Void, Never>?
    private var settingsTask: Task<Void, Never>?
    private var conversationLoadTask: Task<Void, Never>?
    private var olderHistoryTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private(set) var sendTask: Task<Void, Never>?
    private var deleteTask: Task<Void, Never>?
    private(set) var quoteNavigationTask: Task<Void, Never>?
    private var replyTargetNavigationTask: Task<Void, Never>?
    private var notificationRouteQueue = NotificationRouteQueue()
    private var pendingChatOperationErrors: [NativeChat.ID: String] = [:]
    private var presentedChatOperationErrorChatID: NativeChat.ID?
    private var pendingQuoteNavigationErrors: [NativeChat.ID: String] = [:]
    private var pendingReplyContextErrors: [NativeChat.ID: String] = [:]
    private var pendingSendStatusMessages: [NativeChat.ID: String] = [:]
    private var pendingAttachmentOpenErrors: [NativeChat.ID: String] = [:]
    private var pendingReplyInvalidationChatIDs: Set<NativeChat.ID> = []
    private var markingReadChatIDs: Set<NativeChat.ID> = []
    private var composerStates: [NativeChat.ID: ConversationComposerState] = [:]
    private var quickLookRequestKey: AttachmentOpeningKey?
    private var automaticAttachmentTasks: [AttachmentOpeningKey: Task<Void, Never>] = [:]
    private var requestedFileIDs: Set<Int64> = []
    private var deletingChatID: NativeChat.ID?
    private var deletingMessageIDs: Set<Int64> = []
    private var selectionAnchor: Int64?
    private var replyingChatID: NativeChat.ID?
    private var conversationLoadRevision: UInt64 = 0
    @Published private(set) var conversationAnchorMessageID: Int64?
    private var quoteNavigationRevision: UInt64 = 0
    private static let densityKey = "desktopChatDensity"

    private func attachmentKey(chatID: NativeChat.ID, messageID: Int64) -> AttachmentOpeningKey {
        AttachmentOpeningKey(
            userID: profile?.userID,
            remoteHostID: currentRemoteHostID,
            chatID: chatID,
            messageID: messageID
        )
    }

    init(
        notificationManager: NativeNotificationManager? = nil,
        passphraseStore: any DatabasePassphraseStore = MigratingDatabasePassphraseStore(),
        previewMode: Bool? = nil,
        deleteMessagesOperation: DeleteMessagesOperation? = nil,
        sendTextOperation: SendTextOperation? = nil,
        sendAttachmentOperation: SendAttachmentOperation? = nil,
        loadMessageOperation: LoadMessageOperation? = nil,
        loadMessagesOperation: LoadMessagesOperation? = nil,
        loadChatsOperation: LoadChatsOperation? = nil,
        markChatReadOperation: MarkChatReadOperation? = nil,
        receiveFileOperation: ReceiveFileOperation? = nil,
        openAttachmentOperation: OpenAttachmentOperation? = nil,
        prepareAttachmentOperation: PrepareAttachmentOperation? = nil,
        fileTransferRepository: (any FileTransferRepository)? = nil,
        windowFocusedOperation: WindowFocusedOperation? = nil
    ) {
        let core = SimpleXCore()
        self.core = core
        fileTransfers = FileTransferViewModel(
            repository: fileTransferRepository ?? SimpleXFileTransferRepository(core: core)
        )
        self.previewMode = previewMode
            ?? (ProcessInfo.processInfo.environment["SIMPLEX_NATIVE_UI_PREVIEW"] == "1")
        self.passphraseStore = passphraseStore
        self.deleteMessagesOperation = deleteMessagesOperation
        self.sendTextOperation = sendTextOperation
        self.sendAttachmentOperation = sendAttachmentOperation
        self.loadMessageOperation = loadMessageOperation
        self.loadMessagesOperation = loadMessagesOperation
        self.loadChatsOperation = loadChatsOperation
        self.markChatReadOperation = markChatReadOperation
        self.receiveFileOperation = receiveFileOperation
        self.openAttachmentOperation = openAttachmentOperation
        self.prepareAttachmentOperation = prepareAttachmentOperation
        self.windowFocusedOperation = windowFocusedOperation
        keychainPassphraseStorageAvailable = Bundle.main.object(
            forInfoDictionaryKey: "NativeChatKeychainPassphraseStorageEnabled"
        ) as? Bool == true
        density = DesktopChatDensity(
            rawValue: UserDefaults.standard.string(forKey: Self.densityKey) ?? ""
        ) ?? .compact
        self.notificationManager = notificationManager
        notificationManager?.model = self
        if self.previewMode {
            phase = .ready
            profile = NativePreviewData.profile
            chats = NativePreviewData.chats
            selectedChatID = NativePreviewData.chats.first?.id
            messages = selectedChatID.map(NativePreviewData.messages) ?? []
        } else if keychainPassphraseStorageAvailable {
            Task { await attemptAutomaticUnlock() }
        }
    }

    deinit {
        eventTask?.cancel()
        notificationContextTask?.cancel()
        featureTask?.cancel()
        messageActionTask?.cancel()
        settingsTask?.cancel()
        conversationLoadTask?.cancel()
        olderHistoryTask?.cancel()
        refreshTask?.cancel()
        sendTask?.cancel()
        deleteTask?.cancel()
        for task in automaticAttachmentTasks.values { task.cancel() }
        quoteNavigationTask?.cancel()
        replyTargetNavigationTask?.cancel()
    }

    var selectedChat: NativeChat? {
        chats.first { $0.id == selectedChatID }
    }

    var filteredChats: [NativeChat] {
        guard !searchText.isEmpty else { return chats }
        return chats.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
                || $0.preview.localizedCaseInsensitiveContains(searchText)
        }
    }

    var canSendDraft: Bool {
        let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasText || !pendingAttachments.isEmpty)
            && !isSending
            && !isDeletingSelectedChat
            && !isRefreshing
            && !isLoadingConversation
            && quoteNavigationTask == nil
            && selectedChat?.kind.canSend == true
    }

    var isSendingSelectedChat: Bool {
        isSending && sendingChatID == selectedChatID
    }

    var isDeletingSelectedChat: Bool {
        isDeletingMessages && deletingChatID == selectedChatID
    }

    var canNavigateConversationHistory: Bool {
        !isSendingSelectedChat && !isDeletingSelectedChat && !isRefreshing
    }

    var canRefreshConversation: Bool {
        canNavigateConversationHistory && !isLoadingConversation && quoteNavigationTask == nil
    }

    var isViewingConversationHistory: Bool {
        conversationAnchorMessageID != nil
    }

    var selectedMessagesInTranscriptOrder: [NativeMessage] {
        messages.filter { selectedMessageIDs.contains($0.id) }
    }

    var canDeleteSelectedMessages: Bool {
        let inFlightQuoteID = isSendingSelectedChat ? replyingTo?.id : nil
        let includesInFlightQuote = inFlightQuoteID.map(selectedMessageIDs.contains) ?? false
        return !isDeletingMessages
            && !isSendingSelectedChat
            && !isRefreshing
            && !isLoadingConversation
            && quoteNavigationTask == nil
            && !selectedMessageIDs.isEmpty
            && selectedMessagesInTranscriptOrder.allSatisfy(\.deletable)
            && !includesInFlightQuote
    }

    var canReplyToSelectedMessage: Bool {
        guard selectedMessagesInTranscriptOrder.count == 1,
              let message = selectedMessagesInTranscriptOrder.first else { return false }
        return canReply(to: message)
    }

    var canDismissNearestState: Bool {
        conversationSearchPresented
            || sidebarSearchPresented
            || (replyingTo != nil && !isSendingSelectedChat)
            || (!pendingAttachments.isEmpty && !isSendingSelectedChat)
            || !selectedMessageIDs.isEmpty
    }

    var conversationSearchMatches: [NativeMessage] {
        ConversationSearch.matches(messages, query: conversationSearchText)
    }

    var conversationSearchResultDescription: String {
        let matches = conversationSearchMatches
        let selectedID = selectedMessagesInTranscriptOrder.last?.id
        return ConversationSearch.resultDescription(
            matches: matches,
            selectedID: selectedID,
            queryIsEmpty: conversationSearchText.isEmpty
        )
    }

    func unlock(passphrase: String, rememberPassphrase: Bool = true) {
        guard phase != .opening else { return }
        phase = .opening
        Task {
            await openProfile(
                passphrase: passphrase,
                rememberPassphrase: rememberPassphrase && keychainPassphraseStorageAvailable,
                automatic: false
            )
        }
    }

    func forgetSavedPassphrase() {
        guard keychainPassphraseStorageAvailable else { return }
        Task {
            do {
                try await passphraseStore.delete()
                hasStoredPassphrase = false
                keychainStatusMessage = "The saved passphrase was removed from Mac Keychain."
            } catch {
                keychainStatusMessage = error.localizedDescription
            }
        }
    }

    @discardableResult
    func selectChat(_ id: NativeChat.ID?) -> Task<Void, Never>? {
        transitionToChat(id)
    }

    func refresh() {
        guard !previewMode else { return }
        guard canRefreshConversation else { return }
        guard let userID = profile?.userID else { return }
        let refreshChatID = selectedChatID
        refreshTask?.cancel()
        isRefreshing = true
        refreshTask = Task {
            defer {
                isRefreshing = false
                refreshTask = nil
                consumePendingNotificationRoutes()
            }
            do {
                let loadedChats = try await loadChats(userID: userID)
                guard !Task.isCancelled else { return }
                chats = loadedChats
                if let chatID = selectedChatID {
                    conversationLoadTask?.cancel()
                    _ = await loadConversation(chatID: chatID)
                }
            } catch is CancellationError {
                return
            } catch {
                if let refreshChatID {
                    presentChatOperationFailure(error.localizedDescription, in: refreshChatID)
                } else {
                    presentGlobalFailure(error.localizedDescription)
                }
            }
        }
    }

    func reloadPeopleAndDevices() {
        guard !previewMode, canOpenNotificationRoutes, !isLoadingFeatures else { return }
        isLoadingFeatures = true
        featureTask?.cancel()
        featureTask = Task { [weak self] in
            guard let self else { return }
            defer {
                isLoadingFeatures = false
                featureTask = nil
            }
            do {
                async let profiles = core.listProfiles()
                async let devices = core.listLinkedDevices()
                managedProfiles = try await profiles
                linkedDevices = try await devices
            } catch {
                featureError = error.localizedDescription
            }
        }
    }

    func activateProfile(_ managedProfile: ManagedProfile) {
        guard !previewMode, !managedProfile.active else { return }
        runFeatureOperation { [weak self] in
            guard let self else { return }
            resetMediaContext()
            let selected = try await core.switchProfile(userID: managedProfile.id)
            let loadedChats = try await core.loadChats(userID: selected.userID)
            profile = selected
            chats = loadedChats
            _ = transitionToChat(loadedChats.first?.id)
            reloadPeopleAndDevices()
        }
    }

    func createProfile(displayName: String, fullName: String) {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            featureError = "Enter a display name for the new profile."
            return
        }
        runFeatureOperation { [weak self] in
            guard let self else { return }
            resetMediaContext()
            let created = try await core.createProfile(displayName: name, fullName: fullName)
            profile = created
            chats = try await core.loadChats(userID: created.userID)
            _ = transitionToChat(chats.first?.id)
            reloadPeopleAndDevices()
        }
    }

    func connectContact(link: String, incognito: Bool) {
        let value = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let userID = profile?.userID, !value.isEmpty else {
            featureError = "Paste a contact or group link first."
            return
        }
        runFeatureOperation { [weak self] in
            guard let self else { return }
            try await core.connectContact(userID: userID, link: value, incognito: incognito)
            chats = try await core.loadChats(userID: userID)
        }
    }

    func respondToContactRequest(_ chat: NativeChat, accept: Bool, incognito: Bool) {
        guard chat.kind == .contactRequest, let userID = profile?.userID else { return }
        runFeatureOperation { [weak self] in
            guard let self else { return }
            if accept {
                try await core.acceptContactRequest(chat.apiID, incognito: incognito)
            } else {
                try await core.rejectContactRequest(chat.apiID)
            }
            chats = try await core.loadChats(userID: userID)
            if selectedChatID == chat.id { _ = transitionToChat(chats.first?.id) }
        }
    }

    func beginRemotePairing() {
        runFeatureOperation { [weak self] in
            guard let self else { return }
            remotePairing = try await core.startRemotePairing()
            linkedDevices = try await core.listLinkedDevices()
        }
    }

    func useRemoteHost(_ id: Int64?) {
        runFeatureOperation { [weak self] in
            guard let self else { return }
            resetMediaContext()
            try await core.switchRemoteHost(id)
            currentRemoteHostID = id
            let profiles = try await core.listProfiles()
            managedProfiles = profiles
            guard let active = profiles.first(where: \.active) ?? profiles.first else {
                profile = nil
                chats = []
                _ = transitionToChat(nil)
                return
            }
            profile = try await core.switchProfile(userID: active.id)
            chats = try await core.loadChats(userID: active.id)
            _ = transitionToChat(chats.first?.id)
        }
    }

    func removeRemoteHost(_ device: LinkedDevice) {
        runFeatureOperation { [weak self] in
            guard let self else { return }
            if currentRemoteHostID == device.id {
                resetMediaContext()
                try await core.switchRemoteHost(nil)
                currentRemoteHostID = nil
            }
            try await core.stopRemoteHost(device.id)
            try await core.deleteRemoteHost(device.id)
            linkedDevices = try await core.listLinkedDevices()
        }
    }

    private func runFeatureOperation(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !previewMode, !isLoadingFeatures else { return }
        isLoadingFeatures = true
        featureError = nil
        featureTask?.cancel()
        featureTask = Task { [weak self] in
            guard let self else { return }
            defer {
                isLoadingFeatures = false
                featureTask = nil
            }
            do {
                try await operation()
            } catch is CancellationError {
                return
            } catch {
                featureError = error.localizedDescription
            }
        }
    }

    func loadAdvancedSettings() {
        guard !previewMode, let userID = profile?.userID, !isSavingSettings else { return }
        runSettingsOperation { [weak self] in
            guard let self else { return }
            async let network = core.networkConfigurationJSON()
            async let servers = core.serverConfigurationJSON(userID: userID)
            networkConfigurationText = try await network
            serverConfigurationText = try await servers
        }
    }

    func savePrivacySettings() {
        guard let userID = profile?.userID else { return }
        let snapshot = settingsSnapshot
        NativeSettingsPersistence.save(snapshot)
        if snapshot.autoAcceptImages, let chatID = selectedChatID {
            startAutomaticImageDownloads(messages, in: chatID)
        }
        runSettingsOperation { [weak self] in
            guard let self else { return }
            try await core.setEncryptLocalFiles(snapshot.encryptLocalFiles)
            try await core.setDeliveryReceipts(
                userID: userID,
                contacts: snapshot.deliveryReceiptsContacts,
                groups: snapshot.deliveryReceiptsGroups
            )
            try await core.setMessageRetention(userID: userID, days: snapshot.messageRetentionDays)
        }
    }

    func saveNetworkSettings() {
        let json = networkConfigurationText
        runSettingsOperation { [weak self] in
            guard let self else { return }
            try await core.saveNetworkConfiguration(json: json)
            networkConfigurationText = try await core.networkConfigurationJSON()
        }
    }

    func saveServerSettings() {
        guard let userID = profile?.userID else { return }
        let json = serverConfigurationText
        runSettingsOperation { [weak self] in
            guard let self else { return }
            try await core.saveServerConfiguration(userID: userID, json: json)
            serverConfigurationText = try await core.serverConfigurationJSON(userID: userID)
        }
    }

    func reconnectServers() {
        runSettingsOperation { [weak self] in
            guard let self else { return }
            try await core.reconnectServers()
        }
    }

    func exportDatabase() {
        let panel = NSSavePanel()
        panel.title = "Export Encrypted Chat Database"
        panel.nameFieldStringValue = "NativeChat-Backup.zip"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        runSettingsOperation { [weak self] in
            guard let self else { return }
            try await core.exportDatabase(to: url.path)
        }
    }

    func importDatabase() {
        let panel = NSOpenPanel()
        panel.title = "Import Chat Database"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        runSettingsOperation { [weak self] in
            guard let self else { return }
            try await core.importDatabase(from: url.path)
            presentGlobalFailure("Database imported. Restart Native Chat before continuing.")
        }
    }

    func changeDatabasePassphrase(current: String, new: String, remember: Bool) {
        guard !current.isEmpty else {
            settingsError = "Enter the current database passphrase."
            return
        }
        runSettingsOperation { [weak self] in
            guard let self else { return }
            try await core.changeDatabasePassphrase(current: current, new: new)
            if remember {
                try await passphraseStore.save(new)
                hasStoredPassphrase = true
            } else {
                try await passphraseStore.delete()
                hasStoredPassphrase = false
            }
        }
    }

    func openDatabaseFolder() {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/simplex", isDirectory: true)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    private func runSettingsOperation(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !previewMode, !isSavingSettings else { return }
        isSavingSettings = true
        settingsError = nil
        settingsTask?.cancel()
        settingsTask = Task { [weak self] in
            guard let self else { return }
            defer {
                isSavingSettings = false
                settingsTask = nil
            }
            do {
                try await operation()
            } catch is CancellationError {
                return
            } catch {
                settingsError = error.localizedDescription
            }
        }
    }

    func loadOlderMessages() {
        guard !previewMode, !isLoadingOlderMessages, hasOlderMessages,
              canNavigateConversationHistory,
              let chatID = selectedChatID,
              conversationAnchorMessageID == nil,
              let oldestID = messages.first?.id else { return }
        isLoadingOlderMessages = true
        olderHistoryTask?.cancel()
        olderHistoryTask = Task { [weak self] in
            guard let self else { return }
            defer {
                isLoadingOlderMessages = false
                olderHistoryTask = nil
            }
            do {
                let older = try await core.loadOlderMessages(chatID: chatID, before: oldestID, count: 100)
                try Task.checkCancellation()
                guard selectedChatID == chatID, conversationAnchorMessageID == nil else { return }
                let existingIDs = Set(messages.map(\.id))
                let unique = older.filter { !existingIDs.contains($0.id) }
                messages.insert(contentsOf: unique, at: 0)
                startAutomaticImageDownloads(unique, in: chatID)
                hasOlderMessages = older.count >= 100
                targetMessageID = oldestID
            } catch is CancellationError {
                return
            } catch {
                guard selectedChatID == chatID else { return }
                presentChatOperationFailure(error.localizedDescription, in: chatID)
            }
        }
    }

    @discardableResult
    func jumpToLatest() -> Task<Void, Never>? {
        guard canNavigateConversationHistory,
              let chatID = selectedChatID, isViewingConversationHistory else { return nil }
        quoteNavigationTask?.cancel()
        quoteNavigationTask = nil
        quoteNavigationRevision &+= 1
        quoteNavigationError = nil
        return scheduleConversationLoad(chatID: chatID, scrollToLatest: true)
    }

    func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if let editingMessage {
            commitEdit(editingMessage, text: text)
            return
        }
        let attachments = pendingAttachments
        guard (!text.isEmpty || !attachments.isEmpty), let chat = selectedChat,
              canSendDraft else { return }
        let quotedMessage = replyingChatID == chat.id ? replyingTo : nil
        if replyingTo != nil, quotedMessage == nil { cancelReply() }
        if previewMode, sendTextOperation == nil, sendAttachmentOperation == nil {
            if !text.isEmpty {
                let nextID = (messages.map(\.id).max() ?? 0) + 1
                messages.append(NativeMessage(
                    id: nextID,
                    text: text,
                    timestamp: Date(),
                    sent: true,
                    author: nil,
                    deletable: true,
                    content: .text,
                    quotedItem: quotedMessage.map {
                        NativeQuote(
                            messageID: $0.id,
                            text: $0.replyPreview,
                            sent: $0.sent,
                            author: $0.author,
                            visual: $0.content.replyContextVisual
                        )
                    }
                ))
            }
            draft = ""
            pendingAttachments = []
            cancelReply()
            return
        }
        draft = ""
        sendingChatID = chat.id
        isSending = true
        let core = core
        let sendTextOperation = sendTextOperation
        let sendAttachmentOperation = sendAttachmentOperation
        let loadMessageOperation = loadMessageOperation
        let loadMessagesOperation = loadMessagesOperation
        let loadChatsOperation = loadChatsOperation
        sendTask = Task { [weak self] in
            var draftWasSent = false
            var quoteCommitResolved = false
            defer {
                self?.finishSending(
                    in: chat.id,
                    quotedMessageID: quotedMessage?.id,
                    quoteCommitResolved: quoteCommitResolved
                )
            }
            do {
                if let quotedMessage {
                    let refreshedReply: NativeMessage?
                    if let loadMessageOperation {
                        refreshedReply = try await loadMessageOperation(chat.id, quotedMessage.id)
                    } else if self?.previewMode == true {
                        refreshedReply = quotedMessage
                    } else {
                        refreshedReply = try await core.loadMessage(chatID: chat.id, itemID: quotedMessage.id)
                    }
                    try Task.checkCancellation()
                    guard refreshedReply?.replyable == true else {
                        self?.restoreFailedDraft(text, in: chat.id)
                        self?.invalidateReplyContext(in: chat.id)
                        return
                    }
                }
                if attachments.isEmpty {
                    try Task.checkCancellation()
                    let receipt: NativeSendReceipt
                    if let sendTextOperation {
                        receipt = try await sendTextOperation(text, quotedMessage?.id, chat)
                    } else {
                        receipt = try await core.sendText(text, quotedItemID: quotedMessage?.id, to: chat)
                    }
                    draftWasSent = true
                    self?.applyCommittedMessages(
                        receipt.committedMessages,
                        in: chat.id,
                        announcement: "Message sent"
                    )
                    if let quotedItemID = quotedMessage?.id {
                        quoteCommitResolved = true
                        self?.clearReply(quotedItemID, in: chat.id)
                        if !receipt.replyContextConfirmed {
                            self?.reportUnconfirmedReplyContext(in: chat.id)
                        }
                    }
                    try Task.checkCancellation()
                } else {
                    let sendSteps = PendingAttachmentBatch.sendSteps(
                        attachments: attachments,
                        caption: text,
                        quotedItemID: quotedMessage?.id
                    )
                    for (index, step) in sendSteps.enumerated() {
                        try Task.checkCancellation()
                        let receipt: NativeSendReceipt
                        if let sendAttachmentOperation {
                            receipt = try await sendAttachmentOperation(
                                step.attachment,
                                step.caption,
                                step.quotedItemID,
                                chat
                            )
                        } else {
                            receipt = try await core.sendAttachment(
                                step.attachment,
                                caption: step.caption,
                                quotedItemID: step.quotedItemID,
                                to: chat
                            )
                        }
                        if index == sendSteps.index(before: sendSteps.endIndex) { draftWasSent = true }
                        self?.applyCommittedMessages(
                            receipt.committedMessages,
                            in: chat.id,
                            announcement: "Attachment \(index + 1) of \(sendSteps.count) sent"
                        )
                        self?.removeSentAttachment(step.attachment.id, from: chat.id)
                        if let quotedItemID = step.quotedItemID {
                            quoteCommitResolved = true
                            self?.clearReply(quotedItemID, in: chat.id)
                            if !receipt.replyContextConfirmed {
                                self?.reportUnconfirmedReplyContext(in: chat.id)
                            }
                        }
                        try Task.checkCancellation()
                    }
                }
                let sentMessages: [NativeMessage]
                if let loadMessagesOperation {
                    sentMessages = try await loadMessagesOperation(chat.id, nil)
                } else {
                    sentMessages = try await core.loadMessages(chatID: chat.id)
                }
                try Task.checkCancellation()
                if self?.selectedChatID == chat.id {
                    self?.conversationAnchorMessageID = nil
                    self?.messages = sentMessages
                }
                if let userID = self?.profile?.userID {
                    let loadedChats: [NativeChat]
                    if let loadChatsOperation {
                        loadedChats = try await loadChatsOperation(userID)
                    } else {
                        loadedChats = try await core.loadChats(userID: userID)
                    }
                    try Task.checkCancellation()
                    self?.chats = loadedChats
                }
            } catch is CancellationError {
                if !draftWasSent { self?.restoreFailedDraft(text, in: chat.id) }
                return
            } catch NativeChatError.replyTargetUnavailable {
                if !draftWasSent { self?.restoreFailedDraft(text, in: chat.id) }
                self?.invalidateReplyContext(in: chat.id)
            } catch {
                if draftWasSent {
                    self?.finishPostSendRefreshFailure(error.localizedDescription, in: chat.id)
                } else {
                    self?.restoreFailedDraft(text, in: chat.id)
                    self?.finishSendFailure(error.localizedDescription, in: chat.id)
                }
            }
        }
    }

    var canEditSelectedMessage: Bool {
        guard selectedMessageIDs.count == 1,
              let message = selectedMessagesInTranscriptOrder.first else { return false }
        if case .text = message.content { return message.sent && message.deletable }
        return false
    }

    func beginEditingSelectedMessage() {
        guard canEditSelectedMessage, let message = selectedMessagesInTranscriptOrder.first else { return }
        cancelReply()
        editingMessage = message
        draft = message.text
        clearMessageSelection()
        composerFocusRequest &+= 1
    }

    func cancelEditing() {
        guard editingMessage != nil, !isSendingSelectedChat else { return }
        editingMessage = nil
        draft = ""
    }

    private func commitEdit(_ message: NativeMessage, text: String) {
        guard !text.isEmpty, let chat = selectedChat, !isPerformingMessageAction else { return }
        let chatID = chat.id
        isPerformingMessageAction = true
        isSending = true
        sendingChatID = chatID
        messageActionTask?.cancel()
        messageActionTask = Task { [weak self] in
            guard let self else { return }
            defer {
                isPerformingMessageAction = false
                isSending = false
                sendingChatID = nil
                messageActionTask = nil
            }
            do {
                try await core.editMessage(message.id, text: text, in: chat)
                let refreshed = try await core.loadMessages(chatID: chatID)
                guard selectedChatID == chatID else { return }
                messages = refreshed
                editingMessage = nil
                draft = ""
                targetMessageID = message.id
            } catch {
                presentChatOperationFailure(error.localizedDescription, in: chatID)
            }
        }
    }

    func toggleReaction(_ emoji: String, on message: NativeMessage) {
        guard let chat = selectedChat, !isPerformingMessageAction else { return }
        let existing = message.reactions.first { $0.emoji == emoji }
        let shouldAdd = existing?.userReacted != true
        let original = message.reactions
        var updated = original.filter { $0.emoji != emoji }
        let newCount = max(0, (existing?.count ?? 0) + (shouldAdd ? 1 : -1))
        if newCount > 0 { updated.append(NativeReaction(emoji: emoji, count: newCount, userReacted: shouldAdd)) }
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message.replacingReactions(updated)
        }
        isPerformingMessageAction = true
        messageActionTask = Task { [weak self] in
            guard let self else { return }
            defer {
                isPerformingMessageAction = false
                messageActionTask = nil
            }
            do {
                try await core.setReaction(emoji, add: shouldAdd, messageID: message.id, in: chat)
                let refreshed = try await core.loadMessages(chatID: chat.id)
                if selectedChatID == chat.id { messages = refreshed }
            } catch {
                if selectedChatID == chat.id,
                   let index = messages.firstIndex(where: { $0.id == message.id }) {
                    messages[index] = message.replacingReactions(original)
                }
                presentChatOperationFailure(error.localizedDescription, in: chat.id)
            }
        }
    }

    func forwardSelectedMessages(to destination: NativeChat) {
        guard let source = selectedChat, source.id != destination.id,
              !selectedMessageIDs.isEmpty, !isPerformingMessageAction else { return }
        let ids = selectedMessagesInTranscriptOrder.map(\.id)
        forwardingPresented = false
        isPerformingMessageAction = true
        messageActionTask = Task { [weak self] in
            guard let self else { return }
            defer {
                isPerformingMessageAction = false
                messageActionTask = nil
            }
            do {
                try await core.forwardMessages(ids, from: source, to: destination)
                clearMessageSelection()
                sendStatusMessage = "Forwarded \(ids.count) message\(ids.count == 1 ? "" : "s") to \(destination.displayName)."
            } catch {
                presentChatOperationFailure(error.localizedDescription, in: source.id)
            }
        }
    }

    func clearSelectedChat() {
        guard let chat = selectedChat else { return }
        runChatManagementOperation(chat: chat) { core, chat in try await core.clearChat(chat) }
    }

    func deleteSelectedChat() {
        guard let chat = selectedChat else { return }
        runChatManagementOperation(chat: chat) { core, chat in try await core.deleteChat(chat, notify: false) }
    }

    func leaveSelectedGroup() {
        guard let chat = selectedChat, chat.kind == .group else { return }
        runChatManagementOperation(chat: chat) { core, chat in try await core.leaveGroup(chat) }
    }

    private func runChatManagementOperation(
        chat: NativeChat,
        operation: @escaping @Sendable (SimpleXCore, NativeChat) async throws -> Void
    ) {
        guard !isPerformingMessageAction, let userID = profile?.userID else { return }
        isPerformingMessageAction = true
        messageActionTask = Task { [weak self] in
            guard let self else { return }
            defer {
                isPerformingMessageAction = false
                messageActionTask = nil
            }
            do {
                try await operation(core, chat)
                chats = try await core.loadChats(userID: userID)
                if let refreshed = chats.first(where: { $0.id == chat.id }) {
                    _ = transitionToChat(refreshed.id)
                    _ = await loadConversation(chatID: refreshed.id)
                } else {
                    _ = transitionToChat(chats.first?.id)
                }
                chatDetailsPresented = false
            } catch {
                presentChatOperationFailure(error.localizedDescription, in: chat.id)
            }
        }
    }

    func chooseAttachments() {
        guard !isSendingSelectedChat else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.data]
        panel.prompt = "Attach"
        panel.message = "Choose images, videos, or documents to send."
        guard panel.runModal() == .OK else { return }
        stageAttachments(panel.urls)
    }

    func stageAttachments(_ urls: [URL]) {
        guard !isSendingSelectedChat else {
            attachmentError = "Wait for the current message to finish sending before changing attachments."
            return
        }
        var failures: [String] = []
        for url in urls {
            do {
                let attachment = try PendingAttachment.stage(url: url)
                if !pendingAttachments.contains(where: { $0.url == attachment.url }) {
                    pendingAttachments.append(attachment)
                }
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        if !failures.isEmpty { attachmentError = failures.joined(separator: "\n") }
    }

    func stageVoiceRecording(url: URL, duration: TimeInterval) {
        guard !isSendingSelectedChat else { return }
        do {
            pendingAttachments.append(try PendingAttachment.voiceRecording(
                url: url,
                durationSeconds: Int(duration.rounded())
            ))
            voiceRecorder.consumeReview()
        } catch {
            attachmentError = error.localizedDescription
        }
    }

    func stageFilesFromPasteboard() {
        guard !isSendingSelectedChat else {
            attachmentError = "Wait for the current message to finish sending before changing attachments."
            return
        }
        let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        if urls.isEmpty {
            attachmentError = "The clipboard does not contain any files."
        } else {
            stageAttachments(urls)
        }
    }

    func removeAttachment(_ id: PendingAttachment.ID) {
        guard !isSendingSelectedChat else { return }
        pendingAttachments.removeAll { $0.id == id }
    }

    func reorderAttachment(_ source: PendingAttachment.ID, before destination: PendingAttachment.ID) {
        guard !isSendingSelectedChat else { return }
        pendingAttachments = PendingAttachment.reordered(pendingAttachments, from: source, before: destination)
    }

    func moveAttachment(_ id: PendingAttachment.ID, by offset: Int) {
        guard !isSendingSelectedChat else { return }
        guard let sourceIndex = pendingAttachments.firstIndex(where: { $0.id == id }) else { return }
        let destinationIndex = min(max(0, sourceIndex + offset), pendingAttachments.count - 1)
        guard sourceIndex != destinationIndex else { return }
        let attachment = pendingAttachments.remove(at: sourceIndex)
        pendingAttachments.insert(attachment, at: destinationIndex)
    }

    func beginReply(to message: NativeMessage) {
        guard let chat = selectedChat, canReply(to: message),
              let currentMessage = messages.first(where: { $0.id == message.id }),
              currentMessage.replyable else { return }
        cancelStaleNavigationForReply()
        replyingTo = currentMessage
        replyingChatID = chat.id
        if conversationSearchPresented {
            dismissConversationSearch()
        } else {
            clearMessageSelection()
        }
        composerFocusRequest &+= 1
    }

    func canReply(to message: NativeMessage) -> Bool {
        guard let chat = selectedChat,
              chat.kind.canReply,
              canNavigateConversationHistory,
              let currentMessage = messages.first(where: { $0.id == message.id }) else { return false }
        return currentMessage.replyable
            && !deletionIncludesMessage(currentMessage.id, in: chat.id)
    }

    private func cancelStaleNavigationForReply() {
        cancelReplyTargetNavigation()
        quoteNavigationTask?.cancel()
        quoteNavigationTask = nil
        quoteNavigationRevision &+= 1
        cancelConversationLoadWithoutReplacement()
    }

    private func cancelReplyTargetNavigation() {
        replyTargetNavigationTask?.cancel()
        replyTargetNavigationTask = nil
    }

    @discardableResult
    func replyToSelectedMessage() -> Bool {
        guard selectedMessagesInTranscriptOrder.count == 1,
              let message = selectedMessagesInTranscriptOrder.first,
              canReply(to: message) else { return false }
        beginReply(to: message)
        return replyingTo?.id == message.id
    }

    func cancelReply() {
        guard !isSendingSelectedChat else { return }
        cancelReplyTargetNavigation()
        replyingTo = nil
        replyingChatID = nil
    }

    @discardableResult
    func openReplyTarget() -> Task<Void, Never>? {
        guard let message = replyingTo,
              let chatID = selectedChatID,
              replyingChatID == chatID else { return nil }
        cancelReplyTargetNavigation()
        quoteNavigationTask?.cancel()
        quoteNavigationTask = nil
        quoteNavigationRevision &+= 1
        quoteNavigationError = nil
        let task = navigateToMessage(
            message.id,
            in: chatID,
            invalidateReplyIfMissing: true
        )
        replyTargetNavigationTask = task
        return task
    }

    @discardableResult
    func openQuotedMessage(_ quote: NativeQuote, from containingMessageID: Int64) -> Task<Void, Never>? {
        guard canNavigateConversationHistory, let chatID = selectedChatID else { return nil }
        quoteNavigationTask?.cancel()
        quoteNavigationTask = nil
        quoteNavigationRevision &+= 1
        quoteNavigationError = nil
        if let messageID = quote.messageID {
            return navigateToMessage(messageID, in: chatID)
        }

        let revision = quoteNavigationRevision
        let operation = loadMessageOperation
        let task = Task {
            defer {
                if quoteNavigationRevision == revision {
                    quoteNavigationTask = nil
                }
            }
            do {
                let refreshedMessage: NativeMessage?
                if let operation {
                    refreshedMessage = try await operation(chatID, containingMessageID)
                } else {
                    refreshedMessage = try await core.loadMessage(
                        chatID: chatID,
                        itemID: containingMessageID
                    )
                }
                guard !Task.isCancelled, selectedChatID == chatID,
                      quoteNavigationRevision == revision else { return }
                guard let refreshedMessage,
                      let quotedMessageID = refreshedMessage.quotedItem?.messageID else {
                    quoteNavigationError = "The original quoted message is no longer available in this conversation."
                    return
                }
                if let index = messages.firstIndex(where: { $0.id == containingMessageID }) {
                    messages[index] = refreshedMessage
                }
                if let navigation = navigateToMessage(quotedMessageID, in: chatID) {
                    await navigation.value
                }
            } catch is CancellationError {
                return
            } catch {
                guard selectedChatID == chatID, quoteNavigationRevision == revision else { return }
                quoteNavigationError = error.localizedDescription
            }
        }
        quoteNavigationTask = task
        return task
    }

    private func prepareForQuoteNavigation() {
        if conversationSearchPresented {
            dismissConversationSearch()
        } else {
            clearMessageSelection()
        }
    }

    @discardableResult
    func openAttachment(_ message: NativeMessage) -> Task<Void, Never>? {
        guard message.fileSource != nil || message.fileID != nil,
              let chatID = selectedChatID else { return nil }
        let openingKey = attachmentKey(chatID: chatID, messageID: message.id)
        guard !openingAttachmentKeys.contains(openingKey) else { return nil }
        let loadMessageOperation = loadMessageOperation
        let openAttachmentOperation = openAttachmentOperation
        let opensInQuickLook = openAttachmentOperation == nil && message.content.opensInQuickLook
        if opensInQuickLook {
            quickLookRequestKey = openingKey
            quickLookURL = nil
        }
        openingAttachmentKeys.insert(openingKey)
        let task = Task {
            defer { openingAttachmentKeys.remove(openingKey) }
            do {
                let (source, fileName) = try await resolveAttachment(
                    initialSource: message.fileSource,
                    message: message,
                    chatID: chatID,
                    loadMessageOperation: loadMessageOperation,
                    requiresStoredFile: openAttachmentOperation == nil
                )
                if let openAttachmentOperation {
                    try await openAttachmentOperation(source, fileName)
                } else {
                    let url = try await core.openableURL(
                        for: source,
                        fileName: fileName
                    )
                    try Task.checkCancellation()
                    if opensInQuickLook {
                        inlineImageURLs[openingKey] = url
                        guard selectedChatID == chatID,
                              quickLookRequestKey == openingKey else { return }
                        quickLookRequestKey = nil
                        quickLookURL = url
                    } else if !NSWorkspace.shared.open(url) {
                        throw NativeChatError.unavailable("macOS could not open this attachment.")
                    }
                }
            } catch is CancellationError {
                if quickLookRequestKey == openingKey { quickLookRequestKey = nil }
                return
            } catch {
                if quickLookRequestKey == openingKey { quickLookRequestKey = nil }
                presentAttachmentOpenFailure(error.localizedDescription, in: chatID)
            }
        }
        return task
    }

    @discardableResult
    func prepareInlineAudio(_ message: NativeMessage) -> Task<Void, Never>? {
        guard message.content.inlineAudioFileName != nil,
              let initialSource = message.fileSource,
              let chatID = selectedChatID else { return nil }
        let openingKey = attachmentKey(chatID: chatID, messageID: message.id)
        guard inlineAudioURLs[openingKey] == nil,
              !openingAttachmentKeys.contains(openingKey) else { return nil }

        let loadMessageOperation = loadMessageOperation
        let prepareAttachmentOperation = prepareAttachmentOperation
        openingAttachmentKeys.insert(openingKey)
        let task = Task {
            defer { openingAttachmentKeys.remove(openingKey) }
            do {
                let (source, fileName) = try await resolveAttachment(
                    initialSource: initialSource,
                    message: message,
                    chatID: chatID,
                    loadMessageOperation: loadMessageOperation,
                    requiresStoredFile: prepareAttachmentOperation == nil
                )
                let url: URL
                if let prepareAttachmentOperation {
                    url = try await prepareAttachmentOperation(source, fileName)
                } else {
                    url = try await core.openableURL(for: source, fileName: fileName)
                }
                try Task.checkCancellation()
                inlineAudioURLs[openingKey] = url
            } catch is CancellationError {
                return
            } catch {
                presentAttachmentOpenFailure(error.localizedDescription, in: chatID)
            }
        }
        return task
    }

    func inlineAudioURL(_ messageID: Int64) -> URL? {
        guard let chatID = selectedChatID else { return nil }
        return inlineAudioURLs[attachmentKey(chatID: chatID, messageID: messageID)]
    }

    func inlineImageURL(_ messageID: Int64) -> URL? {
        guard let chatID = selectedChatID else { return nil }
        return inlineImageURLs[attachmentKey(chatID: chatID, messageID: messageID)]
    }

    func receiveAttachment(_ message: NativeMessage) {
        guard let transfer = message.fileTransfer,
              let context = currentUserContext,
              let chatID = selectedChatID else { return }
        let task = fileTransfers.receive(fileID: transfer.id, context: context)
        refreshMessageAfterTransferAction(task, fileID: transfer.id, messageID: message.id, chatID: chatID)
    }

    func retryAttachmentTransfer(_ message: NativeMessage) {
        guard let transfer = message.fileTransfer,
              let context = currentUserContext,
              let chatID = selectedChatID else { return }
        requestedFileIDs.remove(transfer.id)
        let task = fileTransfers.retry(fileID: transfer.id, context: context)
        refreshMessageAfterTransferAction(task, fileID: transfer.id, messageID: message.id, chatID: chatID)
    }

    func cancelAttachmentTransfer(_ message: NativeMessage) {
        guard let transfer = message.fileTransfer,
              let context = currentUserContext,
              let chatID = selectedChatID else { return }
        let task = fileTransfers.cancel(fileID: transfer.id, context: context)
        refreshMessageAfterTransferAction(task, fileID: transfer.id, messageID: message.id, chatID: chatID)
    }

    private var currentUserContext: UserContext? {
        profile.map { UserContext(userID: $0.userID, remoteHostID: currentRemoteHostID) }
    }

    private func refreshMessageAfterTransferAction(
        _ task: Task<Void, Never>,
        fileID: Int64,
        messageID: Int64,
        chatID: NativeChat.ID
    ) {
        Task { [weak self] in
            await task.value
            guard let self, self.fileTransfers.operation(for: fileID)?.errorMessage == nil else {
                return
            }
            do {
                let refreshed: NativeMessage?
                if let loadMessageOperation = self.loadMessageOperation {
                    refreshed = try await loadMessageOperation(chatID, messageID)
                } else {
                    refreshed = try await self.core.loadMessage(chatID: chatID, itemID: messageID)
                }
                guard !Task.isCancelled, self.selectedChatID == chatID,
                      let refreshed,
                      let index = self.messages.firstIndex(where: { $0.id == messageID }) else { return }
                self.messages[index] = refreshed
                self.startAutomaticImageDownloads([refreshed], in: chatID)
            } catch is CancellationError {
                return
            } catch {
                self.presentAttachmentOpenFailure(error.localizedDescription, in: chatID)
            }
        }
    }

    private func resolveAttachment(
        initialSource: NativeCryptoFile?,
        message: NativeMessage,
        chatID: NativeChat.ID,
        loadMessageOperation: LoadMessageOperation?,
        requiresStoredFile: Bool = true
    ) async throws -> (source: NativeCryptoFile, fileName: String?) {
        var currentMessage = message
        var source = initialSource
        var receiveRequested = false
        var refreshedOnce = false

        // A preview can arrive before the original file. Requesting the file and
        // polling the authoritative chat item keeps the low-resolution data URI
        // strictly as a placeholder; Quick Look receives the transferred original.
        for attempt in 0..<120 {
            try Task.checkCancellation()

            if let source,
               source.cryptoArgs != nil,
               !requiresStoredFile || FileManager.default.fileExists(atPath: source.sourceURL.path),
               !currentMessage.attachmentIsInProgress {
                return (
                    source,
                    currentMessage.content.fileName ?? currentMessage.content.attachmentDescription
                )
            }

            if !receiveRequested, currentMessage.attachmentCanBeReceived,
               let fileID = currentMessage.fileID {
                try await requestFileReceiveIfNeeded(fileID)
                receiveRequested = true
            }

            if let failure = currentMessage.attachmentFailureDescription {
                throw NativeChatError.unavailable(failure)
            }

            let refreshedMessage: NativeMessage?
            if let loadMessageOperation {
                refreshedMessage = try await loadMessageOperation(chatID, message.id)
            } else {
                refreshedMessage = try await core.loadMessage(chatID: chatID, itemID: message.id)
            }
            try Task.checkCancellation()
            if let refreshedMessage {
                currentMessage = refreshedMessage
                source = refreshedMessage.fileSource ?? source
                refreshedOnce = true
                if selectedChatID == chatID,
                   let index = messages.firstIndex(where: { $0.id == message.id }) {
                    messages[index] = refreshedMessage
                }
                if let source,
                   !requiresStoredFile || FileManager.default.fileExists(atPath: source.sourceURL.path),
                   !refreshedMessage.attachmentIsInProgress {
                    return (
                        source,
                        refreshedMessage.content.fileName ?? refreshedMessage.content.attachmentDescription
                    )
                }
            }

            if refreshedOnce, let source,
               !requiresStoredFile || FileManager.default.fileExists(atPath: source.sourceURL.path),
               !currentMessage.attachmentIsInProgress {
                return (
                    source,
                    currentMessage.content.fileName ?? currentMessage.content.attachmentDescription
                )
            }

            if attempt < 119 {
                try await Task.sleep(for: .milliseconds(500))
            }
        }

        if currentMessage.attachmentIsInProgress {
            throw NativeChatError.unavailable(
                "The full-resolution image is still downloading. Try opening it again in a moment."
            )
        }
        throw NativeChatError.unavailable(
            "The full-resolution attachment is not available on this Mac."
        )
    }

    private func requestFileReceiveIfNeeded(_ fileID: Int64) async throws {
        guard requestedFileIDs.insert(fileID).inserted else { return }
        do {
            if let receiveFileOperation {
                try await receiveFileOperation(fileID)
            } else {
                try await core.receiveFile(fileID: fileID)
            }
        } catch {
            requestedFileIDs.remove(fileID)
            throw error
        }
    }

    private func startAutomaticImageDownloads(_ loadedMessages: [NativeMessage], in chatID: NativeChat.ID) {
        guard settingsSnapshot.autoAcceptImages, !previewMode else { return }
        for message in loadedMessages {
            guard case .image = message.content,
                  message.fileSource != nil || message.fileID != nil else { continue }
            let key = attachmentKey(chatID: chatID, messageID: message.id)
            guard inlineImageURLs[key] == nil,
                  automaticAttachmentTasks[key] == nil else { continue }

            let loadMessageOperation = loadMessageOperation
            let task = Task { [weak self] in
                guard let self else { return }
                defer { automaticAttachmentTasks[key] = nil }
                do {
                    if message.attachmentCanBeReceived, let fileID = message.fileID {
                        try await requestFileReceiveIfNeeded(fileID)
                    }
                    let (source, fileName) = try await resolveAttachment(
                        initialSource: message.fileSource,
                        message: message,
                        chatID: chatID,
                        loadMessageOperation: loadMessageOperation
                    )
                    let url = try await core.openableURL(for: source, fileName: fileName)
                    try Task.checkCancellation()
                    inlineImageURLs[key] = url
                } catch is CancellationError {
                    return
                } catch {
                    // Background media retrieval remains silent. The explicit
                    // open action surfaces a useful error if the user needs it.
                    if let fileID = message.fileID { requestedFileIDs.remove(fileID) }
                }
            }
            automaticAttachmentTasks[key] = task
        }
    }

    private func resetMediaContext() {
        for task in automaticAttachmentTasks.values { task.cancel() }
        automaticAttachmentTasks.removeAll()
        requestedFileIDs.removeAll()
        openingAttachmentKeys.removeAll()
        inlineAudioURLs.removeAll()
        inlineImageURLs.removeAll()
        quickLookRequestKey = nil
        quickLookURL = nil
    }

    func isOpeningAttachment(_ messageID: Int64) -> Bool {
        guard let chatID = selectedChatID else { return false }
        return openingAttachmentKeys.contains(
            attachmentKey(chatID: chatID, messageID: messageID)
        )
    }

    @discardableResult
    private func navigateToMessage(
        _ messageID: Int64,
        in chatID: NativeChat.ID,
        invalidateReplyIfMissing: Bool = false
    ) -> Task<Void, Never>? {
        guard selectedChatID == chatID else { return nil }
        if messages.contains(where: { $0.id == messageID }) {
            cancelConversationLoadWithoutReplacement()
            prepareForQuoteNavigation()
            conversationAnchorMessageID = messageID
            targetMessageID = messageID
            return nil
        }
        return scheduleConversationLoad(
            chatID: chatID,
            around: messageID,
            scrollTo: messageID,
            navigationFailureMessage: "The original quoted message is no longer available in this conversation.",
            consumeQuoteNavigationStateOnSuccess: true,
            invalidateReplyIfMissing: invalidateReplyIfMissing
        )
    }

    private func cancelConversationLoadWithoutReplacement() {
        conversationLoadTask?.cancel()
        conversationLoadTask = nil
        conversationLoadRevision &+= 1
        isLoadingConversation = false
    }

    func selectMessage(_ id: Int64, modifiers: NSEvent.ModifierFlags) {
        let result = MessageSelection.updated(
            current: selectedMessageIDs,
            anchor: selectionAnchor,
            clicked: id,
            orderedIDs: messages.map(\.id),
            command: modifiers.contains(.command),
            shift: modifiers.contains(.shift)
        )
        selectedMessageIDs = result.selection
        selectionAnchor = result.anchor
    }

    func selectAllMessages() {
        guard transcriptFocused else { return }
        selectedMessageIDs = Set(messages.map(\.id))
        selectionAnchor = messages.last?.id
    }

    func moveMessageSelection(by offset: Int) {
        guard transcriptFocused, !messages.isEmpty else { return }
        let currentID = selectedMessagesInTranscriptOrder.last?.id
        let currentIndex = currentID.flatMap { id in messages.firstIndex(where: { $0.id == id }) }
        let proposed = (currentIndex ?? (offset > 0 ? -1 : messages.count)) + offset
        let targetIndex = min(max(0, proposed), messages.count - 1)
        selectedMessageIDs = [messages[targetIndex].id]
        selectionAnchor = messages[targetIndex].id
    }

    func beginConversationSearch() {
        guard selectedChat != nil else { return }
        conversationSearchPresented = true
    }

    func updateConversationSearchSelection() {
        guard let first = conversationSearchMatches.first else {
            clearMessageSelection()
            return
        }
        selectedMessageIDs = [first.id]
        selectionAnchor = first.id
        targetMessageID = first.id
    }

    func moveConversationSearchResult(by offset: Int) {
        let matches = conversationSearchMatches
        let selectedID = selectedMessagesInTranscriptOrder.last?.id
        guard let nextID = ConversationSearch.nextID(in: matches, currentID: selectedID, offset: offset) else { return }
        selectedMessageIDs = [nextID]
        selectionAnchor = nextID
        targetMessageID = nextID
    }

    func dismissConversationSearch() {
        conversationSearchPresented = false
        conversationSearchText = ""
        clearMessageSelection()
    }

    func copySelectedMessages() {
        guard !selectedMessageIDs.isEmpty else { return }
        let text = MessageSelection.clipboardText(for: selectedMessagesInTranscriptOrder)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func requestDeleteSelectedMessages() {
        guard canDeleteSelectedMessages else { return }
        showingDeleteConfirmation = true
    }

    @discardableResult
    func deleteSelectedMessages() -> Task<Void, Never>? {
        guard let chat = selectedChat, canDeleteSelectedMessages else { return nil }
        let identifiers = selectedMessagesInTranscriptOrder.map(\.id)
        showingDeleteConfirmation = false
        if previewMode, deleteMessagesOperation == nil {
            messages.removeAll { identifiers.contains($0.id) }
            identifiers.forEach { clearReply($0, in: chat.id) }
            clearMessageSelection()
            return nil
        }

        deletingChatID = chat.id
        deletingMessageIDs = Set(identifiers)
        isDeletingMessages = true
        clearMessageSelection()
        let operation = deleteMessagesOperation
        let core = core
        let task = Task { [weak self] in
            var deletionCommitted = false
            do {
                let loadedMessages: [NativeMessage]
                if let operation {
                    loadedMessages = try await operation(identifiers, chat)
                    deletionCommitted = true
                } else {
                    try await core.deleteMessages(identifiers, from: chat)
                    deletionCommitted = true
                    try Task.checkCancellation()
                    loadedMessages = try await core.loadMessages(chatID: chat.id)
                }
                try Task.checkCancellation()
                guard let self else { return }
                self.finishMessageDeletion(loadedMessages, deletedIDs: identifiers, in: chat.id)
            } catch is CancellationError {
                if deletionCommitted {
                    self?.finishCommittedMessageDeletion(deletedIDs: identifiers, in: chat.id)
                } else {
                    self?.finishMessageDeletionCancellation()
                }
            } catch {
                if deletionCommitted {
                    self?.finishCommittedMessageDeletion(deletedIDs: identifiers, in: chat.id)
                } else {
                    self?.finishMessageDeletionFailure(error.localizedDescription, in: chat.id)
                }
            }
        }
        deleteTask = task
        return task
    }

    private func finishMessageDeletion(
        _ loadedMessages: [NativeMessage],
        deletedIDs: [Int64],
        in chatID: NativeChat.ID
    ) {
        clearDeletionState()
        defer { consumePendingNotificationRoutes() }
        deletedIDs.forEach { clearReply($0, in: chatID) }
        guard selectedChatID == chatID else { return }
        conversationAnchorMessageID = nil
        messages = loadedMessages
    }

    private func finishCommittedMessageDeletion(deletedIDs: [Int64], in chatID: NativeChat.ID) {
        clearDeletionState()
        defer { consumePendingNotificationRoutes() }
        deletedIDs.forEach { clearReply($0, in: chatID) }
        guard selectedChatID == chatID else { return }
        if conversationAnchorMessageID.map(deletedIDs.contains) == true {
            conversationAnchorMessageID = nil
        }
        messages.removeAll { deletedIDs.contains($0.id) }
    }

    private func finishMessageDeletionCancellation() {
        clearDeletionState()
        consumePendingNotificationRoutes()
    }

    private func finishMessageDeletionFailure(_ message: String, in chatID: NativeChat.ID) {
        clearDeletionState()
        presentChatOperationFailure(message, in: chatID)
        consumePendingNotificationRoutes()
    }

    private func deletionIncludesMessage(_ messageID: Int64, in chatID: NativeChat.ID?) -> Bool {
        isDeletingMessages
            && deletingChatID == chatID
            && deletingMessageIDs.contains(messageID)
    }

    private func clearDeletionState() {
        deletingChatID = nil
        deletingMessageIDs = []
        isDeletingMessages = false
        deleteTask = nil
    }

    func clearMessageSelection() {
        selectedMessageIDs = []
        selectionAnchor = nil
    }

    func dismissNearestState() {
        if conversationSearchPresented {
            dismissConversationSearch()
        } else if sidebarSearchPresented {
            sidebarSearchPresented = false
            searchText = ""
        } else if editingMessage != nil, !isSendingSelectedChat {
            cancelEditing()
        } else if replyingTo != nil, !isSendingSelectedChat {
            cancelReply()
        } else if !pendingAttachments.isEmpty, !isSendingSelectedChat {
            pendingAttachments = []
        } else if !selectedMessageIDs.isEmpty {
            clearMessageSelection()
        }
    }

    func openNotificationRoute(_ route: NotificationRoute) {
        guard canOpenNotificationRoutes else {
            notificationRouteQueue.enqueue(route)
            return
        }
        if route.remoteHostID != currentRemoteHostID || (
            route.userID != nil && route.userID != profile?.userID
        ) {
            guard notificationContextTask == nil else {
                notificationRouteQueue.enqueue(route)
                return
            }
            notificationContextTask = Task { [weak self] in
                guard let self else { return }
                defer {
                    notificationContextTask = nil
                    consumePendingNotificationRoutes()
                }
                do {
                    if route.remoteHostID != currentRemoteHostID {
                        resetMediaContext()
                        try await core.switchRemoteHost(route.remoteHostID)
                        currentRemoteHostID = route.remoteHostID
                    }
                    if let userID = route.userID, userID != profile?.userID {
                        resetMediaContext()
                        profile = try await core.switchProfile(userID: userID)
                    }
                    guard let activeUserID = profile?.userID else {
                        throw NativeChatError.unavailable("The notification profile is not available.")
                    }
                    chats = try await core.loadChats(userID: activeUserID)
                    openNotificationRoute(route)
                } catch {
                    presentGlobalFailure("Couldn’t open the notification: \(error.localizedDescription)")
                }
            }
            return
        }
        guard chats.contains(where: { $0.id == route.chatID }) else {
            notificationRouteQueue.enqueue(route)
            return
        }
        if isRefreshing || (
            route.chatID == selectedChatID
                && (isSendingSelectedChat || isDeletingSelectedChat)
        ) {
            notificationRouteQueue.enqueue(route)
            return
        }
        transitionToChat(route.chatID, around: route.messageID, scrollTo: route.messageID)
    }

    private var canOpenNotificationRoutes: Bool {
        if case .ready = phase { return true }
        if case .failed = phase { return true }
        return false
    }

    @discardableResult
    private func transitionToChat(
        _ id: NativeChat.ID?,
        around messageID: Int64? = nil,
        scrollTo scrollTarget: Int64? = nil
    ) -> Task<Void, Never>? {
        let changedChat = selectedChatID != id
        guard changedChat || messageID != nil || scrollTarget != nil else { return nil }

        if changedChat {
            quickLookRequestKey = nil
            quickLookURL = nil
            editingMessage = nil
            cancelReplyTargetNavigation()
            quoteNavigationTask?.cancel()
            quoteNavigationTask = nil
            quoteNavigationRevision &+= 1
            if let previousChatID = selectedChatID {
                saveComposerState(for: previousChatID)
                saveConversationNotices(for: previousChatID)
                savePresentedChatOperationFailure(for: previousChatID)
            }
            quoteNavigationError = nil
            replyContextError = nil
            sendStatusMessage = nil
            attachmentOpenError = nil
            selectedChatID = id
            conversationAnchorMessageID = nil
            messages = []
            clearMessageSelection()
            restoreComposerState(for: id)
            targetMessageID = nil
            conversationSearchText = ""
            conversationSearchPresented = false
            if let id, let message = pendingChatOperationErrors.removeValue(forKey: id) {
                presentChatOperationFailure(message, in: id)
            }
            if let id {
                quoteNavigationError = pendingQuoteNavigationErrors.removeValue(forKey: id)
                replyContextError = pendingReplyContextErrors.removeValue(forKey: id)
                sendStatusMessage = pendingSendStatusMessages.removeValue(forKey: id)
                attachmentOpenError = pendingAttachmentOpenErrors.removeValue(forKey: id)
            }
        }
        if let id { notificationManager?.removeDeliveredNotifications(chatID: id) }

        conversationLoadTask?.cancel()
        guard let id else {
            messages = []
            isLoadingConversation = false
            return nil
        }
        if previewMode {
            messages = NativePreviewData.messages(for: id)
            if let scrollTarget, messages.contains(where: { $0.id == scrollTarget }) {
                targetMessageID = scrollTarget
            }
            return nil
        }
        return scheduleConversationLoad(chatID: id, around: messageID, scrollTo: scrollTarget)
    }

    private func saveConversationNotices(for chatID: NativeChat.ID) {
        if let quoteNavigationError {
            pendingQuoteNavigationErrors[chatID] = quoteNavigationError
        }
        if let replyContextError {
            pendingReplyContextErrors[chatID] = replyContextError
        }
        if let sendStatusMessage {
            pendingSendStatusMessages[chatID] = sendStatusMessage
        }
        if let attachmentOpenError {
            pendingAttachmentOpenErrors[chatID] = attachmentOpenError
        }
    }

    private func savePresentedChatOperationFailure(for chatID: NativeChat.ID) {
        guard presentedChatOperationErrorChatID == chatID else { return }
        defer { presentedChatOperationErrorChatID = nil }
        guard case let .failed(message) = phase else { return }
        pendingChatOperationErrors[chatID] = message
        phase = .ready
    }

    private func saveComposerState(for chatID: NativeChat.ID) {
        storeComposerState(
            ConversationComposerState(draft: draft, attachments: pendingAttachments, reply: replyingTo),
            for: chatID
        )
    }

    private func restoreComposerState(for chatID: NativeChat.ID?) {
        let state = chatID.flatMap { composerStates[$0] } ?? ConversationComposerState()
        draft = state.draft
        pendingAttachments = state.attachments
        replyingTo = state.reply
        replyingChatID = state.reply == nil ? nil : chatID
    }

    private func storeComposerState(_ state: ConversationComposerState, for chatID: NativeChat.ID) {
        if state.isEmpty {
            composerStates.removeValue(forKey: chatID)
        } else {
            composerStates[chatID] = state
        }
    }

    private func updateComposerState(
        for chatID: NativeChat.ID,
        _ update: (inout ConversationComposerState) -> Void
    ) {
        if selectedChatID == chatID {
            var state = ConversationComposerState(
                draft: draft,
                attachments: pendingAttachments,
                reply: replyingTo
            )
            update(&state)
            draft = state.draft
            pendingAttachments = state.attachments
            replyingTo = state.reply
            replyingChatID = state.reply == nil ? nil : chatID
        } else {
            var state = composerStates[chatID] ?? ConversationComposerState()
            update(&state)
            storeComposerState(state, for: chatID)
        }
    }

    private func removeSentAttachment(_ attachmentID: PendingAttachment.ID, from chatID: NativeChat.ID) {
        updateComposerState(for: chatID) { state in
            state.attachments.removeAll { $0.id == attachmentID }
        }
    }

    private func applyCommittedMessages(
        _ committedMessages: [NativeMessage],
        in chatID: NativeChat.ID,
        announcement: String
    ) {
        guard selectedChatID == chatID, !committedMessages.isEmpty else { return }
        for message in committedMessages {
            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                messages[index] = message
            } else {
                messages.append(message)
            }
        }
        targetMessageID = committedMessages.last?.id
        if let application = NSApp {
            let userInfo: [NSAccessibility.NotificationUserInfoKey: Any] = [
                .announcement: announcement,
                .priority: NSNumber(value: NSAccessibilityPriorityLevel.medium.rawValue),
            ]
            NSAccessibility.post(
                element: application,
                notification: .announcementRequested,
                userInfo: userInfo
            )
        }
    }

    private func clearReply(_ messageID: Int64, in chatID: NativeChat.ID) {
        updateComposerState(for: chatID) { state in
            if state.reply?.id == messageID { state.reply = nil }
        }
    }

    private func invalidateReplyContext(in chatID: NativeChat.ID) {
        let message = "The message you were replying to is no longer available. Your draft was kept."
        pendingReplyInvalidationChatIDs.remove(chatID)
        updateComposerState(for: chatID) { state in
            state.reply = nil
        }
        if selectedChatID == chatID {
            replyContextError = message
        } else {
            pendingReplyContextErrors[chatID] = message
        }
    }

    private func reportUnconfirmedReplyContext(in chatID: NativeChat.ID) {
        pendingReplyInvalidationChatIDs.remove(chatID)
        let message = "Your message was sent, but the chat service could not link it to the original message."
        if selectedChatID == chatID {
            replyContextError = message
        } else {
            pendingReplyContextErrors[chatID] = message
        }
    }

    private func restoreFailedDraft(_ text: String, in chatID: NativeChat.ID) {
        guard !text.isEmpty else { return }
        updateComposerState(for: chatID) { state in
            if state.draft.isEmpty {
                state.draft = text
            } else if state.draft != text {
                state.draft = "\(text)\n\(state.draft)"
            }
        }
    }

    private func finishSending(
        in chatID: NativeChat.ID,
        quotedMessageID: Int64?,
        quoteCommitResolved: Bool
    ) {
        let replyWasInvalidated = pendingReplyInvalidationChatIDs.remove(chatID) != nil
        isSending = false
        sendingChatID = nil
        sendTask = nil
        if replyWasInvalidated, !quoteCommitResolved, quotedMessageID != nil {
            invalidateReplyContext(in: chatID)
        }
        consumePendingNotificationRoutes()
    }

    private func finishSendFailure(_ message: String, in chatID: NativeChat.ID) {
        presentChatOperationFailure(message, in: chatID)
    }

    private func presentChatOperationFailure(_ message: String, in chatID: NativeChat.ID) {
        if selectedChatID == chatID {
            presentedChatOperationErrorChatID = chatID
            phase = .failed(message)
        } else {
            pendingChatOperationErrors[chatID] = message
        }
    }

    private func presentGlobalFailure(_ message: String) {
        presentedChatOperationErrorChatID = nil
        phase = .failed(message)
    }

    private func finishPostSendRefreshFailure(_ detail: String, in chatID: NativeChat.ID) {
        let message = "Your message was sent, but the conversation could not refresh. Use Refresh to load it. \(detail)"
        if selectedChatID == chatID {
            sendStatusMessage = message
        } else {
            pendingSendStatusMessages[chatID] = message
        }
    }

    private func presentAttachmentOpenFailure(_ message: String, in chatID: NativeChat.ID) {
        if selectedChatID == chatID {
            attachmentOpenError = message
        } else {
            pendingAttachmentOpenErrors[chatID] = message
        }
    }

    @discardableResult
    private func scheduleConversationLoad(
        chatID: NativeChat.ID,
        around messageID: Int64? = nil,
        scrollTo scrollTarget: Int64? = nil,
        navigationFailureMessage: String? = nil,
        consumeQuoteNavigationStateOnSuccess: Bool = false,
        scrollToLatest: Bool = false,
        invalidateReplyIfMissing: Bool = false
    ) -> Task<Void, Never> {
        conversationLoadTask?.cancel()
        let task = Task {
            let loaded = await loadConversation(
                chatID: chatID,
                around: messageID,
                navigationFailureMessage: navigationFailureMessage,
                invalidateReplyIfMissing: invalidateReplyIfMissing
            )
            guard loaded, !Task.isCancelled, selectedChatID == chatID else { return }
            if scrollToLatest, let latestMessageID = messages.last?.id {
                targetMessageID = latestMessageID
            } else if let scrollTarget {
                if messages.contains(where: { $0.id == scrollTarget }) {
                    if consumeQuoteNavigationStateOnSuccess {
                        prepareForQuoteNavigation()
                    }
                    targetMessageID = scrollTarget
                } else if let navigationFailureMessage {
                    quoteNavigationError = navigationFailureMessage
                }
            }
        }
        conversationLoadTask = task
        return task
    }

    @discardableResult
    private func loadConversation(
        chatID: NativeChat.ID,
        around messageID: Int64? = nil,
        showProgress: Bool = true,
        navigationFailureMessage: String? = nil,
        reportFailure: Bool = true,
        invalidateReplyIfMissing: Bool = false
    ) async -> Bool {
        guard selectedChatID == chatID else { return false }
        conversationLoadRevision &+= 1
        let revision = conversationLoadRevision
        isLoadingConversation = showProgress
        defer {
            if selectedChatID == chatID, conversationLoadRevision == revision {
                isLoadingConversation = false
            }
        }
        do {
            let loadedMessages: [NativeMessage]
            if let loadMessagesOperation {
                loadedMessages = try await loadMessagesOperation(chatID, messageID)
            } else {
                loadedMessages = try await core.loadMessages(chatID: chatID, around: messageID)
            }
            guard !Task.isCancelled, selectedChatID == chatID,
                  conversationLoadRevision == revision else { return false }
            if let navigationFailureMessage, let messageID,
               !loadedMessages.contains(where: { $0.id == messageID }) {
                if invalidateReplyIfMissing {
                    invalidateReplyContext(in: chatID)
                } else {
                    quoteNavigationError = navigationFailureMessage
                }
                return false
            }
            applyLoadedMessages(loadedMessages, to: chatID)
            conversationAnchorMessageID = messageID
            hasOlderMessages = messageID == nil && loadedMessages.count >= 75
            if messageID == nil {
                await markChatReadIfNeeded(chatID)
            }
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard !Task.isCancelled, selectedChatID == chatID,
                  conversationLoadRevision == revision else { return false }
            if let navigationFailureMessage {
                quoteNavigationError = invalidateReplyIfMissing
                    ? error.localizedDescription
                    : navigationFailureMessage
            } else if reportFailure {
                presentChatOperationFailure(error.localizedDescription, in: chatID)
            }
            return false
        }
    }

    func applyLoadedMessages(_ loadedMessages: [NativeMessage], to chatID: NativeChat.ID) {
        guard selectedChatID == chatID else { return }
        messages = loadedMessages
        selectedMessageIDs.formIntersection(messages.map(\.id))
        startAutomaticImageDownloads(loadedMessages, in: chatID)

        guard replyingChatID == chatID, let currentReply = replyingTo,
              let refreshedReply = loadedMessages.first(where: { $0.id == currentReply.id }) else { return }
        if refreshedReply.replyable {
            pendingReplyInvalidationChatIDs.remove(chatID)
            replyingTo = refreshedReply
        } else if sendingChatID == chatID {
            pendingReplyInvalidationChatIDs.insert(chatID)
        } else {
            invalidateReplyContext(in: chatID)
        }
    }

    private func markChatReadIfNeeded(_ chatID: NativeChat.ID) async {
        guard let chat = chats.first(where: { $0.id == chatID }), chat.unreadCount > 0,
              !markingReadChatIDs.contains(chatID), windowIsFocused else { return }
        if previewMode, markChatReadOperation == nil { return }

        markingReadChatIDs.insert(chatID)
        defer { markingReadChatIDs.remove(chatID) }
        do {
            if let markChatReadOperation {
                try await markChatReadOperation(chatID)
            } else {
                try await core.markChatRead(chatID: chatID)
            }
            guard let index = chats.firstIndex(where: { $0.id == chatID }) else { return }
            chats[index] = chats[index].markingRead()
            notificationManager?.removeDeliveredNotifications(chatID: chatID)
        } catch is CancellationError {
            return
        } catch {
            return
        }
    }

    func markSelectedChatReadIfVisible() {
        guard conversationAnchorMessageID == nil, !isLoadingConversation,
              let chatID = selectedChatID else { return }
        Task { await markChatReadIfNeeded(chatID) }
    }

    private var windowIsFocused: Bool {
        if let windowFocusedOperation { return windowFocusedOperation() }
        return NSApp.isActive && NSApp.keyWindow?.isKeyWindow == true
    }

    private func startEventLoop() {
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                guard let event = await core.receiveEvent() else { continue }
                await refreshAfterEvent()
                notificationManager?.handleCoreEvent(event)
            }
        }
    }

    func refreshAfterEvent() async {
        guard let userID = profile?.userID else { return }
        do {
            chats = try await loadChats(userID: userID)
            if let chatID = selectedChatID, canRefreshConversation {
                let anchor = conversationAnchorMessageID
                let loaded = await loadConversation(
                    chatID: chatID,
                    around: anchor,
                    showProgress: false,
                    reportFailure: anchor == nil
                )
                if !loaded, anchor != nil, !Task.isCancelled,
                   selectedChatID == chatID,
                   conversationAnchorMessageID == anchor,
                   !isLoadingConversation {
                    conversationAnchorMessageID = nil
                    _ = await loadConversation(chatID: chatID, showProgress: false)
                }
            }
            consumePendingNotificationRoutes()
        } catch is CancellationError {
            return
        } catch {
            presentGlobalFailure(error.localizedDescription)
        }
    }

    private func loadChats(userID: Int64) async throws -> [NativeChat] {
        if let loadChatsOperation {
            return try await loadChatsOperation(userID)
        }
        return try await core.loadChats(userID: userID)
    }

    private func consumePendingNotificationRoutes() {
        let routes = notificationRouteQueue.consumeIfReady(true)
        for route in routes { openNotificationRoute(route) }
    }

    private func attemptAutomaticUnlock() async {
        phase = .opening
        do {
            guard let passphrase = try await passphraseStore.load() else {
                phase = .locked(message: nil)
                return
            }
            hasStoredPassphrase = true
            await openProfile(passphrase: passphrase, rememberPassphrase: true, automatic: true)
        } catch {
            keychainStatusMessage = error.localizedDescription
            phase = .locked(message: "Couldn’t read the saved passphrase. Enter it to continue.")
        }
    }

    private func openProfile(passphrase: String, rememberPassphrase: Bool, automatic: Bool) async {
        do {
            let (profile, chats) = try await core.open(passphrase: passphrase)

            if rememberPassphrase {
                do {
                    try await passphraseStore.save(passphrase)
                    hasStoredPassphrase = true
                    keychainStatusMessage = nil
                } catch {
                    hasStoredPassphrase = false
                    keychainStatusMessage = "The profile opened, but its passphrase wasn’t saved: \(error.localizedDescription)"
                }
            } else if !automatic {
                do {
                    try await passphraseStore.delete()
                    hasStoredPassphrase = false
                } catch {
                    keychainStatusMessage = error.localizedDescription
                }
            }

            self.profile = profile
            currentRemoteHostID = nil
            self.chats = chats
            phase = .ready
            if selectedChatID == nil { selectedChatID = chats.first?.id }
            if let chatID = selectedChatID {
                _ = await loadConversation(chatID: chatID)
            }
            startEventLoop()
            notificationManager?.chatSetupReady()
            consumePendingNotificationRoutes()
        } catch {
            if automatic, error.localizedDescription == "That database passphrase is not correct." {
                do {
                    try await passphraseStore.delete()
                    hasStoredPassphrase = false
                } catch {
                    keychainStatusMessage = error.localizedDescription
                }
                phase = .locked(message: "The saved passphrase no longer opens this profile. Enter the current passphrase.")
            } else {
                phase = .locked(message: error.localizedDescription)
            }
        }
    }
}
