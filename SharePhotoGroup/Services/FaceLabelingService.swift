//
//  FaceLabelingService.swift
//  SharePhotoGroup
//
//  Created by Pavel Mac on 25/04/25
//

import SwiftUI
import Contacts
import Vision
import CoreML
import CryptoKit

extension UIImage {
    func normalizedOrientation() -> UIImage {
        if imageOrientation == .up {
            return self
        }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return normalizedImage ?? self
    }
}

enum LabelSource: String {
    case userProfile = "userProfile"
    case contact = "contact"
    case peer = "peer"
}

struct KnownFace {
    let id: UUID
    let faceVector: [Float]
    let name: String?
    let labelSource: LabelSource
    let contactIdentifier: String?
    let trustScore: Float
    let familyRelation: Bool
}

class FaceLabelingService: ObservableObject {
    private let contactStore = CNContactStore()
    /*private*/ let faceEmbeddingService: FaceEmbeddingService
    @Published private(set) var knownFaces: [KnownFace] = []
    private var currentUserFamilyName: String?
    
    @Published var isProcessing = false
    @Published var processingProgress: Float = 0
    
    private let embeddingInputSize = CGSize(width: 160, height: 160) // Стандарт для FaceNet
    
    init(faceEmbeddingService: FaceEmbeddingService) {
        self.faceEmbeddingService = faceEmbeddingService
        loadKnownFaces()
        Task {
            await processContacts()
        }
    }
    
    private func saveKnownFaces() {
        print("[FaceLabelingService] Сохраняем известные лица...")
        let facesData = knownFaces.map { face -> [String: Any] in
            return [
                "id": face.id.uuidString,
                "faceVector": face.faceVector,
                "name": face.name ?? "",
                "labelSource": face.labelSource.rawValue,
                "contactIdentifier": face.contactIdentifier ?? "",
                "trustScore": face.trustScore,
                "familyRelation": face.familyRelation
            ]
        }
        UserDefaults.standard.set(facesData, forKey: "knownFaces")
        print("[FaceLabelingService] Сохранено \(facesData.count) лиц")
    }
    
