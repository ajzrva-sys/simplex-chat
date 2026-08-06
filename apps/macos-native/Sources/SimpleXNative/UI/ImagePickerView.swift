import AppKit
import SwiftUI

struct ImagePickerView: View {
    let onImageSelected: (NSImage) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Choose Profile Image")
                .font(.headline)

            Button("Choose from Finder…") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.image]
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = false
                panel.title = "Select Profile Image"
                if panel.runModal() == .OK, let url = panel.url,
                   let image = NSImage(contentsOf: url) {
                    onImageSelected(image)
                    dismiss()
                }
            }
            .buttonStyle(.borderedProminent)

            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding()
        .frame(width: 280)
    }
}

func cropToSquare(_ image: NSImage) -> NSImage {
    let size = min(image.size.width, image.size.height)
    let origin = NSPoint(
        x: (image.size.width - size) / 2,
        y: (image.size.height - size) / 2
    )
    let cropped = NSImage(size: NSSize(width: size, height: size))
    cropped.lockFocus()
    image.draw(
        in: NSRect(origin: .zero, size: cropped.size),
        from: NSRect(origin: origin, size: NSSize(width: size, height: size)),
        operation: .copy,
        fraction: 1
    )
    cropped.unlockFocus()
    return cropped
}

func compressImageToBase64(_ image: NSImage, maxBytes: Int = 12500) -> String? {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else { return nil }

    var quality: CGFloat = 0.8
    var data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])

    // Reduce quality until under maxBytes
    while let d = data, d.count > maxBytes && quality > 0.1 {
        quality -= 0.1
        data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    guard let finalData = data else { return nil }
    return "data:image/jpeg;base64,\(finalData.base64EncodedString())"
}
