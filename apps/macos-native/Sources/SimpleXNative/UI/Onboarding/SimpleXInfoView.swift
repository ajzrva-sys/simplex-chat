import SwiftUI

struct SimpleXInfoView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)

                Text("Welcome to SimpleX")
                    .font(.largeTitle.weight(.bold))

                Text("Private and secure messaging. No phone number or identity required.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            VStack(spacing: 12) {
                FeatureRow(icon: "lock.fill", title: "End-to-end encrypted", description: "All messages are encrypted and only readable by you.")
                FeatureRow(icon: "eye.slash.fill", title: "No user identifiers", description: "No phone number, email, or username required to connect.")
                FeatureRow(icon: "network", title: "Decentralized", description: "Uses redundant relay servers for reliability.")
            }
            .frame(maxWidth: 400)

            Spacer()

            Button("Create Your Profile") {
                model.onboardingStage = .createProfile
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
