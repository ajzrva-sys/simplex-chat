import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct DroppedAttachmentLoadResult: Sendable {
    let urls: [URL]
    let failures: [String]
}

enum DroppedAttachmentLoader {
    static let supportedContentTypes: [UTType] = [.fileURL, .image]

    @MainActor
    @discardableResult
    static func beginLoading(
        _ providers: [NSItemProvider],
        stagingDirectory: URL = defaultStagingDirectory,
        completion: @escaping @MainActor (DroppedAttachmentLoadResult) -> Void
    ) -> Bool {
        let candidates = providers.compactMap(candidate(for:))
        guard !candidates.isEmpty else { return false }

        let batch = DroppedAttachmentBatch(count: candidates.count, completion: completion)
        for (index, candidate) in candidates.enumerated() {
            switch candidate {
            case let .fileURL(provider, identifier):
                beginLoadingFileURL(
                    from: provider,
                    identifier: identifier,
                    stagingDirectory: stagingDirectory
                ) { result in
                    Task { @MainActor in batch.complete(index: index, with: result) }
                }
            case let .image(provider, identifier):
                beginLoadingImage(
                    from: provider,
                    identifier: identifier,
                    stagingDirectory: stagingDirectory
                ) { result in
                    Task { @MainActor in batch.complete(index: index, with: result) }
                }
            }
        }
        return true
    }

    private enum Candidate {
        case fileURL(NSItemProvider, String)
        case image(NSItemProvider, String)
    }

    private static var defaultStagingDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("NativeChat", isDirectory: true)
            .appendingPathComponent("DroppedAttachments", isDirectory: true)
    }

    private static func candidate(for provider: NSItemProvider) -> Candidate? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return .fileURL(provider, UTType.fileURL.identifier)
        }

        if let identifier = provider.registeredTypeIdentifiers.first(where: {
            UTType($0)?.conforms(to: .image) == true
        }) {
            return .image(provider, identifier)
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            return .image(provider, UTType.image.identifier)
        }
        return nil
    }

    private static func beginLoadingFileURL(
        from provider: NSItemProvider,
        identifier: String,
        stagingDirectory: URL,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        provider.loadItem(forTypeIdentifier: identifier, options: nil) { item, error in
            if let error {
                completion(.failure(error))
                return
            }

            do {
                let url = try fileURL(from: item)
                guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
                    throw DroppedAttachmentError.fileUnavailable(provider.suggestedName)
                }
                if isEphemeral(url) {
                    let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
                        ?? UTType(filenameExtension: url.pathExtension)
                        ?? .data
                    completion(.success(try copyFile(
                        at: url,
                        suggestedName: provider.suggestedName,
                        contentType: type,
                        to: stagingDirectory
                    )))
                } else {
                    completion(.success(url))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }

    @MainActor
    private static func beginLoadingImage(
        from provider: NSItemProvider,
        identifier: String,
        stagingDirectory: URL,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let contentType = UTType(identifier) ?? .image
        let suggestedName = provider.suggestedName
        let race = DroppedImageRepresentationRace(
            suggestedName: suggestedName,
            contentType: contentType,
            stagingDirectory: stagingDirectory,
            completion: completion
        )

        provider.loadFileRepresentation(forTypeIdentifier: identifier) { url, error in
            let result: Result<URL, Error>
            if let url {
                do {
                    result = .success(try copyFile(
                        at: url,
                        suggestedName: suggestedName,
                        contentType: contentType,
                        to: stagingDirectory
                    ))
                } catch {
                    result = .failure(error)
                }
            } else {
                result = .failure(error ?? DroppedAttachmentError.fileUnavailable(suggestedName))
            }
            Task { @MainActor in race.completeFileRepresentation(with: result) }
        }

        provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, error in
            let result: Result<Data, Error>
            if let data, !data.isEmpty {
                result = .success(data)
            } else {
                result = .failure(error ?? DroppedAttachmentError.imageUnavailable(suggestedName))
            }
            Task { @MainActor in race.completeDataRepresentation(with: result) }
        }
    }

    private static func fileURL(from item: NSSecureCoding?) throws -> URL {
        if let url = item as? URL { return url }
        if let data = item as? Data,
           let url = URL(dataRepresentation: data, relativeTo: nil) {
            return url
        }
        if let string = item as? String, let url = URL(string: string) {
            return url
        }
        throw DroppedAttachmentError.fileUnavailable(nil)
    }

    fileprivate static func writeImageData(
        _ data: Data,
        suggestedName: String?,
        contentType: UTType,
        to stagingDirectory: URL
    ) throws -> URL {
        let detectedType: UTType? = CGImageSourceCreateWithData(data as CFData, nil)
            .flatMap(CGImageSourceGetType)
            .flatMap { UTType($0 as String) }
        let resolvedType = detectedType ?? contentType
        let destination = try uniqueDestination(
            suggestedName: suggestedName,
            fallbackName: "Screenshot",
            contentType: resolvedType,
            stagingDirectory: stagingDirectory
        )
        try data.write(to: destination, options: .atomic)
        return destination
    }

    private static func copyFile(
        at source: URL,
        suggestedName: String?,
        contentType: UTType,
        to stagingDirectory: URL
    ) throws -> URL {
        let destination = try uniqueDestination(
            suggestedName: suggestedName,
            fallbackName: source.lastPathComponent,
            contentType: contentType,
            stagingDirectory: stagingDirectory
        )
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    private static func uniqueDestination(
        suggestedName: String?,
        fallbackName: String,
        contentType: UTType,
        stagingDirectory: URL
    ) throws -> URL {
        try FileManager.default.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: true
        )

        let rawName = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeName = URL(fileURLWithPath: rawName?.isEmpty == false ? rawName! : fallbackName)
            .lastPathComponent
        var fileName = safeName.isEmpty ? "Screenshot" : safeName
        if URL(fileURLWithPath: fileName).pathExtension.isEmpty,
           let fileExtension = contentType.preferredFilenameExtension {
            fileName += ".\(fileExtension)"
        }
        return stagingDirectory.appendingPathComponent("\(UUID().uuidString)-\(fileName)")
    }

    private static func isEphemeral(_ url: URL) -> Bool {
        let filePath = url.resolvingSymlinksInPath().standardizedFileURL.path
        let temporaryPath = FileManager.default.temporaryDirectory
            .resolvingSymlinksInPath()
            .standardizedFileURL.path
        return filePath == temporaryPath || filePath.hasPrefix(temporaryPath + "/")
    }
}

