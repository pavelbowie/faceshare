//
//  MultipeerService.swift
//  SharePhotoGroup
//
//  Created by Pavel Mac on 22/04/25
//

import MultipeerConnectivity
import Combine
import CoreData
import Vision

class MultipeerService: NSObject, ObservableObject {
    
    private let serviceType = "face-emb-v2"
    private let myPeerId = MCPeerID(displayName: UIDevice.current.name)
    private let serviceAdvertiser: MCNearbyServiceAdvertiser
    private let serviceBrowser: MCNearbyServiceBrowser
    private let session: MCSession
    private let photoStorage: PhotoStorageService
    private let deviceHistoryService: DeviceHistoryService
    private var pendingPhotos: [(image: UIImage, peerID: MCPeerID)] = []
    private var isProcessingEmbeddings = false
    @Published var autoSendPhotos = false

    @Published var connectedPeers: [MCPeerID] = []
    @Published var receivedEmbeddings: [(peerID: MCPeerID, embedding: [Float])] = []
    @Published var isAdvertising = false
    @Published var isBrowsing = false
    @Published var receivedImages: [UIImage] = []
    private var handledEmbeddings: Set<Data> = []

    var faceStore: FaceStore?
    var embeddingService: FaceEmbeddingService?
    var labelingService: FaceLabelingService?
    var peerToTargetEmbedding: [MCPeerID: [Float]] = [:]

    private let similarityThreshold: Float = 0.7 // Увеличиваем порог схожести с 0.01 до 0.7
    
    // Новое: сопоставление peerID -> (имя, аватарка)
    var peerToContact: [MCPeerID: (name: String, avatar: UIImage?)] = [:]
    
