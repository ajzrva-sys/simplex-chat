import SwiftUI

struct TagFilterBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if !model.userTags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    TagChip(
                        label: "All",
                        isSelected: model.activeTagFilter == nil,
                        action: { model.activeTagFilter = nil }
                    )
                    ForEach(model.userTags) { tag in
                        TagChip(
                            emoji: tag.displayEmoji,
                            label: tag.chatTagText,
                            isSelected: model.activeTagFilter == tag.chatTagId,
                            action: { model.activeTagFilter = tag.chatTagId }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
    }
}

private struct TagChip: View {
    let emoji: String?
    let label: String
    let isSelected: Bool
    let action: () -> Void

    init(emoji: String? = nil, label: String, isSelected: Bool, action: @escaping () -> Void) {
        self.emoji = emoji
        self.label = label
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let emoji, !emoji.isEmpty {
                    Text(emoji)
                }
                Text(label)
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
