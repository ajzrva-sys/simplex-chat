import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import SimpleXNative

@MainActor
@Test func droppedScreenshotDataBecomesAStagedPNGAttachment() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let data = try #require(testScreenshotPNGData())
    let provider = NSItemProvider()
    provider.suggestedName = "Screenshot 2026-08-03 at 2.33.12 PM"
    provider.registerDataRepresentation(
        forTypeIdentifier: UTType.png.identifier,
        visibility: .all
    ) { completion in
        completion(data, nil)
        return nil
    }

    let result = await withCheckedContinuation { continuation in
        let accepted = DroppedAttachmentLoader.beginLoading(
            [provider],
            stagingDirectory: directory,
            completion: { result in continuation.resume(returning: result) }
        )
        #expect(accepted)
    }

    let url = try #require(result.urls.first)
    #expect(result.urls.count == 1)
    #expect(result.failures.isEmpty)
    #expect(url.pathExtension == "png")
    #expect(url.lastPathComponent.contains("Screenshot 2026-08-03 at 2.33.12 PM"))
    #expect(try Data(contentsOf: url) == data)

    let attachment = try PendingAttachment.stage(url: url)
    #expect(attachment.kind == .image)
}

@MainActor
@Test func droppedScreenshotProvidersPreserveTheirOrder() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let data = try #require(testScreenshotPNGData())

    let providers = ["First Screenshot", "Second Screenshot"].map { name in
        let provider = NSItemProvider()
        provider.suggestedName = name
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.png.identifier,
            visibility: .all
        ) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }

    let result = await withCheckedContinuation { continuation in
        #expect(DroppedAttachmentLoader.beginLoading(
            providers,
            stagingDirectory: directory,
            completion: { result in continuation.resume(returning: result) }
        ))
    }

    #expect(result.urls.map(\.lastPathComponent).map { $0.contains("First Screenshot") } == [true, false])
    #expect(result.urls[1].lastPathComponent.contains("Second Screenshot"))
}

@MainActor
@Test func unsupportedDropPayloadIsRejectedImmediately() {
    let provider = NSItemProvider(object: "not an attachment" as NSString)
    let accepted = DroppedAttachmentLoader.beginLoading([provider]) { _ in
        Issue.record("Unsupported payload should not start loading")
    }
    #expect(!accepted)
}

private func testScreenshotPNGData() -> Data? {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 8,
        pixelsHigh: 8,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }
    guard let bytes = bitmap.bitmapData else { return nil }
    for y in 0..<8 {
        for x in 0..<8 {
            let offset = y * bitmap.bytesPerRow + x * 4
            bytes[offset] = 0
            bytes[offset + 1] = 122
            bytes[offset + 2] = 255
            bytes[offset + 3] = 255
        }
    }
    return bitmap.representation(using: .png, properties: [:])
}
