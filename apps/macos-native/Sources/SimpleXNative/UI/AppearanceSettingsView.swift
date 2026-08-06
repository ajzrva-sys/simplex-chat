import SwiftUI

struct AppearanceSettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private static let accentColors: [(name: String, color: Color)] = [
        ("default", .accentColor),
        ("blue", .blue),
        ("purple", .purple),
        ("pink", .pink),
        ("red", .red),
        ("orange", .orange),
        ("yellow", .yellow),
        ("green", .green),
        ("mint", .mint),
        ("teal", .teal),
        ("cyan", .cyan),
        ("indigo", .indigo),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Accent Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(Self.accentColors, id: \.name) { entry in
                            Button {
                                model.settingsSnapshot.accentColorName = entry.name
                                model.saveSettings()
                            } label: {
                                Circle()
                                    .fill(entry.color)
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        if model.settingsSnapshot.accentColorName == entry.name {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Font Size") {
                    HStack {
                        Text("A")
                            .font(.caption)
                        Slider(
                            value: Binding(
                                get: { model.settingsSnapshot.fontScale },
                                set: { model.settingsSnapshot.fontScale = $0 }
                            ),
                            in: 0.7...1.5,
                            step: 0.05
                        ) {
                            Text("Font Scale")
                        } minimumValueLabel: {
                            Text("A")
                                .font(.caption)
                        } maximumValueLabel: {
                            Text("A")
                                .font(.title3)
                        }
                        .onChange(of: model.settingsSnapshot.fontScale) { _, _ in
                            model.saveSettings()
                        }
                        Text(String(format: "%.0f%%", model.settingsSnapshot.fontScale * 100))
                            .font(.caption)
                            .monospacedDigit()
                            .frame(width: 40)
                    }
                }

                Section {
                    Text("Changes take effect immediately. Accent color applies to interactive elements throughout the app.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Appearance")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
        .frame(width: 440, height: 400)
    }
}
