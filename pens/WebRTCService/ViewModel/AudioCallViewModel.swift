import Foundation
import SwiftUI
import WebRTC


class AudioCallViewModel: ObservableObject {

    var _roomClient: RoomClient?

    // MARK: Room
    var _roomInfo: JoinResponseParam?

    // MARK: 信令
    var _webSocket: WebSocketClient?
    var _messageQueue = [String]()

    //MARK: WebRTC
    var _webRTCClient: WebRTCClient?

    func connectRoom(roomID: String) -> Void {
        dLog("connectToRoom");
        prepare();
        join(roomID: roomID)
    }

    private func prepare() {
        _roomClient = RoomClient();
        _webSocket = WebSocketClient();
        _webRTCClient = WebRTCClient();
    }

    func clear() {
        _roomClient = nil
        _webRTCClient = nil
        _webSocket = nil
    }
}

//MARK: 网络
extension AudioCallViewModel {
    func join(roomID: String) -> Void {
        guard let _roomClient = _roomClient else {
            return
        }
//        _roomClient.join(roomID: roomID)
        connectToWebSocket(roomId: roomID)
    }

    func disconnect() -> Void {
        guard let roomID = _roomInfo?.room_id,
            let userID = _roomInfo?.client_id,
            let roomClient = _roomClient,
            let webSocket = _webSocket,
            let webRTCClient = _webRTCClient else { return }

        roomClient.disconnect(roomID: roomID, userID: userID) { [weak self] in
            self?._roomInfo = nil
        }

        let message = ["type": "bye"]

        if let data = message.JSONData {
            webSocket.send(data: data)
        }
        webSocket.delegate = nil
        _roomInfo = nil

        webRTCClient.disconnect()

        clear()
    }

    func drainMessageQueue() {
        guard let webSocket = _webSocket,
            webSocket.isConnected,
            let webRTCClient = _webRTCClient else {
            return
        }

        for message in _messageQueue {
            processSignalingMessage(message)
        }
        _messageQueue.removeAll()
        webRTCClient.drainMessageQueue()
    }

    func processSignalingMessage(_ message: String) -> Void {
        guard let webRTCClient = _webRTCClient else { return }

        let signalMessage = SignalMessage.from(message: message)
        switch signalMessage {
        case .candidate(let candidate):
            webRTCClient.handleCandidateMessage(candidate)
            dLog("Receive candidate")
        case .answer(let answer):
            webRTCClient.handleRemoteDescription(answer)
            dLog("Recevie Answer")
        case .offer(let offer):
            webRTCClient.handleRemoteDescription(offer)
            dLog("Recevie Offer")
        case .bye:
            disconnect()
        default:
            break
        }
    }

    func sendSignalingMessage(_ message: Data) {
        guard let roomID = _roomInfo?.room_id,
            let userID = _roomInfo?.client_id,
            let roomClient = _roomClient else { return }

        roomClient.sendMessage(message, roomID: roomID, userID: userID) {

        }
    }
}

//MARK: webSocketClientDelegate
extension AudioCallViewModel: WebSocketClientDelegate {
    func connectToWebSocket(roomId: String) -> Void {
        guard let webSocketURL = URL(string: APIContants.signalingServerURL + "?roomId=" + roomId) else {
            return
        }
//        let url = URL(string: webSocketURL)
        guard let webSocket = _webSocket else {
            return
        }
        webSocket.delegate = self
        debugPrint(webSocketURL)
        webSocket.connect(url: webSocketURL)
    }

    func registerWithCollider() {
        guard let roomID = _roomInfo?.room_id,
            let userID = _roomInfo?.client_id,
            let webSocket = _webSocket else {
            return
        }

        let message = ["cmd": "register",
            "roomid": roomID,
            "clientid": userID
        ]

        guard let data = message.JSONData else {
            debugPrint("Error in Register room.")
            return
        }

        webSocket.send(data: data)
        dLog("Register Room")
    }

    func webSocketDidConnect(_ webSocket: WebSocketClient) {
        guard let webRTCClient = _webRTCClient else { return }

        registerWithCollider();

        webRTCClient.delegate = self
        if(_roomInfo?.is_initiator == "true") {
            webRTCClient.createOffer()
        }
        drainMessageQueue();

    }

    func webSocketDidDisconnect(_ webSocket: WebSocketClient) {
        webSocket.delegate = nil
    }

    func webSocket(_ webSocket: WebSocketClient, didReceive data: String) {
        processSignalingMessage(data)
        _webRTCClient?.drainMessageQueue()
    }
}

//MARK: WebRTCClientDelegate
extension AudioCallViewModel: WebRTCClientDelegate {
    func webRTCClient(_ client: WebRTCClient, sendData data: Data) {
        sendSignalingMessage(data)
    }
}

//MARK: 音视频开关
extension AudioCallViewModel {

    func audioEnable(_ enable: Bool) -> Void {
        self._webRTCClient?.AudioIsEnable = enable
    }

}
