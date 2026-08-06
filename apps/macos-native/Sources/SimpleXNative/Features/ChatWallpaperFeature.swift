import AppKit
import Foundation
import SwiftUI

// MARK: - Wallpaper Type

enum ChatWallpaperType: Codable, Equatable, Sendable {
    case none
    case preset(String)
    case image(String)
    case color(String)

    var storageTag: String {
        switch self {
        case .none: "none"
        case .preset(let name): "preset:\(name)"
        case .image(let file): "image:\(file)"
        case .color(let hex): "color:\(hex)"
        }
    }
}

// MARK: - Wallpaper Settings

struct ChatWallpaperSettings: Codable, Equatable, Sendable {
    var type: ChatWallpaperType
    var scale: Double
    var tintColor: String?

    static let `default` = ChatWallpaperSettings(type: .none, scale: 1.0, tintColor: nil)

    var isNone: Bool { type == .none }
}

// MARK: - Preset Definition

struct WallpaperPreset: Identifiable, Sendable {
    let id: String
    let name: String
    let baseColor: Color
    let dotColor: Color
}

enum WallpaperPresets {
    static let all: [WallpaperPreset] = [
        WallpaperPreset(
            id: "warm",
            name: "Warm",
            baseColor: Color(red: 1.0, green: 0.95, blue: 0.9),
            dotColor: Color(red: 1.0, green: 0.6, blue: 0.4)
        ),
        WallpaperPreset(
            id: "cool",
            name: "Cool",
            baseColor: Color(red: 0.9, green: 0.95, blue: 1.0),
            dotColor: Color(red: 0.3, green: 0.6, blue: 0.9)
        ),
        WallpaperPreset(
            id: "nature",
            name: "Nature",
            baseColor: Color(red: 0.92, green: 0.97, blue: 0.92),
            dotColor: Color(red: 0.3, green: 0.7, blue: 0.3)
        ),
        WallpaperPreset(
            id: "sunset",
            name: "Sunset",
            baseColor: Color(red: 1.0, green: 0.93, blue: 0.88),
            dotColor: Color(red: 0.95, green: 0.5, blue: 0.3)
        ),
        WallpaperPreset(
            id: "ocean",
            name: "Ocean",
            baseColor: Color(red: 0.88, green: 0.93, blue: 1.0),
            dotColor: Color(red: 0.2, green: 0.4, blue: 0.8)
        ),
        WallpaperPreset(
            id: "forest",
            name: "Forest",
            baseColor: Color(red: 0.88, green: 0.95, blue: 0.88),
            dotColor: Color(red: 0.15, green: 0.45, blue: 0.2)
        ),
    ]

    static func preset(for id: String) -> WallpaperPreset? {
        all.first { $0.id == id }
    }
}

// MARK: - Wallpaper Persistence

enum ChatWallpaperStore {
    private static let defaults = UserDefaults.standard
    private static let keyPrefix = "wallpaper_"

    static func settings(for chatID: String) -> ChatWallpaperSettings {
        let key = keyPrefix + chatID
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(ChatWallpaperSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    static func save(_ settings: ChatWallpaperSettings, for chatID: String) {
        let key = keyPrefix + chatID
        if settings.isNone {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: key)
        }
    }

    static var wallpaperDirectory: URL {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NativeChat/wallpapers", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport
    }

    static func saveCustomImage(from sourceURL: URL) -> String? {
        let fileName = "\(UUID().uuidString).\(sourceURL.pathExtension.isEmpty ? "jpg" : sourceURL.pathExtension)"
        let destination = wallpaperDirectory.appendingPathComponent(fileName)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            return fileName
        } catch {
            return nil
        }
    }

    static func customImageURL(fileName: String) -> URL {
        wallpaperDirectory.appendingPathComponent(fileName)
    }

    static func deleteCustomImage(fileName: String) {
        let url = wallpaperDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Wallpaper Background View

struct ChatWallpaperBackground: View {
    let settings: ChatWallpaperSettings

    var body: some View {
        switch settings.type {
        case .none:
            Color.clear
        case .preset(let name):
            presetBackground(name: name)
        case .image(let fileName):
            customImageBackground(fileName: fileName)
        case .color(let hex):
            Color(hex: hex).opacity(0.3)
        }
    }

    @ViewBuilder
    private func presetBackground(name: String) -> some View {
        if let preset = WallpaperPresets.preset(for: name) {
            Canvas { context, size in
                let dotSpacing: CGFloat = 32.0 * settings.scale
                let dotRadius: CGFloat = 4.0 * settings.scale

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
                            with: .color(preset.dotColor.opacity(0.25))
                        )
                        x += dotSpacing
                    }
                    y += dotSpacing
                }
            }
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func customImageBackground(fileName: String) -> some View {
        let url = ChatWallpaperStore.customImageURL(fileName: fileName)
        if let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .scaleEffect(settings.scale)
                .opacity(0.4)
                .clipped()
        } else {
            Color.clear
        }
    }
}

// MARK: - Hex Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
