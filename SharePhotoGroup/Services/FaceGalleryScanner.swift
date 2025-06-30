//
//  FaceGalleryScanner.swift
//  SharePhotoGroup
//
//  Created by Pavel Mac on 25/04/25
//

import Photos
import Vision
import UIKit

/// Сканирует последние 100 фото из галереи, находит все лица и группирует похожие
/// - Parameters:
///   - faceStore: Хранилище для сохранения найденных лиц
///   - faceEmbeddingService: Сервис для создания эмбеддингов лиц
///   - similarityThreshold: Порог схожести лиц (от 0 до 1, по умолчанию 0.6)
///   - completion: Замыкание, вызываемое после завершения сканирования


func scanLastHundredPhotosAndFillFaceStore(faceStore: FaceStore, faceEmbeddingService: FaceEmbeddingService, similarityThreshold: Float = 0.6, completion: (() -> Void)? = nil) {
    let fetchOptions = PHFetchOptions()
    fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
    fetchOptions.fetchLimit = 100
    let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
    let imageManager = PHImageManager.default()
    let targetSize = CGSize(width: 800, height: 800)
    let options = PHImageRequestOptions()
    options.isSynchronous = true
    
    let group = DispatchGroup()
    print("[Сканирование] Начинаем сканирование последних 100 фотографий")
    
    var allFaces: [FaceData] = []
    
    for i in 0..<assets.count {
        let asset = assets[i]
        group.enter()
        imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, _ in
            defer { group.leave() }
            guard let image = image, let cgImage = image.cgImage else { return }
            
            let request = VNDetectFaceRectanglesRequest { request, error in
                if let error = error {
                    print("[Ошибка] Vision: \(error.localizedDescription)")
                    return
                }
                
                guard let results = request.results as? [VNFaceObservation] else { return }
                
                // Обрабатываем все найденные лица на фото
                for faceObservation in results {
                    // Кроп лица с padding
                    let boundingBox = faceObservation.boundingBox
                    let width = CGFloat(cgImage.width)
                    let height = CGFloat(cgImage.height)
                    let padding: CGFloat = 0.2
                    let rect = CGRect(
                        x: (boundingBox.origin.x - padding) * width,
                        y: (1 - boundingBox.origin.y - boundingBox.height - padding) * height,
                        width: (boundingBox.width + padding * 2) * width,
                        height: (boundingBox.height + padding * 2) * height
                    ).integral
                    
                    // Проверяем, что кроп не выходит за границы изображения
                    let safeRect = CGRect(
                        x: max(0, rect.origin.x),
                        y: max(0, rect.origin.y),
                        width: min(width - rect.origin.x, rect.width),
                        height: min(height - rect.origin.y, rect.height)
                    )
                    
                    guard let faceCgImage = cgImage.cropping(to: safeRect) else {
                        print("[Ошибка] Не удалось кропнуть лицо")
                        continue
                    }
                    
                    let faceImage = UIImage(cgImage: faceCgImage)
                    do {
                        let embedding = try faceEmbeddingService.getEmbedding(for: faceImage)
                        let faceData = FaceData(image: faceImage, fullImage: image, embedding: embedding)
                        allFaces.append(faceData)
                    } catch {
                        print("[Ошибка] Не удалось создать embedding: \(error)")
                    }
                }
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                print("[Ошибка] Vision perform: \(error.localizedDescription)")
            }
        }
    }
    
    group.notify(queue: .main) {
        print("[Прогресс] Найдено всего лиц: \(allFaces.count)")
        
        // Группируем похожие лица
        var groupedFaces: [[FaceData]] = []
        var processedIndices = Set<Int>()
        
        for i in 0..<allFaces.count {
            if processedIndices.contains(i) { continue }
            
            var currentGroup: [FaceData] = [allFaces[i]]
            processedIndices.insert(i)
            
            for j in (i + 1)..<allFaces.count {
                if processedIndices.contains(j) { continue }
                
                let similarity = cosineSimilarity(allFaces[i].embedding, allFaces[j].embedding)
                if similarity >= similarityThreshold {
                    currentGroup.append(allFaces[j])
                    processedIndices.insert(j)
                }
            }
            
            if currentGroup.count > 1 {
                groupedFaces.append(currentGroup)
            }
        }
        
        // Добавляем группы похожих лиц в faceStore
        for group in groupedFaces {
            faceStore.add(group)
        }
        
        print("[Завершение] Сканирование завершено 100")
        print("[Статистика] Найдено групп похожих лиц: \(groupedFaces.count)")
        for (index, group) in groupedFaces.enumerated() {
            print("[Группа \(index + 1)] Количество похожих лиц: \(group.count)")
        }
        
        completion?()
    }
}

// Вспомогательная функция для вычисления косинусного сходства между эмбеддингами
private func cosineSimilarity(_ embedding1: [Float], _ embedding2: [Float]) -> Float {
    guard embedding1.count == embedding2.count else { return 0 }
    
    var dotProduct: Float = 0
    var norm1: Float = 0
    var norm2: Float = 0
    
    for i in 0..<embedding1.count {
        dotProduct += embedding1[i] * embedding2[i]
        norm1 += embedding1[i] * embedding1[i]
        norm2 += embedding2[i] * embedding2[i]
    }
    
    norm1 = sqrt(norm1)
    norm2 = sqrt(norm2)
    
    guard norm1 > 0 && norm2 > 0 else { return 0 }
    return dotProduct / (norm1 * norm2)
}