    init(photoStorage: PhotoStorageService) {
        self.photoStorage = photoStorage
        let context = PersistenceController.shared.container.viewContext
        self.deviceHistoryService = DeviceHistoryService(context: context)
        
        session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .required)
        serviceAdvertiser = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: nil, serviceType: serviceType)
        serviceBrowser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType)
        
        super.init()
        
        session.delegate = self
        serviceAdvertiser.delegate = self
        serviceBrowser.delegate = self
        
        print("[Инициализация] MultipeerService создан для \(myPeerId.displayName)")
    }
    
    func configure(faceStore: FaceStore, embeddingService: FaceEmbeddingService, labelingService: FaceLabelingService) {
        self.faceStore = faceStore
        self.embeddingService = embeddingService
        self.labelingService = labelingService
    }
    
    func startAdvertising() {
        // Проверяем, установлен ли профиль пользователя
        guard let _ = UserProfile.shared.contactName,
              let _ = UserProfile.shared.profileImage else {
            print("[Реклама] Нельзя начать рекламу: профиль не настроен")
            return
        }
        
        print("[Реклама] Запуск трансляции")
        serviceAdvertiser.startAdvertisingPeer()
        isAdvertising = true
    }
    
    func stopAdvertising() {
        print("[Реклама] Остановка трансляции")
        serviceAdvertiser.stopAdvertisingPeer()
        isAdvertising = false
    }
    
    func startBrowsing() {
        // Проверяем, установлен ли профиль пользователя
        guard let _ = UserProfile.shared.contactName,
              let _ = UserProfile.shared.profileImage else {
            print("[Поиск] Нельзя начать поиск: профиль не настроен")
            return
        }
        
        print("[Поиск] Запуск поиска пиров")
        serviceBrowser.startBrowsingForPeers()
        isBrowsing = true
    }
    
    func stopBrowsing() {
        print("[Поиск] Остановка поиска пиров")
        serviceBrowser.stopBrowsingForPeers()
        isBrowsing = false
    }
    
    func sendEmbedding(_ embedding: [Float], to peer: MCPeerID) {
        do {
            let data = try JSONEncoder().encode(embedding)
            try session.send(data, toPeers: [peer], with: .reliable)
            print("[Отправка] Отправлен эмбеддинг пиру \(peer.displayName)")
            
            // Обновляем историю при отправке эмбеддинга
            if let contact = self.peerToContact[peer] {
                self.deviceHistoryService.updateDeviceHistory(peer: peer, name: contact.name, avatar: contact.avatar)
            } else {
                self.deviceHistoryService.updateDeviceHistory(peer: peer, name: nil, avatar: nil)
            }
            
            // Обновляем состояние после отправки
            DispatchQueue.main.async {
                // Проверяем, есть ли уже такой эмбеддинг
                if !self.receivedEmbeddings.contains(where: { $0.peerID == peer }) {
                    self.receivedEmbeddings.append((peer, embedding))
                }
            }
        } catch {
            print("[Ошибка] Не удалось отправить эмбеддинг: \(error.localizedDescription)")
        }
    }
    
    func sendPhoto(_ image: UIImage, to peer: MCPeerID) {
        // Используем максимальное качество для сохранения
        guard let imageData = image.jpegData(compressionQuality: 1.0) else {
            print("[Ошибка] Невозможно сконвертировать изображение в JPEG")
            return
        }
        
        do {
            try session.send(imageData, toPeers: [peer], with: .reliable)
            print("[Отправка] Отправлено фото пиру \(peer.displayName)")
            
            // Обновляем историю при отправке фото
            if let contact = self.peerToContact[peer] {
                self.deviceHistoryService.updateDeviceHistory(peer: peer, name: contact.name, avatar: contact.avatar)
            } else {
                self.deviceHistoryService.updateDeviceHistory(peer: peer, name: nil, avatar: nil)
            }
        } catch {
            print("[Ошибка] Не удалось отправить фото: \(error.localizedDescription)")
        }
    }
    
    func sendAllEmbeddings(_ embeddings: [[Float]]) async throws {
        guard !connectedPeers.isEmpty else {
            throw NSError(domain: "MultipeerService", code: 1, userInfo: [NSLocalizedDescriptionKey: "No connected peers"])
        }
        
        for embedding in embeddings {
            do {
                let data = try JSONEncoder().encode(embedding)
                try session.send(data, toPeers: connectedPeers, with: .reliable)
                print("[Отправка] Отправлен эмбеддинг всем подключенным пирам")
            } catch {
                print("[Ошибка] Не удалось отправить эмбеддинг: \(error.localizedDescription)")
                throw error
            }
        }
    }
    
    func handleReceivedEmbedding(_ embedding: [Float], from peerID: MCPeerID) {
        guard let faceStore = faceStore,
              let embeddingService = embeddingService else {
            print("[Ошибка] FaceStore или EmbeddingService не настроены")
            return
        }
        
        print("[Обработка] Получен эмбеддинг от \(peerID.displayName)")
        
        // Обновляем peerToContact с использованием getContactDisplayInfo (асинхронно)
        Task {
            if let labelingService = self.labelingService,
               let match = labelingService.findMatch(for: embedding),
               match.source == .contact,
               match.confidence >= self.similarityThreshold, // Проверяем порог схожести
               let knownFace = labelingService.getKnownFaces().first(where: { $0.name == match.name && $0.labelSource == .contact }),
               let contactId = knownFace.contactIdentifier,
               let contact = try? await ContactService.shared.fetchContact(byIdentifier: contactId) {
                
                let name = ContactService.shared.getContactName(from: contact)
                let avatar = ContactService.shared.getContactImage(from: contact)
                
                self.peerToContact[peerID] = (name: name, avatar: avatar)
                print("[PeerToContact] Обновлено: \(peerID.displayName) -> \(name) (аватар: \(avatar != nil ? "есть" : "нет"))")
                
                // Обрабатываем отложенные фото после обновления peerToContact
                await self.processPendingPhotos()
            } else {
                // Если нет совпадения выше порога, используем информацию из профиля
                // Проверяем, есть ли уже информация о профиле в peerToContact
                if let existingContact = self.peerToContact[peerID] {
                    // Сохраняем существующую информацию
                    print("[PeerToContact] Сохраняем существующую информацию: \(existingContact.name)")
                } else {
                    // Если информации еще нет, используем имя устройства
                    self.peerToContact[peerID] = (name: peerID.displayName, avatar: nil)
                    print("[PeerToContact] Используем имя устройства: \(peerID.displayName)")
                }
            }
        }
        
        // Ищем похожие фото в локальном хранилище
        print("[Поиск] Ищем похожие фото среди \(faceStore.faces.count) локальных фото")
        var bestSimilarity: Float = 0.0
        var bestMatch: FaceData?
        
        for (idx, face) in faceStore.faces.enumerated() {
            let similarity = embeddingService.calculateSimilarity(face.embedding, embedding)
            let percent = Int(similarity * 100)
            print("[Сравнение] Фото \(idx + 1): similarity = \(String(format: "%.2f", similarity)) (\(percent)%)")
            
            if similarity > bestSimilarity {
                bestSimilarity = similarity
                bestMatch = face
            }
        }
        
        print("[Результат] Лучшая схожесть: \(bestSimilarity)")
        
        // Отправляем фото только если включен флаг autoSendPhotos и схожесть выше порога
        if autoSendPhotos, let match = bestMatch, bestSimilarity > similarityThreshold {
            sendPhoto(match.fullImage, to: peerID)
            print("[Отправка] Найдено похожее фото! Отправляем его \(peerID.displayName) (схожесть: \(String(format: "%.2f", bestSimilarity)))")
        } else {
            print("[Результат] Похожих фото не найдено или автоматическая отправка отключена")
        }
    }
    
    private func processPendingPhotos() async {
        print("🔄 Обработка отложенных фото...")
        for (index, pending) in pendingPhotos.enumerated() {
            if let contact = peerToContact[pending.peerID] {
                await photoStorage.savePhoto(
                    pending.image,
                    senderName: contact.name,
                    senderAvatar: contact.avatar,
                    recognizedFaces: nil // Передаем nil, так как лица будут распознаны внутри savePhoto
                )
                print("✅ Обработано отложенное фото \(index + 1) из \(pendingPhotos.count)")
            }
        }
        pendingPhotos.removeAll()
    }
    
    /// Фильтрует фото: оставляет только те, где найдено лицо, схожее с targetEmbedding для peerID
    func filterPhotosForPeer(_ photos: [UIImage], peerID: MCPeerID, threshold: Float = 0.7) -> [UIImage] {
        guard let targetEmbedding = peerToTargetEmbedding[peerID],
              let embeddingService = embeddingService else { return [] }
        return photos.filter { photo in
            photoContainsTargetFace(photo, targetEmbedding: targetEmbedding, embeddingService: embeddingService, threshold: threshold)
        }
    }
    
    /// Проверяет, есть ли на фото лицо, схожее с targetEmbedding
    private func photoContainsTargetFace(_ photo: UIImage, targetEmbedding: [Float], embeddingService: FaceEmbeddingService, threshold: Float = 0.7) -> Bool {
        guard let cgImage = photo.cgImage else { return false }
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            guard let results = request.results as? [VNFaceObservation], !results.isEmpty else { return false }
            for face in results {
                let boundingBox = face.boundingBox
                let width = CGFloat(cgImage.width)
                let height = CGFloat(cgImage.height)
                let rect = CGRect(
                    x: boundingBox.origin.x * width,
                    y: (1 - boundingBox.origin.y - boundingBox.height) * height,
                    width: boundingBox.width * width,
                    height: boundingBox.height * height
                ).integral
                guard let faceCgImage = cgImage.cropping(to: rect) else { continue }
                let faceImage = UIImage(cgImage: faceCgImage)
                if let embedding = try? embeddingService.getEmbedding(for: faceImage) {
                    let similarity = embeddingService.calculateSimilarity(embedding, targetEmbedding)
                    if similarity > threshold {
                        return true
                    }
                }
            }
        } catch {
            print("Ошибка Vision: \(error)")
        }
        return false
    }
}

