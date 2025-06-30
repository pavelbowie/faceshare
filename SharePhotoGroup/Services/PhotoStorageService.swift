//
//  PhotoStorageService.swift
//  SharePhotoGroup
//
//  Created by Pavel Mac on 29/04/25
//

import CoreData
import UIKit
import Combine
import Vision

class PhotoStorageService: ObservableObject {
    
    private let context: NSManagedObjectContext
    private let faceLabelingService: FaceLabelingService
    @Published var photos: [ReceivedPhotoModel] = []
    
    init(context: NSManagedObjectContext, faceLabelingService: FaceLabelingService) {
        self.context = context
        self.faceLabelingService = faceLabelingService
        loadPhotos()
    }
    
    func savePhoto(_ image: UIImage, senderName: String?, senderAvatar: UIImage?, recognizedFaces: [RecognizedFace]?) async {
        print("📥 Сохраняем фото...")
        print("   📝 Информация о фото:")
        print("   - Отправитель: \(senderName ?? "неизвестен")")
        print("   - Аватар: \(senderAvatar != nil ? "есть" : "нет")")
        print("   - Распознанные лица: \(recognizedFaces?.count ?? 0)")

        let photo = ReceivedPhotoEntity(context: context)
        let uuid = UUID()
        photo.id = uuid.uuidString
        photo.dateReceived = Date()
        photo.senderName = senderName
        
        // Сохраняем аватарку с максимальным качеством
        if let avatar = senderAvatar {
            if let avatarData = avatar.jpegData(compressionQuality: 1.0) {
                photo.senderAvatar = avatarData
                print("📸 Аватарка отправителя сохранена (размер: \(avatarData.count) байт)")
            } else {
                print("⚠️ Не удалось сконвертировать аватарку в JPEG")
                photo.senderAvatar = nil
            }
        } else {
            photo.senderAvatar = nil
            print("⚠️ Аватарка отправителя отсутствует")
        }
        
        if let imageData = image.jpegData(compressionQuality: 1.0) {
            photo.imageData = imageData
            print("📸 Основное фото сохранено (размер: \(imageData.count) байт)")
            
            // Если переданы распознанные лица, сохраняем их
            if let faces = recognizedFaces {
                print("🎯 Сохраняем \(faces.count) распознанных лиц")
                for face in faces {
                    print("🧠 Сохраняем лицо: \(face.name ?? "Unknown"), confidence: \(face.confidence), source: \(face.source)")
                    let faceEntity = RecognizedFaceEntity(context: context)
                    faceEntity.name = face.name
                    faceEntity.confidence = face.confidence
                    faceEntity.source = face.source.rawValue
                    photo.addToRecognizedFaces(faceEntity)
                    
                    // Если лицо из полученного фото, сохраняем его в FaceLabelingService
                    if face.source == .peer {
                        // Получаем embedding для лица
                        if let faceImage = extractFaceImage(from: image, face: face) {
                            do {
                                let embedding = try faceLabelingService.faceEmbeddingService.getEmbedding(for: faceImage)
                                faceLabelingService.addPeerFace(embedding: embedding, name: face.name, from: "peer")
                                print("✅ Лицо из полученного фото сохранено в FaceLabelingService: \(face.name ?? "Unknown")")
                            } catch {
                                print("❌ Не удалось получить embedding для лица из полученного фото: \(error)")
                            }
                        }
                    }
                }
            } else {
                // Если лица не переданы, пробуем распознать их
                if let faces = await detectFacesAndCompareWithContacts(in: image) {
                    print("🎯 Обнаружено лиц: \(faces.count)")
                    for face in faces {
                        print("🧠 Обнаружено лицо: \(face.name), confidence: \(face.confidence), source: \(face.source)")
                        let faceEntity = RecognizedFaceEntity(context: context)
                        faceEntity.name = face.name
                        faceEntity.confidence = face.confidence
                        faceEntity.source = face.source.rawValue
                        photo.addToRecognizedFaces(faceEntity)
                        
                        // Сохраняем все распознанные лица в FaceLabelingService
                        if let faceImage = extractFaceImage(from: image, face: face) {
                            do {
                                let embedding = try faceLabelingService.faceEmbeddingService.getEmbedding(for: faceImage)
                                faceLabelingService.addPeerFace(embedding: embedding, name: face.name, from: "peer")
                                print("✅ Распознанное лицо сохранено в FaceLabelingService: \(face.name ?? "Unknown")")
                            } catch {
                                print("❌ Не удалось получить embedding для распознанного лица: \(error)")
                            }
                        }
                    }
                } else {
                    print("⚠️ Лица не обнаружены или не распознаны")
                }
            }
            
            do {
                try context.save()
                print("✅ Фото и лица сохранены в Core Data")
                print("   - ID фото: \(photo.id ?? "неизвестен")")
                print("   - Дата: \(photo.dateReceived?.description ?? "неизвестна")")
                print("   - Количество лиц: \(photo.recognizedFaces?.count ?? 0)")
                loadPhotos()
            } catch {
                print("❌ Ошибка при сохранении фото: \(error)")
            }
        } else {
            print("❌ Не удалось сконвертировать фото в JPEG")
        }
    }
    
