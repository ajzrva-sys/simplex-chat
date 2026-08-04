import Foundation
import Testing
@testable import SimpleXNative

@Test func migrationFileLinksAcceptNativeAndWebForms() {
    #expect(DeviceMigrationTransferParser.isFileLink("simplex:/file#/?v=1"))
    #expect(DeviceMigrationTransferParser.isFileLink(" https://simplex.chat/file#/?v=1\n"))
    #expect(!DeviceMigrationTransferParser.isFileLink("https://example.com/archive.zip"))
}

@Test func migrationUploadStartParsesFileMetadata() throws {
    let json = #"{"result":{"type":"sndStandaloneFileCreated","fileTransferMeta":{"fileId":42,"fileSize":8192}}}"#
    let started = try DeviceMigrationTransferParser.uploadStarted(Data(json.utf8))
    #expect(started.fileID == 42)
    #expect(started.total == 8192)
}

@Test func migrationDownloadStartParsesFileIdentifier() throws {
    let json = #"{"result":{"type":"rcvStandaloneFileCreated","rcvFileTransfer":{"fileId":91}}}"#
    #expect(try DeviceMigrationTransferParser.downloadStarted(Data(json.utf8)) == 91)
}

@Test func migrationTransferParserReportsUploadCompletionLink() {
    let json = #"{"result":{"type":"sndStandaloneFileComplete","fileTransferMeta":{"fileId":7},"rcvURIs":["simplex:/file#/?v=1"]}}"#
    #expect(
        DeviceMigrationTransferParser.event(Data(json.utf8))
            == .sendComplete(fileID: 7, link: "simplex:/file#/?v=1")
    )
}

@Test func migrationTransferParserReportsDownloadProgress() {
    let json = #"{"result":{"type":"rcvFileProgressXFTP","receivedSize":4096,"totalSize":16384,"rcvFileTransfer":{"fileId":11}}}"#
    #expect(
        DeviceMigrationTransferParser.event(Data(json.utf8))
            == .receiveProgress(bytes: 4096, total: 16384, fileID: 11)
    )
}

@Test func migrationCommandsMatchTheCoreProtocol() {
    #expect(
        DeviceMigrationTransferParser.uploadCommand(userID: 5, fileName: "archive.zip")
            == "/_upload 5 archive.zip"
    )
    #expect(
        DeviceMigrationTransferParser.downloadCommand(
            userID: 5,
            link: "simplex:/file#/?v=1",
            fileName: "archive.zip"
        ) == "/_download 5 simplex:/file#/?v=1 archive.zip"
    )
}