extension MultipeerService: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                if !self.connectedPeers.contains(peerID) {
                    self.connectedPeers.append(peerID)
                    // Обновляем историю устройств при подключении
                    if let contact = self.peerToContact[peerID] {
                        self.deviceHistoryService.updateDeviceHistory(peer: peerID, name: contact.name, avatar: contact.avatar)
                    } else {
                        self.deviceHistoryService.updateDeviceHistory(peer: peerID, name: nil, avatar: nil)
                    }
                }
                // Отправляем информацию о профиле и эмбеддинг после успешного соединения
                if let embedding = UserProfile.shared.faceEmbedding {
                    print("[Сессия] Отправляем эмбеддинг новому пиру \(peerID.displayName)")
                    self.sendEmbedding(embedding, to: peerID)
                    
                    // Отправляем информацию о профиле
                    let profileInfo = ProfileInfo(
                        name: UserProfile.shared.contactName ?? peerID.displayName,
                        embedding: embedding,
                        hasProfileImage: UserProfile.shared.profileImage != nil
                    )
                    
                    do {
                        let data = try JSONEncoder().encode(profileInfo)
                        try session.send(data, toPeers: [peerID], with: .reliable)
                        print("[Сессия] Отправлена информация о профиле пиру \(peerID.displayName)")
                        
                        // Отправляем фото профиля, если оно есть
                        if let profileImage = UserProfile.shared.profileImage,
                           let imageData = profileImage.jpegData(compressionQuality: 0.9) {
                            try session.send(imageData, toPeers: [peerID], with: .reliable)
                            print("[Сессия] Отправлено фото профиля пиру \(peerID.displayName)")
                        }
                    } catch {
                        print("[Ошибка] Не удалось отправить информацию о профиле: \(error.localizedDescription)")
                    }
                } else {
                    print("[Сессия] Предупреждение: нет эмбеддинга для отправки пиру \(peerID.displayName)")
                }
            case .notConnected:
                if let index = self.connectedPeers.firstIndex(of: peerID) {
                    self.connectedPeers.remove(at: index)
                }
                // Удаляем эмбеддинг при отключении
                self.receivedEmbeddings.removeAll { $0.peerID == peerID }
            case .connecting:
                print("[Сессия] Идёт соединение с \(peerID.displayName)")
            @unknown default:
                print("[Сессия] Неизвестное состояние с \(peerID.displayName)")
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            if let embedding = try? JSONDecoder().decode([Float].self, from: data) {
                print("[Данные] Получен эмбеддинг от \(peerID.displayName)")
                
                // Обновляем или добавляем эмбеддинг
                if let index = self.receivedEmbeddings.firstIndex(where: { $0.peerID == peerID }) {
                    self.receivedEmbeddings[index] = (peerID, embedding)
                } else {
                    self.receivedEmbeddings.append((peerID, embedding))
                }
                
                // Обновляем историю при получении эмбеддинга
                if let contact = self.peerToContact[peerID] {
                    self.deviceHistoryService.updateDeviceHistory(peer: peerID, name: contact.name, avatar: contact.avatar)
                } else {
                    // Если нет информации о контакте, используем имя устройства
                    self.deviceHistoryService.updateDeviceHistory(peer: peerID, name: peerID.displayName, avatar: nil)
                }
                
                self.handleReceivedEmbedding(embedding, from: peerID)
            }
            else if let profileInfo = try? JSONDecoder().decode(ProfileInfo.self, from: data) {
                print("[Данные] Получена информация о профиле от \(peerID.displayName)")
                // Обновляем информацию о пире
                let currentContact = self.peerToContact[peerID]
                self.peerToContact[peerID] = (
                    name: profileInfo.name,
                    avatar: currentContact?.avatar
                )
                // Обновляем историю при получении информации о профиле
                self.deviceHistoryService.updateDeviceHistory(peer: peerID, name: profileInfo.name, avatar: currentContact?.avatar)
                print("[PeerToContact] Обновлено: \(peerID.displayName) -> \(profileInfo.name) (аватар: \(currentContact?.avatar != nil ? "есть" : "нет"))")
            }
            else if let image = UIImage(data: data) {
                print("[Данные] Получено изображение от \(peerID.displayName)")
                
                // Проверяем, является ли это фото профиля
                if let contact = self.peerToContact[peerID], contact.avatar == nil {
                    // Обновляем аватар в peerToContact
                    self.peerToContact[peerID] = (name: contact.name, avatar: image)
                    // Обновляем историю при получении аватара
                    self.deviceHistoryService.updateDeviceHistory(peer: peerID, name: contact.name, avatar: image)
                    print("[Данные] Обновлен аватар профиля для \(peerID.displayName)")
                } else if !self.containsImage(image) {
                    self.receivedImages.append(image)
                    
                    Task {
                        // Проверяем, есть ли уже информация об отправителе
                        if let contact = self.peerToContact[peerID] {
                            await self.photoStorage.savePhoto(
                                image,
                                senderName: contact.name,
                                senderAvatar: contact.avatar,
                                recognizedFaces: nil // Передаем nil, так как лица будут распознаны внутри savePhoto
                            )
                            // Обновляем историю при получении фото
                            self.deviceHistoryService.updateDeviceHistory(peer: peerID, name: contact.name, avatar: contact.avatar)
                        } else {
                            // Если информации еще нет, добавляем фото в очередь ожидания
                            self.pendingPhotos.append((image: image, peerID: peerID))
                            // Обновляем историю с базовой информацией
                            self.deviceHistoryService.updateDeviceHistory(peer: peerID, name: peerID.displayName, avatar: nil)
                            print("[Ожидание] Фото добавлено в очередь ожидания для \(peerID.displayName)")
                        }
                    }
                } else {
                    print("[Данные] Изображение уже существует, не добавляем")
                }
            }
            else {
                print("[Данные] Получен неизвестный формат данных от \(peerID.displayName)")
            }
        }
    }
    
    private func containsImage(_ newImage: UIImage) -> Bool {
        guard let newData = newImage.pngData() else { return false }
        for image in receivedImages {
            if let data = image.pngData(), data == newData {
                return true
            }
        }
        return false
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        print("[Поток] Получен поток \(streamName) от \(peerID.displayName)")
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        print("[Ресурс] Начат приём ресурса \(resourceName) от \(peerID.displayName)")
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        if let error = error {
            print("[Ресурс] Ошибка при приёме ресурса \(resourceName) от \(peerID.displayName): \(error.localizedDescription)")
        } else {
            print("[Ресурс] Ресурс \(resourceName) от \(peerID.displayName) успешно получен")
        }
    }
}

extension MultipeerService: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("[Реклама] Получено приглашение от \(peerID.displayName)")
        invitationHandler(true, session)
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("[Ошибка рекламы] Не удалось начать рекламу: \(error.localizedDescription)")
    }
}

extension MultipeerService: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        print("[Поиск] Найден пир: \(peerID.displayName)")
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("[Поиск] Потерян пир: \(peerID.displayName)")
        DispatchQueue.main.async {
            self.connectedPeers.removeAll { $0 == peerID }
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("[Ошибка поиска] Не удалось начать поиск пиров: \(error.localizedDescription)")
    }
}

// Добавляем структуру для передачи информации о профиле
struct ProfileInfo: Codable {
    let name: String
    let embedding: [Float]
    let hasProfileImage: Bool
}

