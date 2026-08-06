import Foundation
import Sparkle

enum UpdateChannel: String, Sendable, CaseIterable {
    case stable
    case beta
    case disabled

    var label: String {
        switch self {
        case .stable: "Stable"
        case .beta: "Beta"
        case .disabled: "Disabled"
        }
    }
}

final class AppUpdaterManager: NSObject, SPUUpdaterDelegate {
    private var updater: SPUUpdater?

    override init() {
        super.init()
        do {
            let userDriver = SPUStandardUserDriver(hostBundle: Bundle.main, delegate: nil)
            updater = try SPUUpdater(
                hostBundle: Bundle.main,
                applicationBundle: Bundle.main,
                userDriver: userDriver,
                delegate: self
            )
            try updater?.start()
        } catch {
            print("Failed to start updater: \(error)")
        }
    }

    func checkForUpdates() {
        updater?.checkForUpdates()
    }

    var canCheckForUpdates: Bool {
        updater?.canCheckForUpdates ?? false
    }

    // MARK: - SPUUpdaterDelegate

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        let channel = UserDefaults.standard.string(forKey: "nativeChat.updateChannel") ?? "stable"
        switch channel {
        case "beta": return ["beta"]
        default: return []
        }
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        "https://raw.githubusercontent.com/ajzrva-sys/simplex-chat/macos-native/appcast.xml"
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        print("Updater error: \(error)")
    }
}
