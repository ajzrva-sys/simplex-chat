import SwiftUI

struct ComposeLinkPreviewView: View {
    let preview: NativeLinkPreview?
    let isLoading: Bool
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                Text("Fetching link preview…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let preview {
                if let image = NativeChatParser.image(from: preview.image) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "link")
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(preview.title.isEmpty ? preview.uri : preview.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    if !preview.title.isEmpty {
                        Text(preview.displayHost)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }

            Button(action: cancel) {
                Image(systemName: "xmark")
                    .frame(width: 24, height: 24)
            }
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
            .buttonStyle(.borderless)
            .help("Remove link preview")
            .accessibilityLabel("Remove link preview")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
    }
}