@MainActor
private final class DroppedAttachmentBatch {
    private var remaining: Int
    private var results: [Int: Result<URL, Error>] = [:]
    private let completion: @MainActor (DroppedAttachmentLoadResult) -> Void

    init(count: Int, completion: @escaping @MainActor (DroppedAttachmentLoadResult) -> Void) {
        remaining = count
        self.completion = completion
    }

    func complete(index: Int, with result: Result<URL, Error>) {
        guard results[index] == nil else { return }
        results[index] = result
        remaining -= 1
        guard remaining == 0 else { return }

        var urls: [URL] = []
        var failures: [String] = []
        for index in results.keys.sorted() {
            switch results[index] {
            case let .success(url): urls.append(url)
            case let .failure(error): failures.append(error.localizedDescription)
            case nil: break
            }
        }
        completion(DroppedAttachmentLoadResult(urls: urls, failures: failures))
    }
}

@MainActor
private final class DroppedImageRepresentationRace {
    private let suggestedName: String?
    private let contentType: UTType
    private let stagingDirectory: URL
    private let completion: (Result<URL, Error>) -> Void
    private var fileResult: Result<URL, Error>?
    private var dataResult: Result<Data, Error>?

    init(
        suggestedName: String?,
        contentType: UTType,
        stagingDirectory: URL,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        self.suggestedName = suggestedName
        self.contentType = contentType
        self.stagingDirectory = stagingDirectory
        self.completion = completion
    }

    func completeFileRepresentation(with result: Result<URL, Error>) {
        fileResult = result
        finishIfReady()
    }

    func completeDataRepresentation(with result: Result<Data, Error>) {
        dataResult = result
        finishIfReady()
    }

    private func finishIfReady() {
        guard let fileResult, let dataResult else { return }
        if case let .success(url) = fileResult {
            completion(.success(url))
            return
        }
        if case let .success(data) = dataResult {
            do {
                completion(.success(try DroppedAttachmentLoader.writeImageData(
                    data,
                    suggestedName: suggestedName,
                    contentType: contentType,
                    to: stagingDirectory
                )))
            } catch {
                completion(.failure(error))
            }
            return
        }
        if case let .failure(error) = dataResult {
            completion(.failure(error))
        }
    }
}

private enum DroppedAttachmentError: LocalizedError {
    case fileUnavailable(String?)
    case imageUnavailable(String?)

    var errorDescription: String? {
        switch self {
        case let .fileUnavailable(name):
            "\(name ?? "The dropped file") could not be read."
        case let .imageUnavailable(name):
            "\(name ?? "The dropped image") could not be imported."
        }
    }
}
