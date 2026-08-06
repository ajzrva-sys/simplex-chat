import SwiftUI

struct TagListView: View {
    @ObservedObject var model: AppModel
    let chat: NativeChat?
    @Environment(\.dismiss) private var dismiss

    @State private var tags: [ChatTag] = []
    @State private var chatTagIds: Set<Int64> = []
    @State private var showCreateSheet = false
    @State private var editingTag: ChatTag?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if let chat {
                Text("Tags for \(chat.displayName)")
                    .font(.headline)
                    .padding()

                Divider()

                List(tags) { tag in
                    Button {
                        toggleTag(tag)
                    } label: {
                        HStack {
                            if tag.hasEmoji {
                                Text(tag.displayEmoji)
                            }
                            Text(tag.chatTagText)
                            Spacer()
                            if chatTagIds.contains(tag.chatTagId) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } else {
                List {
                    ForEach(tags) { tag in
                        HStack {
                            if tag.hasEmoji {
                                Text(tag.displayEmoji)
                            }
                            Text(tag.chatTagText)
                            Spacer()
                            Button {
                                editingTag = tag
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)

                            Button(role: .destructive) {
                                deleteTag(tag)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .onMove { from, to in
                        tags.move(fromOffsets: from, toOffset: to)
                        reorderTags()
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding()
            }
        }
        .frame(width: 360, height: 400)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            TagEditorView(tag: nil) { emoji, text in
                createTag(emoji: emoji, text: text)
            }
        }
        .sheet(item: $editingTag) { tag in
            TagEditorView(tag: tag) { emoji, text in
                updateTag(tag, emoji: emoji, text: text)
            }
        }
        .task { await loadTags() }
    }

    private func loadTags() async {
        do {
            tags = try await model.loadChatTags()
            if let chat {
                chatTagIds = Set(model.chatTagIds[chat.id] ?? chat.chatTagIds)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleTag(_ tag: ChatTag) {
        guard let chat else { return }
        var newIds = chatTagIds
        if newIds.contains(tag.chatTagId) {
            newIds.remove(tag.chatTagId)
        } else {
            newIds.insert(tag.chatTagId)
        }
        Task {
            do {
                let result = try await model.setChatTagsForChat(chatID: chat.id, tagIds: Array(newIds))
                tags = result.userTags
                chatTagIds = Set(result.chatTagIds)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func createTag(emoji: String?, text: String) {
        Task {
            do {
                tags = try await model.createChatTag(emoji: emoji, text: text)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func updateTag(_ tag: ChatTag, emoji: String?, text: String) {
        Task {
            do {
                try await model.updateChatTag(tagId: tag.chatTagId, emoji: emoji, text: text)
                await loadTags()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteTag(_ tag: ChatTag) {
        Task {
            do {
                try await model.deleteChatTag(tagId: tag.chatTagId)
                tags.removeAll { $0.chatTagId == tag.chatTagId }
                model.userTags = tags
                for (chatID, var ids) in model.chatTagIds {
                    ids.removeAll { $0 == tag.chatTagId }
                    model.chatTagIds[chatID] = ids
                }
                if model.activeTagFilter == tag.chatTagId {
                    model.activeTagFilter = nil
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func reorderTags() {
        Task {
            do {
                try await model.reorderChatTags(tagIds: tags.map(\.chatTagId))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct TagEditorView: View {
    let tag: ChatTag?
    let onSave: (String?, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var emoji: String = ""
    @State private var text: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text(tag == nil ? "New Tag" : "Edit Tag")
                .font(.headline)

            HStack {
                TextField("Emoji", text: $emoji)
                    .frame(width: 60)
                    .multilineTextAlignment(.center)
                TextField("Name", text: $text)
            }
            .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    let trimmedEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(trimmedEmoji.isEmpty ? nil : trimmedEmoji, trimmedText)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
        .onAppear {
            if let tag {
                emoji = tag.chatTagEmoji ?? ""
                text = tag.chatTagText
            }
        }
    }
}
