import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: GenerateAppIcon <iconset-directory>\n", stderr)
    exit(2)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(size: Int) throws -> Data {
    let canvas = CGFloat(size)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: size * 4,
        bitsPerPixel: 32
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }

    let bounds = NSRect(x: 0, y: 0, width: canvas, height: canvas)
    let radius = canvas * 0.22
    let background = NSBezierPath(roundedRect: bounds.insetBy(dx: canvas * 0.03, dy: canvas * 0.03), xRadius: radius, yRadius: radius)
    NSGradient(colors: [
        NSColor(red: 0.32, green: 0.66, blue: 1, alpha: 1),
        NSColor(red: 0.14, green: 0.33, blue: 0.85, alpha: 1),
    ])?.draw(in: background, angle: -55)

    let bubbleRect = NSRect(x: canvas * 0.15, y: canvas * 0.27, width: canvas * 0.70, height: canvas * 0.46)
    let bubble = NSBezierPath(roundedRect: bubbleRect, xRadius: canvas * 0.10, yRadius: canvas * 0.10)
    NSColor.white.setFill()
    bubble.fill()

    let tail = NSBezierPath()
    tail.move(to: NSPoint(x: canvas * 0.34, y: canvas * 0.30))
    tail.line(to: NSPoint(x: canvas * 0.27, y: canvas * 0.17))
    tail.line(to: NSPoint(x: canvas * 0.47, y: canvas * 0.29))
    tail.close()
    tail.fill()

    NSColor(red: 0.18, green: 0.41, blue: 0.91, alpha: 1).setFill()
    for x in [0.36, 0.50, 0.64] {
        NSBezierPath(ovalIn: NSRect(
            x: canvas * x - canvas * 0.035,
            y: canvas * 0.47,
            width: canvas * 0.07,
            height: canvas * 0.07
        )).fill()
    }

    context.flushGraphics()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return png
}

for size in [16, 32, 128, 256, 512] {
    try render(size: size).write(to: output.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size: size * 2).write(to: output.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