    func loadPhotos() {
        print("📦 Загружаем фото из Core Data...")
        let request: NSFetchRequest<ReceivedPhotoEntity> = ReceivedPhotoEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ReceivedPhotoEntity.dateReceived, ascending: false)]
        
        do {
            let entities = try context.fetch(request)
            print("📷 Найдено фото: \(entities.count)")
            
            let loadedPhotos = entities.map { entity in
                var photo = ReceivedPhotoModel(
                    id: UUID(uuidString: entity.id ?? "") ?? UUID(),
                    image: entity.imageData.flatMap(UIImage.init),
                    dateReceived: entity.dateReceived,
                    recognizedFaces: [],
                    senderName: entity.senderName,
                    senderAvatar: nil,
                    isShared: entity.isShared,
                    isFavorite: entity.isFavorite
                )
                
                // Загружаем аватарку отправителя
                if let avatarData = entity.senderAvatar {
                    print("📸 Найдены данные аватарки для фото \(entity.id ?? "unknown") (размер: \(avatarData.count) байт)")
                    if let avatar = UIImage(data: avatarData) {
                        photo.senderAvatar = avatar
                        print("✅ Аватарка отправителя успешно загружена")
                    } else {
                        print("⚠️ Не удалось создать UIImage из данных аватарки")
                    }
                }
                
                if let faces = entity.recognizedFaces as? Set<RecognizedFaceEntity> {
                    photo.recognizedFaces = faces.map { face in
                        print("👤 Лицо: \(face.name ?? "Unknown"), confidence: \(face.confidence)")
                        return RecognizedFace(
                            name: face.name ?? "Unknown",
                            confidence: face.confidence,
                            source: LabelSource(rawValue: face.source ?? "") ?? .peer
                        )
                    }
                } else {
                    print("⚠️ Не удалось получить лица для фото")
                }
                
                return photo
            }
            
            DispatchQueue.main.async {
                self.photos = loadedPhotos
                print("✅ Фото успешно загружены в UI. Всего: \(loadedPhotos.count)")
            }
        } catch {
            print("❌ Ошибка при загрузке фото: \(error)")
            DispatchQueue.main.async {
                self.photos = []
            }
        }
    }
    
    func deletePhoto(_ photo: ReceivedPhotoModel) {
        print("🗑️ Удаляем фото: \(photo.id)")
        let request: NSFetchRequest<ReceivedPhotoEntity> = ReceivedPhotoEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", photo.id.uuidString)
        do {
            let results = try context.fetch(request)
            if let entity = results.first {
                context.delete(entity)
                try context.save()
                print("✅ Фото удалено")
                loadPhotos()
            } else {
                print("⚠️ Фото для удаления не найдено")
            }
        } catch {
            print("❌ Ошибка при удалении фото: \(error)")
        }
    }
    private func detectFacesAndCompareWithContacts(in image: UIImage) -> [RecognizedFace]? {
        print("🔍 Запуск распознавания лиц...")
        let faceImage = cropFirstDetectedFace(from: image) ?? cropCenterFace(from: image)
        do {
            let embedding = try faceLabelingService.faceEmbeddingService.getEmbedding(for: faceImage)
            print("🧬 Embedding получен. Длина: \(embedding.count)")
            
            // Проверяем, есть ли известные лица
            let knownFaces = faceLabelingService.getKnownFaces()
            print("📚 Известных лиц в базе: \(knownFaces.count)")
            
            if let match = faceLabelingService.findMatch(for: embedding) {
                if let name = match.name {
                    print("✅ Совпадение найдено: \(name), confidence: \(match.confidence)")
                    if match.confidence > 0.3 {
                        print("✅ Совпадение найдено: \(name), confidence: \(match.confidence). Добавляю фото!")
                        return [RecognizedFace(name: name, confidence: match.confidence, source: match.source)]
                    } else {
                        print("⚠️ Совпадение с низкой уверенностью: \(match.confidence)")
                    }
                }
            } else {
                print("❌ Совпадений не найдено")
            }
        } catch {
            print("❌ Не удалось получить embedding: \(error)")
        }
        return nil
    }
    
    private func cropFirstDetectedFace(from image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            guard let results = request.results as? [VNFaceObservation], let firstFace = results.first else { return nil }
            let boundingBox = firstFace.boundingBox
            let width = CGFloat(cgImage.width)
            let height = CGFloat(cgImage.height)
            let rect = CGRect(
                x: boundingBox.origin.x * width,
                y: (1 - boundingBox.origin.y - boundingBox.height) * height,
                width: boundingBox.width * width,
                height: boundingBox.height * height
            ).integral
            guard let faceCgImage = cgImage.cropping(to: rect) else { return nil }
            return UIImage(cgImage: faceCgImage)
        } catch {
            print("Ошибка Vision face detection: \(error)")
            return nil
        }
    }
    
    private func cropCenterFace(from image: UIImage) -> UIImage {
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
    
    private func extractFaceImage(from image: UIImage, face: RecognizedFace) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        do {
            try handler.perform([request])
            if let results = request.results as? [VNFaceObservation],
               let firstFace = results.first {
                let boundingBox = firstFace.boundingBox
                let x = boundingBox.origin.x * CGFloat(cgImage.width)
                let y = (1 - boundingBox.origin.y - boundingBox.height) * CGFloat(cgImage.height)
                let width = boundingBox.width * CGFloat(cgImage.width)
                let height = boundingBox.height * CGFloat(cgImage.height)
                
                if let croppedCGImage = cgImage.cropping(to: CGRect(x: x, y: y, width: width, height: height)) {
                    return UIImage(cgImage: croppedCGImage)
                }
            }
        } catch {
            print("❌ Ошибка при извлечении лица: \(error)")
        }
        return nil
    }
}
