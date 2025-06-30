//
//  FaceMatcher.swift
//  SharePhotoGroup
//
//  Created by Pavel Mac on 22/04/25
//

import Foundation

struct KnownFaceV2 {
    let id: UUID
    let embedding: [Float]
    let name: String?
    let source: String
}

class FaceMatcher {
    private(set) var knownFaces: [KnownFaceV2] = []
    static let similarityThreshold: Float = 0.01
    
    func addKnownFace(embedding: [Float], name: String?, source: String) {
        let face = KnownFaceV2(id: UUID(), embedding: embedding, name: name, source: source)
        knownFaces.append(face)
        print("НОВАЯ: Добавлено известное лицо: \(name ?? "unknown") (всего: \(knownFaces.count))")
    }
    
    /// Сравнить эмбеддинг с базой, вернуть лучшее совпадение и логи
    func findBestMatch(for embedding: [Float], in store: FaceStore) -> (FaceData, Float)? {
        print("НОВАЯ: Начинаем поиск совпадений среди \(store.faces.count) лиц")
        var bestMatch: (FaceData, Float)?
        var bestSimilarity: Float = 0.0
        
        for (index, face) in store.faces.enumerated() {
            let similarity = FaceMatcher.cosineSimilarity(embedding, face.embedding)
            print("НОВАЯ: Сравнение с лицом \(index + 1): similarity = \(similarity)")
            
            if similarity > bestSimilarity {
                bestSimilarity = similarity
                bestMatch = (face, similarity)
                print("НОВАЯ: Найдено лучшее совпадение: \(similarity)")
            }
        }
        
        if let match = bestMatch {
            print("НОВАЯ: Лучшее совпадение найдено: \(match.1)")
            if match.1 >= FaceMatcher.similarityThreshold {
                return match
            } else {
                print("НОВАЯ: Лучшее совпадение (\(match.1)) ниже порога (\(FaceMatcher.similarityThreshold))")
            }
        } else {
            print("НОВАЯ: Совпадений не найдено")
        }
        
        return nil
    }
    
    static func cosineSimilarity(_ v1: [Float], _ v2: [Float]) -> Float {
        guard v1.count == v2.count else { return 0 }
        var dot: Float = 0, norm1: Float = 0, norm2: Float = 0
        for i in 0..<v1.count {
            dot += v1[i] * v2[i]
            norm1 += v1[i] * v1[i]
            norm2 += v2[i] * v2[i]
        }
        return dot / (sqrt(norm1) * sqrt(norm2))
    }
    
    func clear() {
        knownFaces.removeAll()
        print("НОВАЯ: Очищена база известных лиц")
    }
} 
