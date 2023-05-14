//
//  WebRTCClient.swift
//  pens
//
//  Created by Lee Jeong Woo on 2023/05/14.
//

import Foundation
import WebRTC

protocol WebRTCClientDelegate: class {
    func webRTCClient(_ client: WebRTCClient, sendData data: Data)
}

class WebRTCClient: NSObject {
    var factory: RTCPeerConnectionFactory
    var remoteAudioTrack: RTCAudioTrack?
    private let mediaConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
    private var candidateQueue = [RTCIceCandidate]()
    private var peerConnection: RTCPeerConnection?
    var localAudioTrack: RTCAudioTrack?

    weak var delegate: WebRTCClientDelegate?

    private var hasReceivedSdp = false

    override init() {
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        self.factory = RTCPeerConnectionFactory(encoderFactory: encoderFactory, decoderFactory: decoderFactory)
        super.init()
        setup()
    }


    var AudioIsEnable: Bool {
        get {
            if(localAudioTrack == nil) {
                return true
            }

            return localAudioTrack!.isEnabled
        }
        set {
            localAudioTrack?.isEnabled = newValue;
        }
    }

    func setup() {
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let config = RTCConfiguration()
        self.peerConnection = self.factory.peerConnection(with: config, constraints: constraints, delegate: nil)
        let audioSource = self.factory.audioSource(with: constraints)
        self.remoteAudioTrack = self.factory.audioTrack(with: audioSource, trackId: "audio0")

        createMediaSenders()

    }

    func createOffer() {
        let constraints = RTCMediaConstraints(mandatoryConstraints: ["OfferToReceiveAudio": "true"],
            optionalConstraints: nil)

        self.peerConnection?.offer(for: constraints, completionHandler: { (sdp, error) in
            guard let sdp = sdp else {
                print("Failed to create offer: \(error?.localizedDescription ?? "")")
                return
            }

            let sdpDescription = RTCSessionDescription(type: .offer, sdp: sdp.sdp)
            self.setLocalSDP(sdpDescription)
        })
    }

    func receivedOffer(_ remoteSdp: RTCSessionDescription) {
        self.peerConnection?.setRemoteDescription(remoteSdp, completionHandler: { (error) in
            if let error = error {
                print("Failed to set remote description: \(error.localizedDescription)")
                return
            }

            self.createAnswer()
        })
    }

    private func createAnswer() {
        let constraints = RTCMediaConstraints(mandatoryConstraints: ["OfferToReceiveAudio": "true"],
            optionalConstraints: nil)

        self.peerConnection?.answer(for: constraints, completionHandler: { (sdp, error) in
            guard let sdp = sdp else {
                print("Failed to create answer: \(error?.localizedDescription ?? "")")
                return
            }

            let sdpDescription = RTCSessionDescription(type: .answer, sdp: sdp.sdp)
            self.setLocalSDP(sdpDescription)
        })
    }



    func disconnect() {
        hasReceivedSdp = false
        peerConnection?.close()
        peerConnection = nil
    }


    private func setLocalSDP(_ sdp: RTCSessionDescription) {
        guard let peerConnection = peerConnection else {
            dLog("Check PeerConnection")
            return
        }

        peerConnection.setLocalDescription(sdp, completionHandler: { (error) in
            if let error = error {
                debugPrint(error)
            }
        })

        if let data = sdp.JSONData() {
            self.delegate?.webRTCClient(self, sendData: data)
            dLog("Send Local SDP")
        }
    }
}

// MARK: Preparing parts.
extension WebRTCClient {
    private func generateRTCConfig() -> RTCConfiguration {
        let config = RTCConfiguration()
        let pcert = RTCCertificate.generate(withParams: ["expires": NSNumber(value: 100000),
            "name": "RSASSA-PKCS1-v1_5"
            ])
        config.iceServers = [RTCIceServer(urlStrings: Config.default.webRTCIceServers)]
        config.sdpSemantics = RTCSdpSemantics.unifiedPlan
        config.certificate = pcert

        return config
    }

    private func createMediaSenders() {
        guard let peerConnection = peerConnection else {
            dLog("Check PeerConnection")
            return
        }


        let mediaTrackStreamIDs = ["ARDAMS"]

        peerConnection.add(localAudioTrack!, streamIds: mediaTrackStreamIDs)
        remoteAudioTrack = peerConnection.transceivers.first { $0.mediaType == .audio }?.receiver.track as? RTCAudioTrack
    }
}


// MARK: Message Handling
extension WebRTCClient {
    func handleCandidateMessage(_ candidate: RTCIceCandidate) {
        candidateQueue.append(candidate)
    }

    func handleRemoteDescription(_ desc: RTCSessionDescription) {
        guard let peerConnection = peerConnection else {
            dLog("Check Peer connection")
            return
        }

        hasReceivedSdp = true

        peerConnection.setRemoteDescription(desc, completionHandler: { [weak self](error) in
            if let error = error {
                dLog(error)
            }

            if desc.type == .offer,
                self?.peerConnection?.localDescription == nil {
                self?.createAnswer()
            }
        })
    }

    func drainMessageQueue() {
        guard let peerConnection = peerConnection,
            hasReceivedSdp else {
            return
        }

        dLog("Drain Messages")

        for candidate in candidateQueue {
            dLog("Add Candidate: \(candidate)")
            peerConnection.add(candidate)
        }

        candidateQueue.removeAll()
    }
}

extension WebRTCClient: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        dLog("\(stateChanged.rawValue)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        dLog("")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        dLog("")
    }

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        dLog("")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        dLog("\(newState.rawValue)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        dLog("")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        guard let message = candidate.JSONData() else { return }
        delegate?.webRTCClient(self, sendData: message)
        dLog("")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        dLog("")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        dLog("")
    }
}