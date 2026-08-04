import Foundation
import Testing
@testable import SimpleXNative

@Test func linkedDeviceListPreservesConnectionStates() throws {
    let json = #"{"result":{"type":"remoteHostList","remoteHosts":[{"remoteHostId":1,"hostDeviceName":"AJ’s iPhone","sessionState":{"type":"connected","sessionCode":"438 921"}},{"remoteHostId":2,"hostDeviceName":"Tablet","sessionState":{"type":"pendingConfirmation","sessionCode":"123 456"}},{"remoteHostId":3,"hostDeviceName":"Old phone","sessionState":{"type":"stopped"}}]}}"#

    let devices = try PeopleAndDevicesParser.linkedDevices(from: Data(json.utf8))

    #expect(devices.count == 3)
    #expect(devices[0] == LinkedDevice(id: 1, name: "AJ’s iPhone", state: .connected(code: "438 921")))
    #expect(devices[1] == LinkedDevice(id: 2, name: "Tablet", state: .pendingConfirmation(code: "123 456")))
    #expect(devices[2] == LinkedDevice(id: 3, name: "Old phone", state: .stopped(reason: nil)))
}

@Test func newPairingStartsWithAnInvitation() throws {
    let json = #"{"result":{"type":"remoteHostStarted","remoteHost_":null,"invitation":"simplex:/xrcp#/?v=1&data=test","localAddrs":[],"ctrlPort":"52230"}}"#

    let pairing = try PeopleAndDevicesParser.pairing(from: Data(json.utf8))

    #expect(pairing.remoteHostID == nil)
    #expect(pairing.invitation == "simplex:/xrcp#/?v=1&data=test")
    #expect(pairing.sessionCode == nil)
}

@Test func knownPhoneReconnectUsesMulticastDiscovery() {
    #expect(PeopleAndDevicesParser.startRemoteHostCommand(nil) == "/start remote host new")
    #expect(PeopleAndDevicesParser.startRemoteHostCommand(17) == "/start remote host 17 multicast=on")
}

@Test func pairingSessionCodeEventIsRecognized() {
    let json = #"{"result":{"type":"remoteHostSessionCode","remoteHost_":{"remoteHostId":4,"hostDeviceName":"iPhone","sessionState":{"type":"pendingConfirmation","sessionCode":"864 209"}},"sessionCode":"864 209"}}"#

    let event = PeopleAndDevicesParser.linkedDeviceEvent(from: Data(json.utf8))

    #expect(event == .sessionCode(
        device: LinkedDevice(id: 4, name: "iPhone", state: .pendingConfirmation(code: "864 209")),
        code: "864 209"
    ))
}

@Test func connectedAndStoppedEventsDriveTheLinkedDeviceLifecycle() {
    let connectedJSON = #"{"result":{"type":"remoteHostConnected","remoteHost":{"remoteHostId":9,"hostDeviceName":"Phone","sessionState":{"type":"connected","sessionCode":"111 222"}}}}"#
    let stoppedJSON = #"{"result":{"type":"remoteHostStopped","remoteHostId_":9,"rhsState":{"type":"connected","sessionCode":"111 222"},"rhStopReason":{"type":"disconnected"}}}"#

    #expect(PeopleAndDevicesParser.linkedDeviceEvent(from: Data(connectedJSON.utf8)) == .connected(
        LinkedDevice(id: 9, name: "Phone", state: .connected(code: "111 222"))
    ))
    #expect(PeopleAndDevicesParser.linkedDeviceEvent(from: Data(stoppedJSON.utf8)) == .stopped(
        remoteHostID: 9,
        reason: nil
    ))
}

@Test func ordinaryChatEventsAreNotConsumedByLinkedMode() {
    let json = #"{"result":{"type":"newChatItems","user":{"userId":1},"chatItems":[]}}"#

    #expect(PeopleAndDevicesParser.linkedDeviceEvent(from: Data(json.utf8)) == .ignored)
}

@Test func remoteAttachmentResponsesPreserveEncryptionMetadata() throws {
    let json = #"{"result":{"type":"remoteFileStored","remoteHostId":7,"remoteFileSource":{"filePath":"remote/asset.jpg","cryptoArgs":{"fileKey":"key","fileNonce":"nonce"}}}}"#

    let file = try PeopleAndDevicesParser.storedRemoteFile(from: Data(json.utf8))
    let requestJSON = try PeopleAndDevicesParser.remoteFileJSON(
        userID: 3,
        fileID: 44,
        sent: false,
        fileSource: file
    )
    let request = try #require(JSONSerialization.jsonObject(with: Data(requestJSON.utf8)) as? [String: Any])
    let source = try #require(request["fileSource"] as? [String: Any])
    let crypto = try #require(source["cryptoArgs"] as? [String: Any])

    #expect(file == NativeCryptoFile(
        filePath: "remote/asset.jpg",
        cryptoArgs: NativeCryptoFileArgs(fileKey: "key", fileNonce: "nonce")
    ))
    #expect((request["userId"] as? NSNumber)?.int64Value == 3)
    #expect((request["fileId"] as? NSNumber)?.int64Value == 44)
    #expect(request["sent"] as? Bool == false)
    #expect(source["filePath"] as? String == "remote/asset.jpg")
    #expect(crypto["fileKey"] as? String == "key")
    #expect(crypto["fileNonce"] as? String == "nonce")
}
