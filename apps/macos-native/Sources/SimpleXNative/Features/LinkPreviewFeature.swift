import AppKit
import Foundation

actor LinkPreviewFetcher {
    static let shared = LinkPreviewFetcher()

    private var activeTask: Task<NativeLinkPreview?, Never>?
    private var activeURL: String?

    func fetch(for urlString: String) async -> NativeLinkPreview? {
        guard let url = NativeMessageLink.standaloneURL(in: urlString),
              let host = url.host(), !host.isEmpty else {
            return nil
        }

        if activeURL == urlString, let activeTask {
            return await activeTask.value
        }

        activeTask?.cancel()
        activeURL = urlString

        let task = Task<NativeLinkPreview?, Never> {
            defer {
                if activeURL == urlString {
                    activeTask = nil
                    activeURL = nil
                }
            }

            guard let htmlData = await fetchHTML(from: url),
                  let html = String(data: htmlData, encoding: .utf8) else {
                return nil
            }

            try? Task.checkCancellation()

            let title = extractMetaContent(property: "og:title", from: html)
                ?? extractTitleTag(from: html)
                ?? ""
            let description = extractMetaContent(property: "og:description", from: html)
                ?? extractMetaContent(name: "description", from: html)
                ?? ""
            guard !title.isEmpty || !description.isEmpty else { return nil }

            try? Task.checkCancellation()

            let imageURLString = extractMetaContent(property: "og:image", from: html)
            let imageData = imageURLString.flatMap { imageURLString -> Data? in
                guard let imageURL = URL(string: imageURLString, relativeTo: url) else { return nil }
                return Task.isCancelled ? nil : fetchImageDataSync(from: imageURL)
            }
            let base64Image = imageData.flatMap { compressToJPEGBase64($0) }

            try? Task.checkCancellation()

            return NativeLinkPreview(
                uri: url.absoluteString,
                title: title,
                description: description,
                image: base64Image,
                videoDuration: nil
            )
        }
        activeTask = task
        return await task.value
    }

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
        activeURL = nil
    }

    private func fetchHTML(from url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled else { return nil }
            return data
        } catch {
            return nil
        }
    }

    private func fetchImageDataSync(from url: URL) -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        let semaphore = DispatchSemaphore(value: 0)
        var result: Data?
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }
            guard let data, let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else { return }
            result = data
        }
        task.resume()
        semaphore.wait()
        return result
    }

    nonisolated private func compressToJPEGBase64(_ data: Data) -> String? {
        guard let image = NSImage(data: data), let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }

        let maxDimension: CGFloat = 192
        let originalSize = bitmap.size
        let widthRatio = maxDimension / originalSize.width
        let heightRatio = maxDimension / originalSize.height
        let ratio = min(widthRatio, heightRatio, 1.0)
        let scaledSize = NSSize(
            width: originalSize.width * ratio,
            height: originalSize.height * ratio
        )

        let scaledRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(scaledSize.width),
            pixelsHigh: Int(scaledSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let scaledRep else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: scaledRep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: scaledSize),
            from: .zero,
            operation: .copy,
            fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()

        let maxSize = 14000
        for quality in [0.6, 0.4, 0.25, 0.15] {
            guard let jpegData = scaledRep.representation(using: .jpeg, properties: [.compressionFactor: quality]),
                  jpegData.count <= maxSize else { continue }
            return jpegData.base64EncodedString()
        }
        return scaledRep.representation(using: .jpeg, properties: [.compressionFactor: 0.1])?
            .base64EncodedString()
    }

    nonisolated private func extractMetaContent(property: String, from html: String) -> String? {
        let patterns = [
            #"<meta\s+property="\#(property)"\s+content="([^"]+)""#,
            #"<meta\s+content="([^"]+)"\s+property="\#(property)""#,
        ]
        for pattern in patterns {
            if let match = html.range(of: pattern, options: .regularExpression) {
                let matched = String(html[match])
                if let contentStart = matched.range(of: "content=\""),
                   let contentEnd = matched[contentStart.upperBound...].range(of: "\"") {
                    return String(matched[contentStart.upperBound..<contentEnd.lowerBound])
                }
            }
        }
        return nil
    }

    nonisolated private func extractMetaContent(name: String, from html: String) -> String? {
        let patterns = [
            #"<meta\s+name="\#(name)"\s+content="([^"]+)""#,
            #"<meta\s+content="([^"]+)"\s+name="\#(name)""#,
        ]
        for pattern in patterns {
            if let match = html.range(of: pattern, options: .regularExpression) {
                let matched = String(html[match])
                if let contentStart = matched.range(of: "content=\""),
                   let contentEnd = matched[contentStart.upperBound...].range(of: "\"") {
                    return String(matched[contentStart.upperBound..<contentEnd.lowerBound])
                }
            }
        }
        return nil
    }

    nonisolated private func extractTitleTag(from html: String) -> String? {
        guard let open = html.range(of: "<title[^>]*>", options: .regularExpression),
              let close = html[open.upperBound...].range(of: "</title>") else { return nil }
        return String(html[open.upperBound..<close.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
