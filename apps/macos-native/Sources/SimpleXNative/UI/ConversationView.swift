import AppKit
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct ConversationView: View {
    @ObservedObject var model: AppModel
    @FocusState private var composerFocused: Bool
    @FocusState private var transcriptFocused: Bool
    @State private var dropTargeted = false
    @State private var blurredMessageIDs: Set<Int64> = []
    @State private var wallpaperSettings = ChatWallpaperSettings.default

    var body: some View {
        Group {
            if let chat = model.selectedChat {
                VStack(spacing: 0) {
                    if model.conversationSearchPresented {
                        ConversationSearchBar(model: model)
                        Divider()
                    }
                    transcript(chat: chat)
                    Divider()
                    composer(chat: chat)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .navigationTitle("")
                .toolbar { conversationToolbar(chat: chat) }
                .onDrop(
                    of: DroppedAttachmentLoader.supportedContentTypes,
                    isTargeted: $dropTargeted
                ) { providers in
                    let accepted = model.stageDroppedAttachments(providers)
                    if accepted { composerFocused = true }
                    return accepted
                }
                .overlay {
                    if dropTargeted {
                        DropTargetOverlay()
                    }
                }
                .confirmationDialog(
                    "Delete selected messages?",
                    isPresented: $model.showingDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete Locally", role: .destructive) {
                        model.deleteSelectedMessages()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This removes the selected messages from this Mac. It does not delete them for other people.")
                }
                .modifier(ConversationAlertsModifier(model: model))
                .sheet(isPresented: $model.forwardingPresented) {
                    ForwardMessagesView(model: model, sourceChat: chat)
                }
                .sheet(isPresented: $model.chatDetailsPresented) {
                    ChatDetailsView(model: model, chat: chat)
                }
                .sheet(item: $model.tagAssignmentChat) { tagChat in
                    TagListView(model: model, chat: tagChat)
                }
                .sheet(isPresented: Binding(
                    get: { model.messageInfoData != nil && model.messageInfoMessage != nil },
                    set: { if !$0 { model.messageInfoData = nil; model.messageInfoMessage = nil } }
                )) {
                    if let info = model.messageInfoData, let msg = model.messageInfoMessage, let infoChat = model.messageInfoChat {
                        MessageInfoView(message: msg, chat: infoChat, info: info)
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("No Conversation Selected", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Choose a chat from the sidebar to start messaging.")
                }
            }
        }
        .onChange(of: transcriptFocused) { _, focused in
            model.transcriptFocused = focused
        }
        .onChange(of: composerFocused) { _, focused in
            if focused { model.transcriptFocused = false }
        }
        .onChange(of: model.composerFocusRequest) { _, _ in
            composerFocused = true
        }
        .onChange(of: model.selectedChatID) { _, chatID in
            loadWallpaper(for: chatID)
        }
        .quickLookPreview($model.quickLookURL)
    }

    @ToolbarContentBuilder
    private func conversationToolbar(chat: NativeChat) -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            HStack(spacing: 8) {
                ProfileAvatar(image: chat.image, name: chat.displayName, size: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(chat.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(chat.kind.toolbarSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Conversation with \(chat.displayName)")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button("Conversation Details", systemImage: "info.circle") {
                model.chatDetailsPresented = true
            }
            .labelStyle(.iconOnly)
            .help("Conversation Details")
            .accessibilityLabel("Conversation Details")

            if model.isViewingConversationHistory {
                Button("Jump to Latest", systemImage: "arrow.down.to.line") {
                    model.jumpToLatest()
                }
                .labelStyle(.iconOnly)
                .disabled(!model.canNavigateConversationHistory)
                .help("Jump to Latest")
                .accessibilityInputLabels(["Jump to Latest", "Latest Messages"])
            }

            Button("Refresh Conversation", systemImage: "arrow.clockwise", action: model.refresh)
                .labelStyle(.iconOnly)
                .disabled(!model.canRefreshConversation)
                .help("Refresh Conversation")
                .accessibilityInputLabels(["Refresh Conversation", "Refresh"])
        }
    }

    private func transcript(chat: NativeChat) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: model.density.tokens.transcriptGap) {
                    if model.conversationAnchorMessageID == nil, model.hasOlderMessages {
                        Button {
                            model.loadOlderMessages()
                        } label: {
                            if model.isLoadingOlderMessages {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label("Load Earlier Messages", systemImage: "arrow.up.to.line")
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(model.isLoadingOlderMessages)
                        .help("Load up to 100 earlier messages")
                        .accessibilityLabel("Load Earlier Messages")
                    }
                    ForEach(Array(model.messages.enumerated()), id: \.element.id) { index, message in
                        if startsNewDay(at: index), let timestamp = message.timestamp {
                            TranscriptDateHeader(date: timestamp)
                        }
                        MessageRow(
                            message: message,
                            chat: chat,
                            selected: model.selectedMessageIDs.contains(message.id),
                            density: model.density,
                            startsGroup: startsGroup(at: index),
                            endsGroup: endsGroup(at: index),
                            openingAttachment: model.isOpeningAttachment(message.id),
                            inlineAudioURL: model.inlineAudioURL(message.id),
                            inlineImageURL: model.inlineImageURL(message.id),
                            transferOperation: message.fileID.flatMap(model.fileTransfers.operation),
                            canReply: model.canReply(to: message),
                            canOpenQuote: model.canNavigateConversationHistory,
                            mediaBlurRadius: model.settingsSnapshot.mediaBlurRadius,
                            isBlurred: blurredMessageIDs.contains(message.id),
                            onHoverMedia: { hovering in
                                let radius = model.settingsSnapshot.mediaBlurRadius
                                guard radius > 0 else { return }
                                if hovering {
                                    blurredMessageIDs.remove(message.id)
                                } else {
                                    blurredMessageIDs.insert(message.id)
                                }
                            }
                        ) {
                            transcriptFocused = true
                            model.selectMessage(message.id, modifiers: NSApp.currentEvent?.modifierFlags ?? [])
                        } copy: {
                            transcriptFocused = true
                            model.selectMessage(message.id, modifiers: [])
                            model.copySelectedMessages()
                        } delete: {
                            transcriptFocused = true
                            model.selectMessage(message.id, modifiers: [])
                            model.requestDeleteSelectedMessages()
                        } reply: {
                            model.beginReply(to: message)
                            composerFocused = true
                        } openQuote: { quote in
                            model.openQuotedMessage(quote, from: message.id)
                        } openAttachment: {
                            model.openAttachment(message)
                        } prepareInlineAudio: {
                            model.prepareInlineAudio(message)
                        } receiveAttachment: {
                            model.receiveAttachment(message)
                        } retryAttachment: {
                            model.retryAttachmentTransfer(message)
                        } cancelAttachment: {
                            model.cancelAttachmentTransfer(message)
                        } react: { emoji in
                            model.toggleReaction(emoji, on: message)
                        } info: {
                            model.presentMessageInfo(message, chat: chat)
                        }
                        .id(message.id)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .defaultScrollAnchor(.bottom)
            .background {
                ChatWallpaperBackground(settings: wallpaperSettings)
                    .ignoresSafeArea()
            }
            .background(Color(nsColor: .textBackgroundColor))
            .focusable()
            .focused($transcriptFocused)
            .focusEffectDisabled()
            .overlay {
                if model.isLoadingConversation { ProgressView() }
            }
            .accessibilityLabel("Conversation transcript") // [VERIFY] Names the keyboard-focusable transcript region.
            .accessibilityHint("Use the arrow keys to select messages. Press Return to reply to the selected message.") // [VERIFY] Describes the transcript keyboard actions.
            .onChange(of: model.messages.last?.id) { _, lastID in
                guard let lastID, model.targetMessageID == nil else { return }
                proxy.scrollTo(lastID, anchor: .bottom)
            }
            .onChange(of: model.selectedMessagesInTranscriptOrder.last?.id) { _, selectedID in
                guard let selectedID else { return }
                proxy.scrollTo(selectedID, anchor: .center)
            }
            .onChange(of: model.targetMessageID) { _, targetID in
                guard let targetID else { return }
                proxy.scrollTo(targetID, anchor: .center)
                model.targetMessageID = nil
            }
            .onChange(of: model.messages.map(\.id)) { _, _ in
                syncBlurredIDs()
            }
            .onChange(of: model.settingsSnapshot.mediaBlurRadius) { _, _ in
                syncBlurredIDs()
            }
            .onKeyPress(.upArrow) {
                model.moveMessageSelection(by: -1)
                return .handled
            }
            .onKeyPress(.downArrow) {
                model.moveMessageSelection(by: 1)
                return .handled
            }
            .onKeyPress(.return) {
                guard model.replyToSelectedMessage() else { return .ignored }
                composerFocused = true
                return .handled
            }
            .onKeyPress(.delete) {
                model.requestDeleteSelectedMessages()
                return model.selectedMessageIDs.isEmpty ? .ignored : .handled
            }
            .onKeyPress(.escape) {
                model.dismissNearestState()
                return .handled
            }
        }
    }

    private func loadWallpaper(for chatID: String?) {
        guard let chatID else {
            wallpaperSettings = .default
            return
        }
        wallpaperSettings = ChatWallpaperStore.settings(for: chatID)
    }

    private func syncBlurredIDs() {
        let radius = model.settingsSnapshot.mediaBlurRadius
        if radius > 0 {
            let mediaIDs = Set(model.messages.filter { msg in
                switch msg.content {
                case .image, .video, .link: return true
                default: return false
                }
            }.map(\.id))
            blurredMessageIDs = mediaIDs
        } else {
            blurredMessageIDs.removeAll()
        }
    }

    private func startsNewDay(at index: Int) -> Bool {
        guard index > 0 else { return true }
        guard let current = model.messages[index].timestamp,
              let previous = model.messages[index - 1].timestamp else { return false }
        return !Calendar.current.isDate(current, inSameDayAs: previous)
    }

    private func startsGroup(at index: Int) -> Bool {
        guard index > 0 else { return true }
        return !messagesBelongToSameGroup(model.messages[index - 1], model.messages[index])
    }

    private func endsGroup(at index: Int) -> Bool {
        guard index + 1 < model.messages.count else { return true }
        return !messagesBelongToSameGroup(model.messages[index], model.messages[index + 1])
    }

    private func messagesBelongToSameGroup(_ first: NativeMessage, _ second: NativeMessage) -> Bool {
        guard first.sent == second.sent, first.author == second.author,
              let firstDate = first.timestamp, let secondDate = second.timestamp else { return false }
        return abs(secondDate.timeIntervalSince(firstDate)) <= 5 * 60
    }

    private func composer(chat: NativeChat) -> some View {
        VStack(spacing: 0) {
            if !model.selectedMessageIDs.isEmpty {
                MessageSelectionBar(
                    count: model.selectedMessageIDs.count,
                    canReply: model.canReplyToSelectedMessage,
                    canEdit: model.canEditSelectedMessage,
                    canDelete: model.canDeleteSelectedMessages,
                    reply: { model.replyToSelectedMessage() },
                    edit: model.beginEditingSelectedMessage,
                    forward: { model.forwardingPresented = true },
                    copy: model.copySelectedMessages,
                    delete: model.requestDeleteSelectedMessages,
                    clear: model.clearMessageSelection
                )
                Divider()
            }

            if let message = model.replyingTo {
                ReplyContextBar(
                    message: message,
                    chat: chat,
                    canOpen: model.canNavigateConversationHistory,
                    canCancel: !model.isSendingSelectedChat,
                    open: { model.openReplyTarget() },
                    cancel: model.cancelReply
                )
                Divider()
            }

            if let message = model.editingMessage {
                EditContextBar(message: message, cancel: model.cancelEditing)
                Divider()
            }

            if !model.pendingAttachments.isEmpty {
                AttachmentTray(model: model)
                Divider()
            }

            if model.voiceRecorder.state != .idle {
                VoiceRecordingBar(model: model)
                Divider()
            }

            if model.pendingLinkPreview != nil || model.isLoadingLinkPreview {
                ComposeLinkPreviewView(
                    preview: model.pendingLinkPreview,
                    isLoading: model.isLoadingLinkPreview,
                    cancel: model.cancelLinkPreview
                )
                Divider()
            }

            if model.showBotCommands {
                BotCommandsMenuView(
                    commands: model.botCommands,
                    filter: model.botCommandFilter,
                    onSelect: { model.selectBotCommand($0) }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }

            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    Button("Choose Files…", action: model.chooseAttachments)
                    Button("Paste Files", action: model.stageFilesFromPasteboard)
                        .keyboardShortcut("v", modifiers: [.command, .option])
                } label: {
                    Image(systemName: "paperclip")
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(model.isSendingSelectedChat)
                .help("Add Attachments")
                .accessibilityLabel("Attachments") // [VERIFY] Matches the attachment menu action.
                .accessibilityInputLabels(["Attachments", "Attach Files"])

                TextField("Message", text: $model.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...8)
                    .focused($composerFocused)
                    .accessibilityIdentifier("composer.message")
                    .onChange(of: model.draft) { _, newValue in
                        model.checkForLinkPreview(newValue)
                        if newValue.hasPrefix("/") && model.botCommands.isEmpty {
                            Task { await model.loadBotCommands() }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, model.density.tokens.composerPadding)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                composerFocused ? Color.accentColor : Color(nsColor: .separatorColor),
                                lineWidth: composerFocused ? 2 : 1
                            )
                    }
                    .onKeyPress(.return, phases: .down) { keyPress in
                        switch ComposerKeyboard.returnAction(
                            shiftPressed: keyPress.modifiers.contains(.shift)
                        ) {
                        case .send:
                            model.sendDraft()
                            return .handled
                        case .insertNewline:
                            return .ignored
                        }
                    }

                Button {
                    model.voiceRecorder.start()
                } label: {
                    Image(systemName: "mic.fill")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(model.isSendingSelectedChat || model.voiceRecorder.state != .idle)
                .help("Record Voice Message")
                .accessibilityLabel("Record Voice Message")

                Button(action: model.sendDraft) {
                    ZStack {
                        Circle()
                            .fill(model.canSendDraft ? Color.accentColor : Color(nsColor: .tertiaryLabelColor))
                        if model.isSendingSelectedChat {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color(nsColor: .selectedControlTextColor))
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.body.weight(.bold))
                                .foregroundStyle(Color(nsColor: .selectedControlTextColor))
                        }
                    }
                    .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(!model.canSendDraft || !chat.kind.canSend)
                .help("Send Message")
                .accessibilityLabel("Send Message") // [VERIFY] Matches the visible tooltip.
                .accessibilityInputLabels(["Send Message", "Send"])
                .accessibilityIdentifier("composer.send")
            }
            .padding(12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct VoiceRecordingBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            switch model.voiceRecorder.state {
            case .idle:
                EmptyView()
            case let .recording(elapsed, level):
                Image(systemName: "waveform")
                    .symbolEffect(.variableColor.iterative, value: level)
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                ProgressView(value: Double(level))
                    .frame(maxWidth: 160)
                    .accessibilityLabel("Microphone level")
                Text(formattedDuration(elapsed))
                    .font(.body.monospacedDigit())
                Spacer()
                Button("Cancel", role: .destructive, action: model.voiceRecorder.cancel)
                Button("Stop", systemImage: "stop.fill", action: model.voiceRecorder.stop)
            case let .review(url, duration):
                Image(systemName: "waveform")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Voice Message")
                    Text(formattedDuration(duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Preview") { NSWorkspace.shared.open(url) }
                Button("Cancel", role: .destructive, action: model.voiceRecorder.cancel)
                Button("Add to Message") {
                    model.stageVoiceRecording(url: url, duration: duration)
                }
            case let .failed(message):
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(message)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Dismiss", action: model.voiceRecorder.cancel)
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }
}

private struct MessageSelectionBar: View {
    let count: Int
    let canReply: Bool
    let canEdit: Bool
    let canDelete: Bool
    let reply: () -> Void
    let edit: () -> Void
    let forward: () -> Void
    let copy: () -> Void
    let delete: () -> Void
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("\(count) selected")
                .font(.callout.weight(.medium))

            Spacer(minLength: 8)

            if canReply {
                Button(action: reply) {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                }
                .accessibilityIdentifier("selection.reply")
            }


            if canEdit {
                Button(action: edit) {
                    Label("Edit", systemImage: "pencil")
                }
            }

            Button(action: forward) {
                Label("Forward", systemImage: "arrowshape.turn.up.right")
            }

            Button(action: copy) {
                Label("Copy", systemImage: "doc.on.doc")
            }

            Button(role: .destructive, action: delete) {
                Label("Delete", systemImage: "trash")
            }
            .disabled(!canDelete)

            Button("Done", action: clear)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
    }
}

private struct EditContextBar: View {
    let message: NativeMessage
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Editing Message")
                    .font(.caption.weight(.semibold))
                Text(message.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Cancel", systemImage: "xmark", action: cancel)
                .labelStyle(.iconOnly)
                .help("Cancel Editing")
                .accessibilityLabel("Cancel Editing")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ConversationAlertsModifier: ViewModifier {
    @ObservedObject var model: AppModel

    func body(content: Content) -> some View {
        content
            .alert("Couldn’t Add Attachment", isPresented: attachmentErrorPresented) {
                Button("OK") { model.attachmentError = nil }
            } message: {
                Text(model.attachmentError ?? "")
            }
            .alert("Couldn’t Open Attachment", isPresented: attachmentOpenErrorPresented) {
                Button("OK") { model.attachmentOpenError = nil }
            } message: {
                Text(model.attachmentOpenError ?? "")
            }
            .alert("Couldn’t Find Quoted Message", isPresented: quoteNavigationErrorPresented) {
                Button("OK") { model.quoteNavigationError = nil }
            } message: {
                Text(model.quoteNavigationError ?? "")
            }
            .alert("Reply Issue", isPresented: replyContextErrorPresented) {
                Button("OK") { model.replyContextError = nil }
            } message: {
                Text(model.replyContextError ?? "")
            }
            .alert("Message Sent", isPresented: sendStatusPresented) {
                Button("OK") { model.sendStatusMessage = nil }
            } message: {
                Text(model.sendStatusMessage ?? "")
            }
    }

    private var attachmentErrorPresented: Binding<Bool> {
        Binding(
            get: { model.attachmentError != nil },
            set: { if !$0 { model.attachmentError = nil } }
        )
    }

    private var attachmentOpenErrorPresented: Binding<Bool> {
        Binding(
            get: { model.attachmentOpenError != nil },
            set: { if !$0 { model.attachmentOpenError = nil } }
        )
    }

    private var quoteNavigationErrorPresented: Binding<Bool> {
        Binding(
            get: { model.quoteNavigationError != nil },
            set: { if !$0 { model.quoteNavigationError = nil } }
        )
    }

    private var replyContextErrorPresented: Binding<Bool> {
        Binding(
            get: { model.replyContextError != nil },
            set: { if !$0 { model.replyContextError = nil } }
        )
    }

    private var sendStatusPresented: Binding<Bool> {
        Binding(
            get: { model.sendStatusMessage != nil },
            set: { if !$0 { model.sendStatusMessage = nil } }
        )
    }
}

private struct ConversationSearchBar: View {
    @ObservedObject var model: AppModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Search Conversation", text: $model.conversationSearchText)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .frame(maxWidth: 320)
                .onSubmit { model.moveConversationSearchResult(by: 1) }

            Text(model.conversationSearchResultDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 64, alignment: .leading)

            Button {
                model.moveConversationSearchResult(by: -1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(model.conversationSearchMatches.isEmpty)
            .help("Previous Result")
            .accessibilityLabel("Previous Result") // [VERIFY] Matches the visible tooltip.
            .accessibilityInputLabels(["Previous Result", "Previous"])

            Button {
                model.moveConversationSearchResult(by: 1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(model.conversationSearchMatches.isEmpty)
            .help("Next Result")
            .accessibilityLabel("Next Result") // [VERIFY] Matches the visible tooltip.
            .accessibilityInputLabels(["Next Result", "Next"])

            Button(action: model.dismissConversationSearch) {
                Image(systemName: "xmark")
            }
            .help("Close Search")
            .accessibilityLabel("Close Search") // [VERIFY] Matches the visible tooltip.
            .accessibilityInputLabels(["Close Search", "Close"])

            Spacer(minLength: 0)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { searchFocused = true }
        .onChange(of: model.conversationSearchText) { _, _ in
            model.updateConversationSearchSelection()
        }
        .onKeyPress(.escape) {
            model.dismissConversationSearch()
            return .handled
        }
    }
}

private struct MessageRow: View {
    @State private var hovering = false

    let message: NativeMessage
    let chat: NativeChat
    let selected: Bool
    let density: DesktopChatDensity
    let startsGroup: Bool
    let endsGroup: Bool
    let openingAttachment: Bool
    let inlineAudioURL: URL?
    let inlineImageURL: URL?
    let transferOperation: FileTransferViewModel.Operation?
    let canReply: Bool
    let canOpenQuote: Bool
    let mediaBlurRadius: Int
    let isBlurred: Bool
    let onHoverMedia: (Bool) -> Void
    let select: () -> Void
    let copy: () -> Void
    let delete: () -> Void
    let reply: () -> Void
    let openQuote: (NativeQuote) -> Void
    let openAttachment: () -> Void
    let prepareInlineAudio: () -> Void
    let receiveAttachment: () -> Void
    let retryAttachment: () -> Void
    let cancelAttachment: () -> Void
    let react: (String) -> Void
    let info: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if !message.sent {
                Group {
                    if endsGroup {
                        ProfileAvatar(image: chat.image, name: message.author ?? chat.displayName, size: 28)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            }

            if message.sent { Spacer(minLength: 80) }

            VStack(alignment: message.sent ? .trailing : .leading, spacing: 4) {
                if startsGroup, !message.sent, let author = message.author, chat.kind == .group {
                    Text(author)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                }

                HStack(alignment: .center, spacing: 4) {
                    if message.sent, canReply { replyControlSlot }
                    messageBubble
                    if !message.sent, canReply { replyControlSlot }
                }
                .contentShape(Rectangle())
                .onHover { hovering = $0 }

                if !message.reactions.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(message.reactions) { reaction in
                            Button {
                                react(reaction.emoji)
                            } label: {
                                Text("\(reaction.emoji) \(reaction.count)")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        reaction.userReacted ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(reaction.emoji), \(reaction.count) reaction\(reaction.count == 1 ? "" : "s")")
                            .accessibilityHint(reaction.userReacted ? "Remove your reaction" : "Add your reaction")
                        }
                    }
                }

                if endsGroup, let timestamp = message.timestamp {
                    Text(timestamp, format: .dateTime.hour().minute())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                }
            }
            .frame(maxWidth: 568, alignment: message.sent ? .trailing : .leading)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            .accessibilityActions {
                Button(selected ? "Deselect Message" : "Select Message", action: select)
                if canOpenQuote, let quote = message.quotedItem {
                    Button("Show Quoted Message") { openQuote(quote) }
                }
                if canReply {
                    Button("Reply", action: reply)
                }
            }

            if !message.sent { Spacer(minLength: 80) }
        }
        .contextMenu {
            if canReply {
                Button("Reply", action: reply)
                Divider()
            }
            Menu("React") {
                ForEach(["👍", "👎", "😀", "😂", "😢", "❤️", "🚀", "✅"], id: \.self) { emoji in
                    Button(emoji) { react(emoji) }
                }
            }
            Button("Copy", action: copy)
            Button(selected ? "Deselect Message" : "Select Message", action: select)
            Divider()
            Button("Info…", action: info)
            if message.deletable {
                Divider()
                Button("Delete…", role: .destructive, action: delete)
            }
        }
        .accessibilityIdentifier("message.\(message.id)")
    }

    private var messageBubble: some View {
        MessageContentView(
            message: message,
            chat: chat,
            openingAttachment: openingAttachment,
            inlineAudioURL: inlineAudioURL,
            inlineImageURL: inlineImageURL,
            transferOperation: transferOperation,
            canOpenQuote: canOpenQuote,
            mediaBlurRadius: mediaBlurRadius,
            isBlurred: isBlurred,
            onHoverMedia: onHoverMedia,
            openQuote: openQuote,
            openAttachment: openAttachment,
            prepareInlineAudio: prepareInlineAudio,
            receiveAttachment: receiveAttachment,
            retryAttachment: retryAttachment,
            cancelAttachment: cancelAttachment
        )
        .padding(.horizontal, 12)
        .padding(.vertical, density.tokens.messagePadding)
        .background(bubbleBackground, in: bubbleShape)
        .foregroundStyle(message.sent ? Color(nsColor: .selectedControlTextColor) : Color.primary)
        .overlay(alignment: .topTrailing) {
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.accentColor)
                    .padding(5)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(bubbleShape)
        .simultaneousGesture(
            TapGesture().onEnded {
                let modifiers = NSApp.currentEvent?.modifierFlags ?? []
                guard modifiers.contains(.command) || modifiers.contains(.shift) else { return }
                select()
            }
        )
        .focusEffectDisabled()
    }

    @ViewBuilder
    private var replyControlSlot: some View {
        if MessageReplyControlVisibility.isVisible(
            canReply: canReply,
            hovering: hovering,
            selected: selected
        ) {
            Button(action: reply) {
                Image(systemName: "arrowshape.turn.up.left")
                    .frame(width: 28, height: 28)
                    .background(Color(nsColor: .controlBackgroundColor), in: Circle())
                    .overlay {
                        Circle().stroke(Color(nsColor: .separatorColor))
                    }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .help("Reply")
            .accessibilityLabel("Reply") // [VERIFY] Matches the visible tooltip.
            .accessibilityInputLabels(["Reply", "Quote Message"])
            .accessibilityIdentifier("message.\(message.id).reply")
        } else {
            Color.clear
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        }
    }

    private var bubbleBackground: Color {
        message.sent
            ? Color(nsColor: .selectedContentBackgroundColor)
            : Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    }

    private var bubbleShape: UnevenRoundedRectangle {
        if message.sent {
            UnevenRoundedRectangle(
                topLeadingRadius: 16,
                bottomLeadingRadius: 16,
                bottomTrailingRadius: endsGroup ? 4 : 16,
                topTrailingRadius: 16
            )
        } else {
            UnevenRoundedRectangle(
                topLeadingRadius: 16,
                bottomLeadingRadius: endsGroup ? 4 : 16,
                bottomTrailingRadius: 16,
                topTrailingRadius: 16
            )
        }
    }
}

private struct TranscriptDateHeader: View {
    let date: Date

    var body: some View {
        Text(label)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .accessibilityAddTraits(.isHeader)
    }

    private var label: String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

private struct ReplyContextBar: View {
    let message: NativeMessage
    let chat: NativeChat
    let canOpen: Bool
    let canCancel: Bool
    let open: () -> Void
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: open) {
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(.tint)
                        .frame(width: 4)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Replying to \(sender)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tint)
                        Text(preview)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if let visual = message.content.replyContextVisual {
                        Spacer(minLength: 8)
                        ReplyContextVisualView(visual: visual)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canOpen)
            .help("Show Original Message")
            .accessibilityHint("Moves to the message being replied to in this conversation.")
            .accessibilityInputLabels(["Replying to \(sender)", "Show Original Message"]) // [VERIFY] The first label matches visible text.
            .accessibilityIdentifier("composer.replyContext")

            Spacer(minLength: 8)

            Button(action: cancel) {
                Image(systemName: "xmark")
                    .frame(width: 28, height: 28)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .buttonStyle(.borderless)
            .disabled(!canCancel)
            .help("Cancel Reply")
            .accessibilityLabel("Cancel Reply") // [VERIFY] Matches the visible tooltip.
            .accessibilityInputLabels(["Cancel Reply", "Cancel"])
            .accessibilityIdentifier("composer.cancelReply")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sender: String {
        chat.displayedMessageAuthor(sent: message.sent, author: message.author)
    }

    private var preview: String {
        message.replyPreview
    }
}

private struct ReplyContextVisualView: View {
    let visual: NativeReplyContextVisual

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary)

            switch visual {
            case let .image(preview):
                mediaPreview(preview, fallback: "photo")
            case let .video(preview):
                mediaPreview(preview, fallback: "film")
                Image(systemName: "play.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color(nsColor: .selectedControlTextColor))
                    .shadow(radius: 2)
            case .voice:
                Image(systemName: "waveform")
                    .foregroundStyle(.secondary)
            case .file:
                Image(systemName: "doc")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func mediaPreview(_ preview: String?, fallback: String) -> some View {
        if let image = NativeChatParser.image(from: preview) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .accessibilityIgnoresInvertColors()
        } else {
            Image(systemName: fallback)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AttachmentTray: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(model.pendingAttachments.enumerated()), id: \.element.id) { index, attachment in
                    AttachmentCard(
                        attachment: attachment,
                        canMoveEarlier: index > 0,
                        canMoveLater: index + 1 < model.pendingAttachments.count
                    ) {
                        model.removeAttachment(attachment.id)
                    } moveEarlier: {
                        model.moveAttachment(attachment.id, by: -1)
                    } moveLater: {
                        model.moveAttachment(attachment.id, by: 1)
                    }
                    .draggable(attachment.id.uuidString)
                    .dropDestination(for: String.self) { values, _ in
                        guard let value = values.first, let source = UUID(uuidString: value) else { return false }
                        model.reorderAttachment(source, before: attachment.id)
                        return true
                    }
                    .accessibilityActions {
                        if index > 0 {
                            Button("Move Earlier") { model.moveAttachment(attachment.id, by: -1) }
                        }
                        if index + 1 < model.pendingAttachments.count {
                            Button("Move Later") { model.moveAttachment(attachment.id, by: 1) }
                        }
                        Button("Remove Attachment") { model.removeAttachment(attachment.id) }
                    }
                    .disabled(model.isSendingSelectedChat)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.never)
        .accessibilityLabel("Pending Attachments")
    }
}

private struct AttachmentCard: View {
    let attachment: PendingAttachment
    let canMoveEarlier: Bool
    let canMoveLater: Bool
    let remove: () -> Void
    let moveEarlier: () -> Void
    let moveLater: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let image = NativeChatParser.image(from: attachment.previewImage) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .accessibilityLabel("Preview of \(attachment.fileName)")
                        .accessibilityIgnoresInvertColors()
                } else {
                    Image(systemName: attachment.kind.symbolName)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 4) {
                Text(attachment.fileName)
                    .lineLimit(1)
                Text(attachment.byteCount, format: .byteCount(style: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove \(attachment.fileName)")
            .accessibilityLabel("Remove \(attachment.fileName)") // [VERIFY] Uses the visible file name.
            .accessibilityInputLabels(["Remove \(attachment.fileName)", "Remove Attachment"])
        }
        .padding(8)
        .frame(width: 224, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .contextMenu {
            Button("Move Earlier", action: moveEarlier)
                .disabled(!canMoveEarlier)
            Button("Move Later", action: moveLater)
                .disabled(!canMoveLater)
            Divider()
            Button("Remove Attachment", role: .destructive, action: remove)
        }
    }
}

private struct MessageContentView: View {
    @State private var playingLinkVideo = false
    @State private var requestedAudioPlayback = false

    let message: NativeMessage
    let chat: NativeChat
    let openingAttachment: Bool
    let inlineAudioURL: URL?
    let inlineImageURL: URL?
    let transferOperation: FileTransferViewModel.Operation?
    let canOpenQuote: Bool
    let mediaBlurRadius: Int
    let isBlurred: Bool
    let onHoverMedia: (Bool) -> Void
    let openQuote: (NativeQuote) -> Void
    let openAttachment: () -> Void
    let prepareInlineAudio: () -> Void
    let receiveAttachment: () -> Void
    let retryAttachment: () -> Void
    let cancelAttachment: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let quote = message.quotedItem {
                QuotedMessagePreview(
                    quote: quote,
                    chat: chat,
                    outgoing: message.sent,
                    containingMessageID: message.id,
                    enabled: canOpenQuote,
                    open: { openQuote(quote) }
                )
            }

            switch message.content {
            case .text:
                messageText
            case .link(let preview):
                linkPreview(preview)
                if message.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    != preview.uri.trimmingCharacters(in: .whitespacesAndNewlines) {
                    messageText
                }
            case .image(let preview, let fileName):
                mediaPreview(preview: preview, fileName: fileName ?? "Image", video: false)
                if !message.text.isEmpty { messageText }
            case .video(let preview, let fileName):
                mediaPreview(preview: preview, fileName: fileName ?? "Video", video: true)
                if !message.text.isEmpty { messageText }
            case .voice(let fileName, let duration):
                audioAttachment(fileName: fileName ?? "Voice message", duration: duration)
                if !message.text.isEmpty { messageText }
            case .file(let fileName):
                if NativeAudioFile.supports(fileName) {
                    audioAttachment(fileName: fileName ?? message.text, duration: nil)
                } else {
                    fileAttachment(name: fileName ?? message.text)
                }
                if !message.text.isEmpty, message.text != fileName { messageText }
            }

            if let transfer = message.fileTransfer,
               transfer.rawStatus != "sndComplete",
               transfer.rawStatus != "rcvComplete" {
                FileTransferStatusView(
                    transfer: transfer,
                    operation: transferOperation,
                    receive: receiveAttachment,
                    retry: retryAttachment,
                    cancel: cancelAttachment
                )
            }
        }
    }

    @ViewBuilder
    private func audioAttachment(fileName: String, duration: Int?) -> some View {
        if requestedAudioPlayback, let inlineAudioURL {
            InlineAudioPlayer(
                url: inlineAudioURL,
                title: fileName,
                fallbackDuration: duration,
                close: { requestedAudioPlayback = false }
            )
        } else if attachmentExists {
            Button {
                requestedAudioPlayback = true
                prepareInlineAudio()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "play.circle.fill")
                        .font(.title)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(fileName)
                            .lineLimit(1)
                        Text(openingAttachment ? "Preparing audio…" : "Play audio")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if openingAttachment {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Preparing Audio")
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(openingAttachment)
            .help("Play \(fileName)")
            .accessibilityLabel("Play \(fileName)") // [VERIFY] Uses the visible audio file name.
            .accessibilityInputLabels(["Play \(fileName)", "Play Audio"])
        } else {
            Label(fileName, systemImage: "waveform")
                .foregroundStyle(.secondary)
        }
    }

    private var messageText: some View {
        MessageBodyText(text: message.text)
    }

    @ViewBuilder
    private func linkPreview(_ preview: NativeLinkPreview) -> some View {
        if let destination = preview.destination, let inlineVideoURL = preview.inlineVideoURL {
            playableLinkPreview(preview, destination: destination, inlineVideoURL: inlineVideoURL)
        } else if let destination = preview.destination {
            Link(destination: destination) {
                linkPreviewContent(preview)
            }
            .buttonStyle(.plain)
            .help("Open \(preview.uri)")
            .accessibilityHint("Opens in your default browser")
        } else {
            linkPreviewContent(preview)
        }
    }

    private func playableLinkPreview(
        _ preview: NativeLinkPreview,
        destination: URL,
        inlineVideoURL: URL
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if playingLinkVideo {
                InlineVideoPlayer(url: inlineVideoURL)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(maxWidth: 480)
                    .accessibilityElement(children: .contain)
            } else {
                Button {
                    playingLinkVideo = true
                } label: {
                    linkPreviewArtwork(preview, showPlayButton: true)
                }
                .buttonStyle(.plain)
                .help("Play video here")
                .accessibilityLabel("Play \(preview.title.isEmpty ? "YouTube Video" : preview.title)") // [VERIFY] Uses the visible preview title when available.
                .accessibilityInputLabels(["Play Video", preview.title].filter { !$0.isEmpty })
            }

            linkPreviewMetadata(preview)

            HStack(spacing: 12) {
                if playingLinkVideo {
                    Button("Close Video") {
                        playingLinkVideo = false
                    }
                }
                Spacer(minLength: 0)
                Link("Open in Browser", destination: destination)
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: 480, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .onKeyPress(.escape) {
            guard playingLinkVideo else { return .ignored }
            playingLinkVideo = false
            return .handled
        }
    }

    private func linkPreviewContent(_ preview: NativeLinkPreview) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if preview.image != nil {
                linkPreviewArtwork(preview, showPlayButton: false)
            }
            linkPreviewMetadata(preview)
        }
        .frame(maxWidth: 480, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private func linkPreviewArtwork(_ preview: NativeLinkPreview, showPlayButton: Bool) -> some View {
        ZStack {
            if let image = NativeChatParser.image(from: preview.image) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityHidden(true)
                    .accessibilityIgnoresInvertColors()
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .accessibilityHidden(true)
            }

            if showPlayButton {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 48))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
                    .accessibilityHidden(true)
            }

            if let duration = preview.durationLabel {
                VStack {
                    Spacer(minLength: 0)
                    HStack {
                        Spacer(minLength: 0)
                        Text(duration)
                            .font(.caption.monospacedDigit())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.72), in: Capsule())
                            .foregroundStyle(.white)
                            .padding(8)
                    }
                }
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .frame(maxWidth: 480)
        .clipped()
        .blur(radius: isBlurred ? CGFloat(mediaBlurRadius) : 0)
        .onHover { onHoverMedia($0) }
    }

    private func linkPreviewMetadata(_ preview: NativeLinkPreview) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !preview.title.isEmpty {
                Text(preview.title)
                    .font(.headline)
                    .lineLimit(2)
            }
            if !preview.description.isEmpty {
                Text(preview.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Text(preview.displayHost)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
    }

    @ViewBuilder
    private func mediaPreview(preview: String?, fileName: String, video: Bool) -> some View {
        let previewView = ZStack {
            if !video, let inlineImageURL {
                NativeLocalImageView(url: inlineImageURL)
                    .accessibilityIgnoresInvertColors()
            } else if let image = NativeChatParser.image(from: preview) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityIgnoresInvertColors()
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .overlay {
                        Image(systemName: video ? "film" : "photo")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }
            }
            if video {
                Image(systemName: "play.circle.fill")
                    .font(.largeTitle)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
                    .accessibilityHidden(true)
            }
            if openingAttachment {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Decrypting Attachment")
            } else if message.attachmentCanBeReceived {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.largeTitle)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: 420, maxHeight: 320)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .blur(radius: isBlurred ? CGFloat(mediaBlurRadius) : 0)
        .onHover { onHoverMedia($0) }

        if attachmentIsActionable {
            Button(action: openAttachment) {
                previewView
            }
            .buttonStyle(.plain)
            .disabled(openingAttachment)
            .help(message.attachmentCanBeReceived ? "Download and open \(fileName)" : "Open \(fileName)")
            .accessibilityLabel(message.attachmentCanBeReceived ? "Download and open \(fileName)" : "Open \(fileName)")
            .accessibilityInputLabels(["Open \(fileName)", "Download Attachment", "Open Attachment"])
        } else {
            previewView
                .accessibilityLabel(video ? "Video attachment, \(fileName)" : "Image attachment, \(fileName)")
        }
    }

    @ViewBuilder
    private func fileAttachment(name: String) -> some View {
        if attachmentIsActionable {
            Button(action: openAttachment) {
                Label(name.isEmpty ? "File" : name, systemImage: "doc")
                if openingAttachment {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Decrypting Attachment")
                }
            }
            .buttonStyle(.link)
            .disabled(openingAttachment)
            .help("Open \(name)")
        } else {
            Label(name.isEmpty ? "File" : name, systemImage: "doc")
                .foregroundStyle(.secondary)
        }
    }

    private var attachmentExists: Bool {
        guard let source = message.fileSource else { return false }
        return FileManager.default.fileExists(atPath: source.sourceURL.path)
    }

    private var attachmentIsActionable: Bool {
        attachmentExists || message.fileID != nil
    }
}

private struct FileTransferStatusView: View {
    let transfer: NativeFileTransfer
    let operation: FileTransferViewModel.Operation?
    let receive: () -> Void
    let retry: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let fraction = transfer.state.fractionCompleted {
                    ProgressView(value: fraction)
                        .frame(width: 104)
                        .accessibilityLabel(transfer.statusLabel ?? "File transfer progress")
                        .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
                } else {
                    Image(systemName: statusSymbol)
                        .foregroundStyle(statusColor)
                        .accessibilityHidden(true)
                }

                Text(operationLabel ?? transfer.statusLabel ?? "File transfer")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if operation?.isRunning == true {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(operationLabel ?? "Updating file transfer")
                }

                Spacer(minLength: 0)

                actionButtons
            }

            if let progressLabel {
                Text(progressLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            if let errorMessage = operation?.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 2)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var actionButtons: some View {
        if operation?.isRunning != true {
            if transfer.canRetry {
                Button("Retry", action: retry)
                    .buttonStyle(.link)
                    .help("Retry file transfer")
                    .accessibilityLabel("Retry \(attachmentName)") // [VERIFY] Uses the visible attachment name.
            } else if transfer.canReceive {
                Button("Download", action: receive)
                    .buttonStyle(.link)
                    .help("Download original file")
                    .accessibilityLabel("Download \(attachmentName)") // [VERIFY] Uses the visible attachment name.
            }

            if transfer.canCancel {
                Button("Cancel", role: .destructive, action: cancel)
                    .buttonStyle(.link)
                    .help("Stop file transfer")
                    .accessibilityLabel("Cancel transfer of \(attachmentName)") // [VERIFY] Uses the visible attachment name.
            }
        }
    }

    private var operationLabel: String? {
        switch operation?.action {
        case .receiving: "Starting download…"
        case .retrying: "Retrying download…"
        case .cancelling: "Cancelling…"
        case nil: nil
        }
    }

    private var attachmentName: String {
        let name = transfer.fileName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "attachment" : name
    }

    private var progressLabel: String? {
        guard let completed = transfer.state.bytesTransferred,
              let total = transfer.state.totalBytes,
              total > 0 else {
            return transfer.fileSize.map { $0.formatted(.byteCount(style: .file)) }
        }
        return "\(completed.formatted(.byteCount(style: .file))) of \(total.formatted(.byteCount(style: .file)))"
    }

    private var statusSymbol: String {
        switch transfer.state {
        case .failed: "exclamationmark.triangle.fill"
        case .cancelled: "xmark.circle.fill"
        case .paused: "pause.circle.fill"
        case .queued: "arrow.down.circle"
        case .complete: "checkmark.circle.fill"
        case .transferring: "arrow.triangle.2.circlepath"
        }
    }

    private var statusColor: Color {
        switch transfer.state {
        case .failed: .red
        case .cancelled, .paused: .secondary
        case .queued, .transferring: .accentColor
        case .complete: .green
        }
    }
}

struct NativeLocalImageView: NSViewRepresentable {
    let url: URL

    final class Coordinator {
        var displayedURL: URL?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageFrameStyle = .none
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.animates = true
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        updateImage(in: imageView, coordinator: context.coordinator)
        return imageView
    }

    func updateNSView(_ imageView: NSImageView, context: Context) {
        updateImage(in: imageView, coordinator: context.coordinator)
    }

    private func updateImage(in imageView: NSImageView, coordinator: Coordinator) {
        guard coordinator.displayedURL != url else { return }
        coordinator.displayedURL = url
        imageView.image = NSImage(contentsOf: url)
    }
}

struct MessageBodyText: View {
    let text: String

    var body: some View {
        Group {
            if let destination = NativeMessageLink.standaloneURL(in: text) {
                Link(destination: destination) {
                    Text(text)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .help("Open \(destination.absoluteString)")
            } else {
                Text(text)
            }
        }
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    }
}

private struct QuotedMessagePreview: View {
    let quote: NativeQuote
    let chat: NativeChat
    let outgoing: Bool
    let containingMessageID: Int64
    let enabled: Bool
    let open: () -> Void

    var body: some View {
        Button(action: open) { content }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .help("Show Quoted Message")
            .accessibilityHint("Moves to the original message in this conversation.")
            .accessibilityInputLabels([quote.text, "Quoted Message"]) // [VERIFY] The first label matches visible quote text.
            .accessibilityIdentifier("message.\(containingMessageID).quote")
    }

    private var content: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(outgoing ? Color(nsColor: .selectedControlTextColor) : Color.accentColor)
                .frame(width: 4)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(sender)
                    .font(.caption.weight(.semibold))
                Text(quote.text)
                    .font(.callout)
                    .lineLimit(2)
            }

            if let visual = quote.visual {
                Spacer(minLength: 8)
                ReplyContextVisualView(visual: visual)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Quoted message from \(sender): \(quote.text)")
    }

    private var sender: String {
        chat.displayedMessageAuthor(sent: quote.sent, author: quote.author)
    }
}

private struct DropTargetOverlay: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Label("Drop files to attach", systemImage: "tray.and.arrow.down.fill")
            .font(.headline)
            .padding(24)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(reduceTransparency
                        ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                        : AnyShapeStyle(.regularMaterial))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
            }
            .accessibilityAddTraits(.isStaticText)
    }
}
