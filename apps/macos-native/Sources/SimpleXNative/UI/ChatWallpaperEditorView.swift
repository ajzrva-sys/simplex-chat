import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ChatWallpaperEditorView: View {
    let chatID: String
    let chatName: String
    @Environment(\.dismiss) private var dismiss
    @State private var settings: ChatWallpaperSettings
    @State private var showImagePicker = false

    init(chatID: String, chatName: String) {
        self.chatID = chatID
        self.chatName = chatName
        _settings = State(initialValue: ChatWallpaperStore.settings(for: chatID))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Preset Wallpapers") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 64))], spacing: 12) {
                        // None tile
                        WallpaperTile(
                            isSelected: settings.isNone,
                            label: "None"
                        ) {
                            Rectangle()
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .overlay {
                                    Image(systemName: "slash.circle")
                                        .foregroundStyle(.secondary)
                                }
                        }
                        .onTapGesture {
                            settings.type = .none
                        }

                        // Preset tiles
                        ForEach(WallpaperPresets.all) { preset in
                            WallpaperTile(
                                isSelected: settings.type == .preset(preset.id),
                                label: preset.name
                            ) {
                                presetThumbnail(preset)
                            }
                            .onTapGesture {
                                settings.type = .preset(preset.id)
                            }
                        }

                        // Custom image tile
                        WallpaperTile(
                            isSelected: {
                                if case .image = settings.type { return true }
                                return false
                            }(),
                            label: "Custom"
                        ) {
                            Rectangle()
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .overlay {
                                    Image(systemName: "photo")
                                        .foregroundStyle(.secondary)
                                }
                        }
                        .onTapGesture {
                            showImagePicker = true
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Scale") {
                    HStack {
                        Text("0.5×")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                        Slider(value: $settings.scale, in: 0.5...2.0, step: 0.1)
                        Text("2.0×")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .leading)
                    }
                    Text(String(format: "Scale: %.1f×", settings.scale))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Preview") {
                    ChatWallpaperBackground(settings: settings)
                        .frame(height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(nsColor: .separatorColor))
                        }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Wallpaper — \(chatName)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Reset") {
                        settings = .default
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        ChatWallpaperStore.save(settings, for: chatID)
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $showImagePicker,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    if let fileName = ChatWallpaperStore.saveCustomImage(from: url) {
                        settings = ChatWallpaperSettings(
                            type: .image(fileName),
                            scale: settings.scale,
                            tintColor: settings.tintColor
                        )
                    }
                }
            }
        }
        .frame(minWidth: 440, minHeight: 480)
    }

    @ViewBuilder
    private func presetThumbnail(_ preset: WallpaperPreset) -> some View {
        Canvas { context, size in
            let dotSpacing: CGFloat = 12
            let dotRadius: CGFloat = 2

            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(preset.baseColor)
            )

            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    let rect = CGRect(
                        x: x - dotRadius,
                        y: y - dotRadius,
                        width: dotRadius * 2,
                        height: dotRadius * 2
                    )
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(preset.dotColor.opacity(0.3))
                    )
                    x += dotSpacing
                }
                y += dotSpacing
            }
        }
    }
}

// MARK: - Wallpaper Tile

private struct WallpaperTile<Content: View>: View {
    let isSelected: Bool
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 4) {
            content()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor),
                                lineWidth: isSelected ? 2 : 1)
                }
            Text(label)
                .font(.caption2)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
    }
}
