// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SimpleXNative",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(
            name: "CoreBridge",
            publicHeadersPath: "include",
            linkerSettings: [.linkedLibrary("dl")]
        ),
        .executableTarget(
            name: "SimpleXNative",
            dependencies: ["CoreBridge", "Sparkle"]
        ),
        .testTarget(
            name: "SimpleXNativeTests",
            dependencies: ["SimpleXNative", "CoreBridge"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