    private func loadKnownFaces() {
        print("[FaceLabelingService] Загружаем известные лица...")
        guard let facesData = UserDefaults.standard.array(forKey: "knownFaces") as? [[String: Any]] else {
            print("[FaceLabelingService] Нет сохраненных лиц")
            return
        }
        
        knownFaces = facesData.compactMap { data -> KnownFace? in
            guard let idString = data["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let faceVector = data["faceVector"] as? [Float],
                  let name = data["name"] as? String,
                  let labelSourceString = data["labelSource"] as? String,
                  let labelSource = LabelSource(rawValue: labelSourceString),
                  let trustScore = data["trustScore"] as? Float,
                  let familyRelation = data["familyRelation"] as? Bool else {
                return nil
            }
            
            return KnownFace(
                id: id,
                faceVector: faceVector,
                name: name.isEmpty ? nil : name,
                labelSource: labelSource,
                contactIdentifier: (data["contactIdentifier"] as? String)?.isEmpty == false ? data["contactIdentifier"] as? String : nil,
                trustScore: trustScore,
                familyRelation: familyRelation
            )
        }
        print("[FaceLabelingService] Загружено \(knownFaces.count) лиц")
    }
    
    func setCurrentUserFamilyName(_ name: String) {
        currentUserFamilyName = name
    }
    
    private func cropFace(from image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        do {
            try handler.perform([request])
            guard let results = request.results as? [VNFaceObservation],
                  let firstFace = results.first else {
                print("[FaceLabelingService] Лицо не найдено на фото")
                return nil
            }
            
            let boundingBox = firstFace.boundingBox
            let x = boundingBox.origin.x * CGFloat(cgImage.width)
            let y = (1 - boundingBox.origin.y - boundingBox.height) * CGFloat(cgImage.height)
            let width = boundingBox.width * CGFloat(cgImage.width)
            let height = boundingBox.height * CGFloat(cgImage.height)
            
            guard let croppedCGImage = cgImage.cropping(to: CGRect(x: x, y: y, width: width, height: height)) else {
                print("[FaceLabelingService] Не удалось обрезать фото")
                return nil
            }
            
            let croppedImage = UIImage(cgImage: croppedCGImage)
            // Логируем hash изображения
            if let imageData = croppedImage.pngData() {
                let hash = SHA256.hash(data: imageData)
                let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
                print("[FaceLabelingService] Hash cropped face: \(hashString)")
            } else {
                print("[FaceLabelingService] Не удалось получить данные для hash cropped face")
            }
            return croppedImage
        } catch {
            print("[FaceLabelingService] Ошибка при поиске лица: \(error)")
            return nil
        }
    }
    
    private func cropCenterFace(from image: UIImage) -> UIImage? {
        let width = image.size.width
        let height = image.size.height
        let cropWidth = width * 0.6
        let cropHeight = height * 0.6
        let cropRect = CGRect(
            x: (width - cropWidth) / 2,
            y: (height - cropHeight) / 2,
            width: cropWidth,
            height: cropHeight
        )
        guard let cgImage = image.cgImage?.cropping(to: cropRect) else { return image }
        return UIImage(cgImage: cgImage)
    }
    
    private func resizeImage(_ image: UIImage, to size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: size))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return resized
    }
    
    private func saveCroppedFaceImage(_ image: UIImage, name: String, labelSource: LabelSource) {
        guard let data = image.pngData() else { return }
        let fileManager = FileManager.default
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let filename = "croppedface_\(labelSource)_\(name).png"
        let url = docs.appendingPathComponent(filename)
        do {
            try data.write(to: url)
            print("[FaceLabelingService] Cropped face saved to: \(url.path)")
        } catch {
            print("[FaceLabelingService] Не удалось сохранить cropped face: \(error)")
        }
    }
    
 
    func addUserProfileFace(image: UIImage, name: String) async {
        do {
            print("[FaceLabelingService] Начинаем добавление профильного лица: \(name)")
            // Нормализуем ориентацию только для фото профиля
            let normalizedImage = image.normalizedOrientation()
            // Сначала ищем лицо на нормализованном фото
            var croppedImage = cropFace(from: normalizedImage)
            if croppedImage == nil {
                print("[FaceLabelingService] Vision не нашел лицо, используем cropCenterFace как fallback")
                croppedImage = cropCenterFace(from: normalizedImage)
            }
            guard let croppedImage = croppedImage else {
                print("[FaceLabelingService] Не удалось обрезать лицо с фото профиля даже fallback-ом")
                return
            }
            print("[FaceLabelingService] Лицо успешно обрезано (размер: \(croppedImage.size.width)x\(croppedImage.size.height))")
            if let imageData = croppedImage.pngData() {
                let hash = SHA256.hash(data: imageData)
                let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
                print("[FaceLabelingService] Hash cropped face: \(hashString)")
            }
            // Универсальный resize для embedding
            let finalImage = resizeImage(croppedImage, to: embeddingInputSize) ?? croppedImage
            print("[FaceLabelingService] Cropped face приведён к \(embeddingInputSize.width)x\(embeddingInputSize.height)")
            let embedding = try await faceEmbeddingService.getEmbedding(for: finalImage)
            print("[FaceLabelingService] Embedding получен, длина: \(embedding.count)")
            // Проверяем, есть ли уже такое лицо
            let existingFace = knownFaces.first { $0.name == name && $0.labelSource == .userProfile }
            if let existingFace = existingFace {
                print("[FaceLabelingService] Найдено существующее профильное лицо, обновляем...")
                // Удаляем старое лицо
                knownFaces.removeAll { $0.id == existingFace.id }
            }
            let knownFace = KnownFace(
                id: UUID(),
                faceVector: embedding,
                name: name,
                labelSource: .userProfile,
                contactIdentifier: nil,
                trustScore: 1.0,
                familyRelation: false
            )
            knownFaces.append(knownFace)
            print("[FaceLabelingService] Профильное лицо добавлено: \(name)")
            print("[FaceLabelingService] Всего известных лиц: \(knownFaces.count)")
            print("[FaceLabelingService] Профильные лица: \(knownFaces.filter { $0.labelSource == .userProfile }.count)")
            // Сохраняем обновленный список лиц
            saveKnownFaces()
            // Сохраняем cropped face для отладки
            saveCroppedFaceImage(finalImage, name: name, labelSource: .userProfile)
        } catch {
            print("[FaceLabelingService] Ошибка получения embedding: \(error)")
        }
    }
    
    func processContacts() async {
        DispatchQueue.main.async {
            self.isProcessing = true
            self.processingProgress = 0
        }
        print("[FaceLabelingService] Начинаем обработку контактов...")
        var embeddingCount = 0
        do {
            let status = CNContactStore.authorizationStatus(for: .contacts)
            if status == .notDetermined {
                let granted = try await contactStore.requestAccess(for: .contacts)
                if !granted { print("[FaceLabelingService] Нет доступа к контактам"); return }
            } else if status != .authorized {
                print("[FaceLabelingService] Нет доступа к контактам"); return
            }
            let keys: [CNKeyDescriptor] = [
                CNContactGivenNameKey,
                CNContactFamilyNameKey,
                CNContactImageDataKey,
                CNContactIdentifierKey
            ] as [CNKeyDescriptor]
            let request = CNContactFetchRequest(keysToFetch: keys)
            var contactsWithImages: [CNContact] = []
            var totalContacts = 0
            try contactStore.enumerateContacts(with: request) { contact, stop in
                totalContacts += 1
                if contact.imageData != nil {
                    contactsWithImages.append(contact)
                }
            }
            var processedCount = 0
            for contact in contactsWithImages {
                if let imageData = contact.imageData, let image = UIImage(data: imageData) {
                    do {
                        // Кропаем лицо из фото контакта
                        var croppedImage = cropFace(from: image)
                        if croppedImage == nil {
                            print("[FaceLabelingService] Не удалось обрезать лицо для контакта: \(contact.givenName) \(contact.familyName), fallback cropCenterFace")
                            croppedImage = cropCenterFace(from: image)
                        }
                        guard let croppedImage = croppedImage else {
                            print("[FaceLabelingService] Не удалось обрезать лицо для контакта даже fallback-ом: \(contact.givenName) \(contact.familyName)")
                            continue
                        }
                        print("[FaceLabelingService] Лицо успешно обрезано для контакта: \(contact.givenName) \(contact.familyName), размер: \(croppedImage.size.width)x\(croppedImage.size.height)")
                        if let imageData = croppedImage.pngData() {
                            let hash = SHA256.hash(data: imageData)
                            let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
                            print("[FaceLabelingService] Hash cropped face: \(hashString)")
                        }
                        // Универсальный resize для embedding
                        let finalImage = resizeImage(croppedImage, to: embeddingInputSize) ?? croppedImage
                        print("[FaceLabelingService] Cropped face приведён к \(embeddingInputSize.width)x\(embeddingInputSize.height)")
                        let embedding = try faceEmbeddingService.getEmbedding(for: finalImage)
                        let isFamily = self.currentUserFamilyName != nil &&
                            contact.familyName.lowercased() == self.currentUserFamilyName!.lowercased()
                        let knownFace = KnownFace(
                            id: UUID(),
                            faceVector: embedding,
                            name: contact.givenName,
                            labelSource: .contact,
                            contactIdentifier: contact.identifier,
                            trustScore: isFamily ? 0.9 : 0.7,
                            familyRelation: isFamily
                        )
                        self.knownFaces.append(knownFace)
                        embeddingCount += 1
                        print("[FaceLabelingService] Embedding создан для контакта: \(contact.givenName) \(contact.familyName)")
                        // Сохраняем cropped face для отладки
                        saveCroppedFaceImage(finalImage, name: contact.givenName, labelSource: .contact)
                    } catch {
                        print("[FaceLabelingService] Ошибка embedding для контакта: \(contact.givenName) \(contact.familyName): \(error)")
                    }
                } else {
                    print("[FaceLabelingService] Контакт без фото: \(contact.givenName) \(contact.familyName)")
                }
                processedCount += 1
                DispatchQueue.main.async {
                    self.processingProgress = Float(processedCount) / Float(totalContacts)
                }
            }
            print("[FaceLabelingService] Всего обработано контактов: \(totalContacts)")
            print("[FaceLabelingService] Embedding создано: \(embeddingCount)")
            
            // Сохраняем обновленный список лиц
            saveKnownFaces()
        } catch {
            print("Error processing contacts: \(error)")
        }
        DispatchQueue.main.async {
            self.isProcessing = false
        }
    }
    
    func addPeerFace(embedding: [Float], name: String?, from peerID: String) {
        let knownFace = KnownFace(
            id: UUID(),
            faceVector: embedding,
            name: name,
            labelSource: .peer,
            contactIdentifier: nil,
            trustScore: 0.5,
            familyRelation: false
        )
        
        knownFaces.append(knownFace)
        print("✅ Добавлено лицо от пира: \(name ?? peerID) (всего: \(knownFaces.count))")
    }
    

    
    func findMatch(for embedding: [Float]) -> (name: String?, confidence: Float, source: LabelSource)? {
        var bestMatch: (name: String?, confidence: Float, source: LabelSource)?
        var highestSimilarity: Float = 0.0

        print("🔍 Начинаем поиск совпадений среди \(knownFaces.count) известных лиц")
        
        for knownFace in knownFaces {
            // Проверка, что faceVector не пустой
            if knownFace.faceVector.isEmpty {
                print("⚠️ Пропущен известный вектор лица для \(knownFace.name ?? "неизвестно")")
                continue
            }

            let similarity = faceEmbeddingService.calculateSimilarity(knownFace.faceVector, embedding)
            print("🔍 Сравнение с \(knownFace.name ?? "неизвестно"): similarity = \(similarity), trustScore = \(knownFace.trustScore)")

            // Используем trustScore для корректировки confidence
            let finalConfidence = similarity * knownFace.trustScore
            
            if finalConfidence > highestSimilarity {
                highestSimilarity = finalConfidence
                bestMatch = (knownFace.name, finalConfidence, knownFace.labelSource)
                print("✅ Найдено лучшее совпадение: \(knownFace.name ?? "неизвестно") с confidence = \(finalConfidence)")
            }
        }

        // Логируем итоговый bestMatch
        print("🔎 Итоговый bestMatch: \(bestMatch?.name ?? "nil"), confidence: \(bestMatch?.confidence ?? 0), source: \(bestMatch?.source.rawValue ?? "nil")")

        // Используем одинаковый порог для всех типов лиц
        let threshold: Float = 0.25
        if let match = bestMatch, match.confidence > threshold {
            print("✅ Финальное совпадение: \(match.name ?? "неизвестно") с confidence = \(match.confidence)")
            return match
        }

        print("❌ Совпадений не найдено (лучшее similarity: \(highestSimilarity))")
        return nil
    }
    
    func getKnownFaces() -> [KnownFace] {
        print("[FaceLabelingService] Запрос списка известных лиц")
        print("[FaceLabelingService] Всего лиц: \(knownFaces.count)")
        print("[FaceLabelingService] Профильные лица: \(knownFaces.filter { $0.labelSource == .userProfile }.map { $0.name ?? "Unknown" })")
        print("[FaceLabelingService] Контакты: \(knownFaces.filter { $0.labelSource == .contact }.map { $0.name ?? "Unknown" })")
        return knownFaces
    }
    
    func clearKnownFaces() {
        knownFaces.removeAll()
    }
    // Получить имя и аватар контакта по эмбеддингу (асинхронно)
    func getContactDisplayInfo(for embedding: [Float]) async -> (name: String, avatar: UIImage?)? {
        if let match = findMatch(for: embedding),
           match.source == .contact,
           let knownFace = getKnownFaces().first(where: { $0.name == match.name && $0.labelSource == .contact }),
           let contactId = knownFace.contactIdentifier,
           let contact = try? await ContactService.shared.fetchContact(byIdentifier: contactId) {
            let name = ContactService.shared.getContactName(from: contact)
            let avatar = ContactService.shared.getContactImage(from: contact)
            return (name, avatar)
        }
        return nil
    }
    /// Получить фото контакта по совпадению (match)
    func getContactImage(for match: (name: String?, confidence: Float, source: LabelSource)) -> UIImage? {
        guard let name = match.name, match.source == .contact else { return nil }
        // Найти KnownFace с этим именем и source == .contact
        if let contact = knownFaces.first(where: { $0.name == name && $0.labelSource == .contact }),
           let identifier = contact.contactIdentifier {
            let keysToFetch = [CNContactImageDataKey as CNKeyDescriptor]
            do {
                let cnContact = try contactStore.unifiedContact(withIdentifier: identifier, keysToFetch: keysToFetch)
                if let imageData = cnContact.imageData, let image = UIImage(data: imageData) {
                    return image
                }
            } catch {
                print("[FaceLabelingService] Не удалось получить фото контакта: \(error)")
            }
        }
        return nil
    }
}
