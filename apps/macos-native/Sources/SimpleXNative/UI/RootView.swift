import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var notifications: NativeNotificationManager
    @AppStorage("desktopSidebarCollapsed") private var sidebarCollapsed = false

    private var accentColor: Color {
        switch model.settingsSnapshot.accentColorName {
        case "blue": .blue
        case "purple": .purple
        case "pink": .pink
        case "red": .red
        case "orange": .orange
        case "yellow": .yellow
        case "green": .green
        case "mint": .mint
        case "teal": .teal
        case "cyan": .cyan
        case "indigo": .indigo
        default: .accentColor
        }
    }

    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { sidebarCollapsed ? .detailOnly : .all },
            set: { sidebarCollapsed = $0 == .detailOnly }
        )
    }

    var body: some View {
        Group {
            if let stage = model.onboardingStage {
                onboardingView(for: stage)
            } else {
                switch model.phase {
                case .locked, .opening:
                    UnlockView(model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.background)
                case .ready, .failed:
                ZStack {
                    NavigationSplitView(columnVisibility: columnVisibility) {
                        SidebarView(model: model)
                            .navigationSplitViewColumnWidth(min: 240, ideal: 320, max: 480)
                    } detail: {
                        ConversationView(model: model)
                            .navigationSplitViewColumnWidth(min: 520, ideal: 800)
                    }
                    .alert(AppIdentity.displayName, isPresented: Binding(
                        get: { if case .failed = model.phase { true } else { false } },
                        set: { if !$0 { model.phase = .ready } }
                    )) {
                        Button("OK") { model.phase = .ready }
                    } message: {
                        if case let .failed(message) = model.phase { Text(message) }
                    }

                    // App passcode lock overlay
                    if model.isAppLocked {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                        AppLockView(model: model)
                            .transition(.opacity)
                    }
                }
            }
            }
        }
        .alert("Stay Updated?", isPresented: $notifications.showingPermissionExplanation) {
            Button("Allow Notifications") {
                notifications.respondToPermissionExplanation(requestPermission: true)
            }
            Button("Not Now", role: .cancel) {
                notifications.respondToPermissionExplanation(requestPermission: false)
            }
        } message: {
            Text("Native Chat can use Mac notifications for messages, contact requests, and calls. You can choose how much detail appears in Settings.")
        }
        .sheet(isPresented: $model.featureCenterPresented) {
            PeopleAndDevicesView(model: model)
        }
        .sheet(isPresented: $model.showServersSummary) {
            ServersSummaryView(model: model)
        }
        .tint(accentColor)
        .environment(\.fontScale, model.settingsSnapshot.fontScale)
        .onReceive(NotificationCenter.default.publisher(for: .appDidResignActive)) { _ in
            model.lockApp()
        }
    }

    @ViewBuilder
    private func onboardingView(for stage: AppModel.OnboardingStage) -> some View {
        switch stage {
        case .simpleXInfo:
            SimpleXInfoView(model: model)
        case .createProfile:
            CreateFirstProfileView(model: model)
        case .complete:
            EmptyView()
        }
    }
}

private struct FontScaleKey: EnvironmentKey {
    static let defaultValue: Double = 1.0
}

extension EnvironmentValues {
    var fontScale: Double {
        get { self[FontScaleKey.self] }
        set { self[FontScaleKey.self] = newValue }
    }
}
