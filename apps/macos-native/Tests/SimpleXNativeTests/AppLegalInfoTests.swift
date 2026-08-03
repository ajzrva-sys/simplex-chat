import Foundation
import Testing
@testable import SimpleXNative

@Test func cleanBuildLegalInfoUsesExactSourceRevision() throws {
    let revision = "0123456789abcdef0123456789abcdef01234567"
    let sourceURL = try #require(URL(string: "https://github.com/ajzrva-sys/simplex-chat/tree/\(revision)"))
    let info = AppLegalInfo(infoDictionary: [
        "CFBundleShortVersionString": "0.2.1",
        "CFBundleVersion": "2",
        "NativeChatSourceRevision": revision,
        "NativeChatSourceURL": sourceURL.absoluteString,
        "NativeChatDevelopmentBuild": false,
    ])

    #expect(info.versionDescription == "Version 0.2.1 (2)")
    #expect(info.sourceURL == sourceURL)
    #expect(info.sourceDescription == "Source revision 0123456789ab")
    #expect(!info.isDevelopmentBuild)
}

@Test func developmentBuildLegalInfoIsClearlyIdentified() throws {
    let branchURL = try #require(URL(string: "https://github.com/ajzrva-sys/simplex-chat/tree/macos-native"))
    let info = AppLegalInfo(infoDictionary: [
        "NativeChatSourceURL": branchURL.absoluteString,
        "NativeChatDevelopmentBuild": true,
    ])

    #expect(info.sourceURL == branchURL)
    #expect(info.sourceDescription == "Development build. The source link opens the active macOS branch.")
    #expect(info.isDevelopmentBuild)
}

@Test func legalInfoFallsBackToPublicRepository() {
    let info = AppLegalInfo(infoDictionary: [:])

    #expect(info.sourceURL == AppLegalInfo.defaultRepositoryURL)
    #expect(info.isDevelopmentBuild)
}

@Test func thirdPartyLicenseNamesUseTheirDependencyPath() {
    let license = ThirdPartyLicense(
        id: "haskell/aeson-2.2.1.0/LICENSE",
        name: "haskell / aeson-2.2.1.0",
        url: URL(fileURLWithPath: "/tmp/LICENSE")
    )

    #expect(license.name == "haskell / aeson-2.2.1.0")
    #expect(license.id == "haskell/aeson-2.2.1.0/LICENSE")
}
