import Foundation

struct AppLegalInfo: Equatable, Sendable {
    static let defaultRepositoryURL = URL(string: "https://github.com/ajzrva-sys/simplex-chat")!

    let version: String
    let build: String
    let sourceRevision: String?
    let sourceURL: URL
    let isDevelopmentBuild: Bool

    init(infoDictionary: [String: Any]) {
        version = infoDictionary["CFBundleShortVersionString"] as? String ?? "Development"
        build = infoDictionary["CFBundleVersion"] as? String ?? "0"
        sourceRevision = infoDictionary["NativeChatSourceRevision"] as? String
        isDevelopmentBuild = infoDictionary["NativeChatDevelopmentBuild"] as? Bool ?? true

        if let value = infoDictionary["NativeChatSourceURL"] as? String,
           let url = URL(string: value) {
            sourceURL = url
        } else {
            sourceURL = Self.defaultRepositoryURL
        }
    }

    static var current: AppLegalInfo {
        AppLegalInfo(infoDictionary: Bundle.main.infoDictionary ?? [:])
    }

    var versionDescription: String {
        "Version \(version) (\(build))"
    }

    var sourceDescription: String {
        if isDevelopmentBuild {
            return "Development build. The source link opens the active macOS branch."
        }
        guard let sourceRevision, !sourceRevision.isEmpty else {
            return "Source code for this build is available on GitHub."
        }
        return "Source revision \(sourceRevision.prefix(12))"
    }
}

enum BundledLegalDocument: String, Identifiable {
    case license
    case notice
    case modifications

    var id: Self { self }

    var title: String {
        switch self {
        case .license: "GNU AGPL v3"
        case .notice: "Copyright and Warranty Notice"
        case .modifications: "Native Chat Modifications"
        }
    }

    var resourceName: String {
        switch self {
        case .license: "AGPL-3.0"
        case .notice: "NOTICE"
        case .modifications: "MODIFICATIONS"
        }
    }

    var resourceExtension: String {
        switch self {
        case .modifications: "md"
        case .license, .notice: "txt"
        }
    }

    func text(in bundle: Bundle = .main) -> String {
        guard let url = bundle.url(forResource: resourceName, withExtension: resourceExtension),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "This document is not available in this development build."
        }
        return text
    }
}

struct ThirdPartyLicense: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let url: URL

    var text: String {
        (try? String(contentsOf: url, encoding: .utf8))
            ?? "This license file could not be read."
    }

    static func bundled(in bundle: Bundle = .main) -> [ThirdPartyLicense] {
        guard let root = bundle.resourceURL?.appendingPathComponent("ThirdPartyLicenses", isDirectory: true),
              let enumerator = FileManager.default.enumerator(
                  at: root,
                  includingPropertiesForKeys: [.isRegularFileKey],
                  options: [.skipsHiddenFiles]
              ) else { return [] }

        return enumerator.compactMap { item in
            guard let url = item as? URL,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                return nil
            }
            let relativePath = String(url.path.dropFirst(root.path.count + 1))
            let components = relativePath.split(separator: "/").map(String.init)
            let name = components.dropLast().isEmpty
                ? url.deletingPathExtension().lastPathComponent
                : components.dropLast().joined(separator: " / ")
            return ThirdPartyLicense(id: relativePath, name: name, url: url)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
