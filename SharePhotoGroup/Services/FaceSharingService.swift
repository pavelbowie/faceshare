//
//  FaceSharingService.swift
//  SharePhotoGroup
//
//  Created by Pavel Mac on 22/04/25
//

import Foundation
import MultipeerConnectivity

protocol FaceSharingServiceDelegate: AnyObject {
    func didReceiveEmbedding(_ embedding: [Float], from peer: MCPeerID)
    func didReceiveImage(_ image: UIImage, from peer: MCPeerID)
    func didFindPeer(_ peer: MCPeerID)
    func didLosePeer(_ peer: MCPeerID)
}

class FaceSharingService: NSObject, ObservableObject {
    private let serviceType = "face-emb-v2"
    private let myPeerId = MCPeerID(displayName: UIDevice.current.name)
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    private let browser: MCNearbyServiceBrowser
    weak var delegate: FaceSharingServiceDelegate?
    @Published var connectedPeers: [MCPeerID] = []
    var connectedPeersPublisher: Published<[MCPeerID]>.Publisher { $connectedPeers }
    
    override init() {
        session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .required)
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: nil, serviceType: serviceType)
        browser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType)
        super.init()
        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
        print("НОВАЯ: FaceSharingService инициализирован для \(myPeerId.displayName)")
    }
    
    func start() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        print("НОВАЯ: Запущен обмен эмбеддингами по сети")
    }
    
    func stop() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        print("НОВАЯ: Остановлен обмен эмбеддингами по сети")
    }
    
    func sendEmbedding(_ embedding: [Float], to peer: MCPeerID? = nil) {
        let peers = peer != nil ? [peer!] : session.connectedPeers
        guard !peers.isEmpty else {
            print("НОВАЯ: Нет подключённых пиров для отправки эмбеддинга")
            return
        }
        do {
            let data = try JSONEncoder().encode(embedding)
            try session.send(data, toPeers: peers, with: .reliable)
            print("НОВАЯ: Эмбеддинг отправлен \(peer != nil ? "пиру \(peer!.displayName)" : "всем пирам")")
        } catch {
            print("НОВАЯ: Ошибка отправки эмбеддинга: \(error)")
        }
    }
    
    func sendImage(_ image: UIImage, to peer: MCPeerID? = nil) {
        let peers = peer != nil ? [peer!] : session.connectedPeers
        guard !peers.isEmpty else {
            print("НОВАЯ: Нет подключённых пиров для отправки фото")
            return
        }
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            print("НОВАЯ: Не удалось преобразовать фото в JPEG")
            return
        }
        do {
            try session.send(data, toPeers: peers, with: .reliable)
            print("НОВАЯ: Фото отправлено \(peer != nil ? "пиру \(peer!.displayName)" : "всем пирам")")
        } catch {
            print("НОВАЯ: Ошибка отправки фото: \(error)")
        }
    }
}

extension FaceSharingService: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        print("НОВАЯ: Состояние пира \(peerID.displayName): \(state.rawValue)")
        switch state {
        case .connected:
            print("НОВАЯ: Пир \(peerID.displayName) подключен")
        case .connecting:
            print("НОВАЯ: Пир \(peerID.displayName) подключается")
        case .notConnected:
            print("НОВАЯ: Пир \(peerID.displayName) отключен")
        @unknown default:
            print("НОВАЯ: Неизвестное состояние пира \(peerID.displayName)")
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let embedding = try? JSONDecoder().decode([Float].self, from: data) {
            print("НОВАЯ: Получен эмбеддинг от \(peerID.displayName)")
            delegate?.didReceiveEmbedding(embedding, from: peerID)
        } else if let image = UIImage(data: data) {
            print("НОВАЯ: Получено фото от \(peerID.displayName)")
            delegate?.didReceiveImage(image, from: peerID)
        } else {
            print("НОВАЯ: Получены неизвестные данные от \(peerID.displayName)")
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension FaceSharingService: MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("НОВАЯ: Получено приглашение от \(peerID.displayName)")
        invitationHandler(true, session)
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("НОВАЯ: Ошибка старта рекламы: \(error)")
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        print("НОВАЯ: Найден пир: \(peerID.displayName)")
        delegate?.didFindPeer(peerID)
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("НОВАЯ: Потерян пир: \(peerID.displayName)")
        delegate?.didLosePeer(peerID)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("НОВАЯ: Ошибка старта поиска пиров: \(error)")
    }
} 
