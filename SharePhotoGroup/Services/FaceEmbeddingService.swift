//
//  Theme.swift
//  SharePhotoGroup
//
//  Created by Pavel Mac on 25/04/25
//

import CoreML
import UIKit
import Combine

// Enum для ошибок
enum FaceEmbeddingError: Error {
    case invalidImage
    case processingError
    case modelError
    
    var localizedDescription: String {
        switch self {
        case .invalidImage:
            return "Invalid image format or quality"
        case .processingError:
            return "Could not process the image"
        case .modelError:
            return "Error in model processing"
        }
    }
}

// Структура для хранения метаданных изображения
struct ImageMetadata {
    let quality: Float
    let brightness: Float
    let contrast: Float
    let isBlurred: Bool
}

class FaceEmbeddingService: ObservableObject {
    private let model: Facenet6

    // Константы для предобработки
    private let targetSize = CGSize(width: 160, height: 160) // FaceNet использует 160x160
    private let imageNetMean: [Float] = [0.485, 0.456, 0.406]
    private let imageNetStd: [Float] = [0.229, 0.224, 0.225]
    
    init() {
        do {
             
            
            // Пытаемся загрузить модель
            do {
                        self.model = try Facenet6(configuration: MLModelConfiguration())
                        print("[FaceEmbeddingService] Facenet6 model loaded successfully")
                    } catch {
                        print("[FaceEmbeddingService] Failed to load Facenet6 model: \(error.localizedDescription)")
                        fatalError("Failed to initialize FaceEmbeddingService: \(error.localizedDescription)")
                    }
        } catch {
            print("[FaceEmbeddingService] Initialization failed: \(error.localizedDescription)")
            fatalError("Failed to initialize FaceEmbeddingService: \(error.localizedDescription)")
        }
    }
    
    func getEmbedding(for image: UIImage) throws -> [Float] {
        // Проверяем качество изображения
        let metadata = checkImageQuality(image)
        guard metadata.quality >= 0.7 else {
            print("[FaceEmbeddingService] Изображение не прошло проверку качества: \(metadata)")
            throw FaceEmbeddingError.invalidImage
        }
        
        // Преобразуем UIImage в MLMultiArray с улучшенной нормализацией
        let multiArray = try imageToMLMultiArray(image)
        
        do {
            let input = Facenet6Input(input: multiArray)
            let output = try model.prediction(input: input)
            let embedding = output.embeddings
            
            // Преобразуем MLMultiArray в [Float] с улучшенной нормализацией
            var result = [Float](repeating: 0, count: embedding.count)
            for i in 0..<embedding.count {
                result[i] = Float(truncating: embedding[i])
            }
            
            // L2 нормализация эмбеддинга
            let norm = sqrt(result.reduce(0) { $0 + $1 * $1 })
            if norm > 0 {
                result = result.map { $0 / norm }
            }
            
            return result
        } catch {
            print("[FaceEmbeddingService] Ошибка при обработке изображения: \(error)")
            throw FaceEmbeddingError.processingError
        }
    }
    
    func calculateSimilarity(_ embedding1: [Float], _ embedding2: [Float]) -> Float {
        // 1. Предварительная обработка эмбеддингов
        let processedEmbedding1 = preprocessEmbedding(embedding1)
        let processedEmbedding2 = preprocessEmbedding(embedding2)
        
        // 2. Вычисление базовых метрик
        let cosineSimilarity = calculateCosineSimilarity(processedEmbedding1, processedEmbedding2)
        let euclideanSimilarity = calculateEuclideanSimilarity(processedEmbedding1, processedEmbedding2)
        let manhattanSimilarity = calculateManhattanSimilarity(processedEmbedding1, processedEmbedding2)
        let pearsonSimilarity = calculatePearsonSimilarity(processedEmbedding1, processedEmbedding2)
        
        // 3. Вычисление продвинутых метрик
        let mahalanobisSimilarity = calculateMahalanobisSimilarity(processedEmbedding1, processedEmbedding2)
        let jaccardSimilarity = calculateJaccardSimilarity(processedEmbedding1, processedEmbedding2)
        let chebyshevSimilarity = calculateChebyshevSimilarity(processedEmbedding1, processedEmbedding2)
        let canberraSimilarity = calculateCanberraSimilarity(processedEmbedding1, processedEmbedding2)
        
        // 4. Комбинируем все метрики с весами
        let weights: [Float] = [0.25, 0.15, 0.1, 0.1, 0.15, 0.1, 0.05, 0.1]
        let similarities = [
            cosineSimilarity,
            euclideanSimilarity,
            manhattanSimilarity,
            pearsonSimilarity,
            mahalanobisSimilarity,
            jaccardSimilarity,
            chebyshevSimilarity,
            canberraSimilarity
        ]
        
        // 5. Вычисляем взвешенную сумму
        let weightedSum = zip(similarities, weights).map(*).reduce(0, +)
        
        // 6. Применяем нелинейное преобразование для усиления различий
        let similarity = enhancedSigmoid(weightedSum)
        
        // 7. Применяем пороговую функцию для четкого разделения
        return applyThreshold(similarity)
    }
    
    private func preprocessEmbedding(_ embedding: [Float]) -> [Float] {
        // 1. Нормализация L2
        let norm = sqrt(embedding.map { $0 * $0 }.reduce(0, +))
        let normalized = embedding.map { $0 / norm }
        
        // 2. Удаление шума (сглаживание)
        let smoothed = smoothEmbedding(normalized)
        
        // 3. Усиление важных признаков
        return enhanceFeatures(smoothed)
    }
    
    private func smoothEmbedding(_ embedding: [Float]) -> [Float] {
        let windowSize = 3
        var smoothed = [Float](repeating: 0, count: embedding.count)
        
        for i in 0..<embedding.count {
            var sum: Float = 0
            var count = 0
            
            for j in max(0, i - windowSize)...min(embedding.count - 1, i + windowSize) {
                sum += embedding[j]
                count += 1
            }
            
            smoothed[i] = sum / Float(count)
        }
        
        return smoothed
    }
    
    private func enhanceFeatures(_ embedding: [Float]) -> [Float] {
        // Усиливаем важные признаки (первые 128 измерений обычно содержат основные черты лица)
        var enhanced = embedding
        let importantRange = 0..<min(128, embedding.count)
        
        for i in importantRange {
            enhanced[i] *= 1.2 // Усиливаем важные признаки
        }
        
        return enhanced
    }
    
    private func calculateMahalanobisSimilarity(_ v1: [Float], _ v2: [Float]) -> Float {
        guard v1.count == v2.count else { return 0 }
        
        // Упрощенная версия расстояния Махаланобиса
        var sumSquaredDiff: Float = 0
        var sumVariance: Float = 0
        
        for i in 0..<v1.count {
            let diff = v1[i] - v2[i]
            sumSquaredDiff += diff * diff
            sumVariance += (v1[i] * v1[i] + v2[i] * v2[i]) / 2
        }
        
        guard sumVariance > 0 else { return 0 }
        let distance = sqrt(sumSquaredDiff / sumVariance)
        return 1 / (1 + distance)
    }
    
    private func calculateJaccardSimilarity(_ v1: [Float], _ v2: [Float]) -> Float {
        guard v1.count == v2.count else { return 0 }
        
        var intersection: Float = 0
        var union: Float = 0
        
        for i in 0..<v1.count {
            intersection += min(v1[i], v2[i])
            union += max(v1[i], v2[i])
        }
        
        guard union > 0 else { return 0 }
        return intersection / union
    }
    
    private func calculateChebyshevSimilarity(_ v1: [Float], _ v2: [Float]) -> Float {
        guard v1.count == v2.count else { return 0 }
        
        var maxDiff: Float = 0
        for i in 0..<v1.count {
            maxDiff = max(maxDiff, abs(v1[i] - v2[i]))
        }
        
        return 1 / (1 + maxDiff)
    }
    
    private func calculateCanberraSimilarity(_ v1: [Float], _ v2: [Float]) -> Float {
        guard v1.count == v2.count else { return 0 }
        
        var sum: Float = 0
        for i in 0..<v1.count {
            let denominator = abs(v1[i]) + abs(v2[i])
            if denominator > 0 {
                sum += abs(v1[i] - v2[i]) / denominator
            }
        }
        
        return 1 / (1 + sum)
    }
    
    private func enhancedSigmoid(_ x: Float) -> Float {
        // Улучшенная сигмоидная функция с более крутым наклоном
        let k: Float = 8.0 // Коэффициент крутизны
        return 1 / (1 + exp(-k * (x - 0.5)))
    }
    
    private func applyThreshold(_ similarity: Float) -> Float {
        // Пороговая функция для четкого разделения
        if similarity > 0.8 {
            return 0.9 + (similarity - 0.8) * 0.5 // Усиливаем высокие значения
        } else if similarity < 0.3 {
            return similarity * 0.5 // Ослабляем низкие значения
        }
        return similarity
    }
    
    private func calculateCosineSimilarity(_ v1: [Float], _ v2: [Float]) -> Float {
        guard v1.count == v2.count else { return 0 }
        
        var dotProduct: Float = 0
        var norm1: Float = 0
        var norm2: Float = 0
        
        for i in 0..<v1.count {
            dotProduct += v1[i] * v2[i]
            norm1 += v1[i] * v1[i]
            norm2 += v2[i] * v2[i]
        }
        
        guard norm1 > 0 && norm2 > 0 else { return 0 }
        return dotProduct / (sqrt(norm1) * sqrt(norm2))
    }
    
    private func calculateEuclideanSimilarity(_ v1: [Float], _ v2: [Float]) -> Float {
        guard v1.count == v2.count else { return 0 }
        
        var sumSquaredDiff: Float = 0
        for i in 0..<v1.count {
            let diff = v1[i] - v2[i]
            sumSquaredDiff += diff * diff
        }
        
        let distance = sqrt(sumSquaredDiff)
        let maxDistance = sqrt(Float(v1.count)) // Максимально возможное расстояние
        return 1 - (distance / maxDistance)
    }
    
    private func calculateManhattanSimilarity(_ v1: [Float], _ v2: [Float]) -> Float {
        guard v1.count == v2.count else { return 0 }
        
        var sumAbsDiff: Float = 0
        for i in 0..<v1.count {
            sumAbsDiff += abs(v1[i] - v2[i])
        }
        
        let maxDistance = Float(v1.count) // Максимально возможное расстояние
        return 1 - (sumAbsDiff / maxDistance)
    }
    
    private func calculatePearsonSimilarity(_ v1: [Float], _ v2: [Float]) -> Float {
        guard v1.count == v2.count else { return 0 }
        
        let n = Float(v1.count)
        var sum1: Float = 0, sum2: Float = 0
        var sum1Sq: Float = 0, sum2Sq: Float = 0
        var pSum: Float = 0
        
        for i in 0..<v1.count {
            sum1 += v1[i]
            sum2 += v2[i]
            sum1Sq += v1[i] * v1[i]
            sum2Sq += v2[i] * v2[i]
            pSum += v1[i] * v2[i]
        }
        
        let num = pSum - (sum1 * sum2 / n)
        let den = sqrt((sum1Sq - sum1 * sum1 / n) * (sum2Sq - sum2 * sum2 / n))
        
        guard den != 0 else { return 0 }
        return (num / den + 1) / 2 // Преобразуем в диапазон [0, 1]
    }
    
    private func checkImageQuality(_ image: UIImage) -> ImageMetadata {
        let brightness = calculateBrightness(image)
        let contrast = calculateContrast(image)
        let isBlurred = detectBlur(image)
        
        // Рассчитываем общее качество
        var quality: Float = 1.0
        
        // Штраф за низкую яркость
        if brightness < 0.3 {
            quality *= 0.7
        } else if brightness < 0.5 {
            quality *= 0.85
        }
        
        // Штраф за низкий контраст
        if contrast < 0.3 {
            quality *= 0.7
        } else if contrast < 0.5 {
            quality *= 0.85
        }
        
        // Штраф за размытие
//        if isBlurred {
//            quality *= 0.6
//        }
        
        return ImageMetadata(
            quality: quality,
            brightness: brightness,
            contrast: contrast,
            isBlurred: isBlurred
        )
    }
    
    private func calculateBrightness(_ image: UIImage) -> Float {
        guard let cgImage = image.cgImage else { return 0 }
        
        let width = cgImage.width
        let height = cgImage.height
        let totalPixels = width * height
        
        var totalBrightness: Float = 0
        
        guard let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return 0
        }
        
        let bytesPerPixel = 4
        let bytesPerRow = cgImage.bytesPerRow
        
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let r = Float(bytes[offset]) / 255.0
                let g = Float(bytes[offset + 1]) / 255.0
                let b = Float(bytes[offset + 2]) / 255.0
                
                // Формула для расчета яркости
                let brightness = (0.299 * r + 0.587 * g + 0.114 * b)
                totalBrightness += brightness
            }
        }
        
        return totalBrightness / Float(totalPixels)
    }
    
    private func calculateContrast(_ image: UIImage) -> Float {
        guard let cgImage = image.cgImage else { return 0 }
        
        let width = cgImage.width
        let height = cgImage.height
        
        guard let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return 0
        }
        
        let bytesPerPixel = 4
        let bytesPerRow = cgImage.bytesPerRow
        
        var minBrightness: Float = 1.0
        var maxBrightness: Float = 0.0
        
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let r = Float(bytes[offset]) / 255.0
                let g = Float(bytes[offset + 1]) / 255.0
                let b = Float(bytes[offset + 2]) / 255.0
                
                let brightness = (0.299 * r + 0.587 * g + 0.114 * b)
                minBrightness = min(minBrightness, brightness)
                maxBrightness = max(maxBrightness, brightness)
            }
        }
        
        return maxBrightness - minBrightness
    }
    
    private func detectBlur(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return true }
        
        let width = cgImage.width
        let height = cgImage.height
        
        guard let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return true
        }
        
        let bytesPerPixel = 4
        let bytesPerRow = cgImage.bytesPerRow
        
        var totalLaplacian: Float = 0
        
        for y in 1..<height-1 {
            for x in 1..<width-1 {
                let offset = y * bytesPerRow + x * bytesPerPixel
                
                // Получаем значения яркости соседних пикселей
                let center = Float(bytes[offset]) / 255.0
                let top = Float(bytes[offset - bytesPerRow]) / 255.0
                let bottom = Float(bytes[offset + bytesPerRow]) / 255.0
                let left = Float(bytes[offset - bytesPerPixel]) / 255.0
                let right = Float(bytes[offset + bytesPerPixel]) / 255.0
                
                // Вычисляем лапласиан
                let laplacian = abs(4 * center - top - bottom - left - right)
                totalLaplacian += laplacian
            }
        }
        
        let averageLaplacian = totalLaplacian / Float((width - 2) * (height - 2))
        return averageLaplacian < 0.1 // Порог для определения размытия
    }
    
    // Преобразование UIImage в MLMultiArray для Facenet6
    private func imageToMLMultiArray(_ image: UIImage) throws -> MLMultiArray {
        guard let cgImage = image.cgImage else {
            throw FaceEmbeddingError.invalidImage
        }
        
        // Размеры для Facenet6
        let width = 160
        let height = 160
        
        // Создаем MLMultiArray
        let array = try MLMultiArray(shape: [1, height as NSNumber, width as NSNumber, 3 as NSNumber], dataType: .float32)
        
        // Создаем контекст для рисования
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        
        // Рисуем изображение в контексте
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let data = context?.data else {
            throw FaceEmbeddingError.processingError
        }
        
        let ptr = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        
        // Нормализация пикселей в диапазон [-1, 1]
        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = (y * width + x) * 4
                let r = Float(ptr[pixelIndex + 0]) / 255.0
                let g = Float(ptr[pixelIndex + 1]) / 255.0
                let b = Float(ptr[pixelIndex + 2]) / 255.0
                
                // Нормализация в диапазон [-1, 1]
                let normR = (r - 0.5) * 2.0
                let normG = (g - 0.5) * 2.0
                let normB = (b - 0.5) * 2.0
                
                array[[0, y as NSNumber, x as NSNumber, 0]] = NSNumber(value: normR)
                array[[0, y as NSNumber, x as NSNumber, 1]] = NSNumber(value: normG)
                array[[0, y as NSNumber, x as NSNumber, 2]] = NSNumber(value: normB)
            }
        }
        
        return array
    }
}

// Расширение для UIImage
extension UIImage {
    func resize(to size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        defer { UIGraphicsEndImageContext() }
        
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
    
    func toPixelBuffer() -> CVPixelBuffer? {
        let width = Int(size.width)
        let height = Int(size.height)
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            nil,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        )
        
        context?.draw(cgImage!, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        return buffer
    }
}

//import CoreML
//import UIKit
//import Combine
//
//// Enum для ошибок
//enum FaceEmbeddingError: Error {
//    case invalidImage
//    case processingError
//    case modelError
//    
//    var localizedDescription: String {
//        switch self {
//        case .invalidImage:
//            return "Invalid image format or quality"
//        case .processingError:
//            return "Could not process the image"
//        case .modelError:
//            return "Error in model processing"
//        }
//    }
//}
//
//// Структура для хранения метаданных изображения
//struct ImageMetadata {
//    let quality: Float
//    let brightness: Float
//    let contrast: Float
//    let isBlurred: Bool
//}
//
//class FaceEmbeddingService: ObservableObject {
//    private let model: Facenet6
//
//    // Константы для предобработки
//    private let targetSize = CGSize(width: 160, height: 160) // FaceNet использует 160x160
//    private let imageNetMean: [Float] = [0.485, 0.456, 0.406]
//    private let imageNetStd: [Float] = [0.229, 0.224, 0.225]
//    
//    init() {
//        do {
//             
//            
//            // Пытаемся загрузить модель
//            do {
//                        self.model = try Facenet6(configuration: MLModelConfiguration())
//                        print("[FaceEmbeddingService] Facenet6 model loaded successfully")
//                    } catch {
//                        print("[FaceEmbeddingService] Failed to load Facenet6 model: \(error.localizedDescription)")
//                        fatalError("Failed to initialize FaceEmbeddingService: \(error.localizedDescription)")
//                    }
//        } catch {
//            print("[FaceEmbeddingService] Initialization failed: \(error.localizedDescription)")
//            fatalError("Failed to initialize FaceEmbeddingService: \(error.localizedDescription)")
//        }
//    }
//    
//    func getEmbedding(for image: UIImage) throws -> [Float] {
//        // Проверяем качество изображения
//        let metadata = checkImageQuality(image)
//        guard metadata.quality >= 0.7 else {
//            print("[FaceEmbeddingService] Изображение не прошло проверку качества: \(metadata)")
//            throw FaceEmbeddingError.invalidImage
//        }
//        
//        // Преобразуем UIImage в MLMultiArray с улучшенной нормализацией
//        let multiArray = try imageToMLMultiArray(image)
//        
//        do {
//            let input = Facenet6Input(input: multiArray)
//            let output = try model.prediction(input: input)
//            let embedding = output.embeddings
//            
//            // Преобразуем MLMultiArray в [Float] с улучшенной нормализацией
//            var result = [Float](repeating: 0, count: embedding.count)
//            for i in 0..<embedding.count {
//                result[i] = Float(truncating: embedding[i])
//            }
//            
//            // L2 нормализация эмбеддинга
//            let norm = sqrt(result.reduce(0) { $0 + $1 * $1 })
//            if norm > 0 {
//                result = result.map { $0 / norm }
//            }
//            
//            return result
//        } catch {
//            print("[FaceEmbeddingService] Ошибка при обработке изображения: \(error)")
//            throw FaceEmbeddingError.processingError
//        }
//    }
//    
//    func calculateSimilarity(_ embedding1: [Float], _ embedding2: [Float]) -> Float {
//        // 1. Косинусное сходство с L2 нормализацией
//        let cosineSimilarity = calculateCosineSimilarity(embedding1, embedding2)
//        
//        // 2. Нормализованное евклидово расстояние
//        let euclideanSimilarity = calculateEuclideanSimilarity(embedding1, embedding2)
//        
//        // 3. Манхэттенское расстояние (L1 норма)
//        let manhattanSimilarity = calculateManhattanSimilarity(embedding1, embedding2)
//        
//        // 4. Корреляция Пирсона
//        let pearsonSimilarity = calculatePearsonSimilarity(embedding1, embedding2)
//        
//        // Комбинируем метрики с весами
//        let weights: [Float] = [0.4, 0.3, 0.2, 0.1] // Веса для каждой метрики
//        let similarities = [cosineSimilarity, euclideanSimilarity, manhattanSimilarity, pearsonSimilarity]
//        
//        // Вычисляем взвешенную сумму
//        let weightedSum = zip(similarities, weights).map(*).reduce(0, +)
//        
//        // Применяем нелинейное преобразование для усиления различий
//        return sigmoid(weightedSum)
//    }
//    
//    private func calculateCosineSimilarity(_ v1: [Float], _ v2: [Float]) -> Float {
//        guard v1.count == v2.count else { return 0 }
//        
//        var dotProduct: Float = 0
//        var norm1: Float = 0
//        var norm2: Float = 0
//        
//        for i in 0..<v1.count {
//            dotProduct += v1[i] * v2[i]
//            norm1 += v1[i] * v1[i]
//            norm2 += v2[i] * v2[i]
//        }
//        
//        guard norm1 > 0 && norm2 > 0 else { return 0 }
//        return dotProduct / (sqrt(norm1) * sqrt(norm2))
//    }
//    
//    private func calculateEuclideanSimilarity(_ v1: [Float], _ v2: [Float]) -> Float {
//        guard v1.count == v2.count else { return 0 }
//        
//        var sumSquaredDiff: Float = 0
//        for i in 0..<v1.count {
//            let diff = v1[i] - v2[i]
//            sumSquaredDiff += diff * diff
//        }
//        
//        let distance = sqrt(sumSquaredDiff)
//        let maxDistance = sqrt(Float(v1.count)) // Максимально возможное расстояние
//        return 1 - (distance / maxDistance)
//    }
//    
//    private func calculateManhattanSimilarity(_ v1: [Float], _ v2: [Float]) -> Float {
//        guard v1.count == v2.count else { return 0 }
//        
//        var sumAbsDiff: Float = 0
//        for i in 0..<v1.count {
//            sumAbsDiff += abs(v1[i] - v2[i])
//        }
//        
//        let maxDistance = Float(v1.count) // Максимально возможное расстояние
//        return 1 - (sumAbsDiff / maxDistance)
//    }
//    
//    private func calculatePearsonSimilarity(_ v1: [Float], _ v2: [Float]) -> Float {
//        guard v1.count == v2.count else { return 0 }
//        
//        let n = Float(v1.count)
//        var sum1: Float = 0, sum2: Float = 0
//        var sum1Sq: Float = 0, sum2Sq: Float = 0
//        var pSum: Float = 0
//        
//        for i in 0..<v1.count {
//            sum1 += v1[i]
//            sum2 += v2[i]
//            sum1Sq += v1[i] * v1[i]
//            sum2Sq += v2[i] * v2[i]
//            pSum += v1[i] * v2[i]
//        }
//        
//        let num = pSum - (sum1 * sum2 / n)
//        let den = sqrt((sum1Sq - sum1 * sum1 / n) * (sum2Sq - sum2 * sum2 / n))
//        
//        guard den != 0 else { return 0 }
//        return (num / den + 1) / 2 // Преобразуем в диапазон [0, 1]
//    }
//    
//    private func sigmoid(_ x: Float) -> Float {
//        return 1 / (1 + exp(-x))
//    }
//    
//    private func checkImageQuality(_ image: UIImage) -> ImageMetadata {
//        let brightness = calculateBrightness(image)
//        let contrast = calculateContrast(image)
//        let isBlurred = detectBlur(image)
//        
//        // Рассчитываем общее качество
//        var quality: Float = 1.0
//        
//        // Штраф за низкую яркость
//        if brightness < 0.3 {
//            quality *= 0.7
//        } else if brightness < 0.5 {
//            quality *= 0.85
//        }
//        
//        // Штраф за низкий контраст
//        if contrast < 0.3 {
//            quality *= 0.7
//        } else if contrast < 0.5 {
//            quality *= 0.85
//        }
//        
//        // Штраф за размытие
////        if isBlurred {
////            quality *= 0.6
////        }
//        
//        return ImageMetadata(
//            quality: quality,
//            brightness: brightness,
//            contrast: contrast,
//            isBlurred: isBlurred
//        )
//    }
//    
//    private func calculateBrightness(_ image: UIImage) -> Float {
//        guard let cgImage = image.cgImage else { return 0 }
//        
//        let width = cgImage.width
//        let height = cgImage.height
//        let totalPixels = width * height
//        
//        var totalBrightness: Float = 0
//        
//        guard let data = cgImage.dataProvider?.data,
//              let bytes = CFDataGetBytePtr(data) else {
//            return 0
//        }
//        
//        let bytesPerPixel = 4
//        let bytesPerRow = cgImage.bytesPerRow
//        
//        for y in 0..<height {
//            for x in 0..<width {
//                let offset = y * bytesPerRow + x * bytesPerPixel
//                let r = Float(bytes[offset]) / 255.0
//                let g = Float(bytes[offset + 1]) / 255.0
//                let b = Float(bytes[offset + 2]) / 255.0
//                
//                // Формула для расчета яркости
//                let brightness = (0.299 * r + 0.587 * g + 0.114 * b)
//                totalBrightness += brightness
//            }
//        }
//        
//        return totalBrightness / Float(totalPixels)
//    }
//    
//    private func calculateContrast(_ image: UIImage) -> Float {
//        guard let cgImage = image.cgImage else { return 0 }
//        
//        let width = cgImage.width
//        let height = cgImage.height
//        
//        guard let data = cgImage.dataProvider?.data,
//              let bytes = CFDataGetBytePtr(data) else {
//            return 0
//        }
//        
//        let bytesPerPixel = 4
//        let bytesPerRow = cgImage.bytesPerRow
//        
//        var minBrightness: Float = 1.0
//        var maxBrightness: Float = 0.0
//        
//        for y in 0..<height {
//            for x in 0..<width {
//                let offset = y * bytesPerRow + x * bytesPerPixel
//                let r = Float(bytes[offset]) / 255.0
//                let g = Float(bytes[offset + 1]) / 255.0
//                let b = Float(bytes[offset + 2]) / 255.0
//                
//                let brightness = (0.299 * r + 0.587 * g + 0.114 * b)
//                minBrightness = min(minBrightness, brightness)
//                maxBrightness = max(maxBrightness, brightness)
//            }
//        }
//        
//        return maxBrightness - minBrightness
//    }
//    
//    private func detectBlur(_ image: UIImage) -> Bool {
//        guard let cgImage = image.cgImage else { return true }
//        
//        let width = cgImage.width
//        let height = cgImage.height
//        
//        guard let data = cgImage.dataProvider?.data,
//              let bytes = CFDataGetBytePtr(data) else {
//            return true
//        }
//        
//        let bytesPerPixel = 4
//        let bytesPerRow = cgImage.bytesPerRow
//        
//        var totalLaplacian: Float = 0
//        
//        for y in 1..<height-1 {
//            for x in 1..<width-1 {
//                let offset = y * bytesPerRow + x * bytesPerPixel
//                
//                // Получаем значения яркости соседних пикселей
//                let center = Float(bytes[offset]) / 255.0
//                let top = Float(bytes[offset - bytesPerRow]) / 255.0
//                let bottom = Float(bytes[offset + bytesPerRow]) / 255.0
//                let left = Float(bytes[offset - bytesPerPixel]) / 255.0
//                let right = Float(bytes[offset + bytesPerPixel]) / 255.0
//                
//                // Вычисляем лапласиан
//                let laplacian = abs(4 * center - top - bottom - left - right)
//                totalLaplacian += laplacian
//            }
//        }
//        
//        let averageLaplacian = totalLaplacian / Float((width - 2) * (height - 2))
//        return averageLaplacian < 0.1 // Порог для определения размытия
//    }
//    
//    // Преобразование UIImage в MLMultiArray для Facenet6
//    private func imageToMLMultiArray(_ image: UIImage) throws -> MLMultiArray {
//        guard let cgImage = image.cgImage else {
//            throw FaceEmbeddingError.invalidImage
//        }
//        
//        // Размеры для Facenet6
//        let width = 160
//        let height = 160
//        
//        // Создаем MLMultiArray
//        let array = try MLMultiArray(shape: [1, height as NSNumber, width as NSNumber, 3 as NSNumber], dataType: .float32)
//        
//        // Создаем контекст для рисования
//        let colorSpace = CGColorSpaceCreateDeviceRGB()
//        let context = CGContext(
//            data: nil,
//            width: width,
//            height: height,
//            bitsPerComponent: 8,
//            bytesPerRow: width * 4,
//            space: colorSpace,
//            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
//        )
//        
//        // Рисуем изображение в контексте
//        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
//        
//        guard let data = context?.data else {
//            throw FaceEmbeddingError.processingError
//        }
//        
//        let ptr = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
//        
//        // Нормализация пикселей в диапазон [-1, 1]
//        for y in 0..<height {
//            for x in 0..<width {
//                let pixelIndex = (y * width + x) * 4
//                let r = Float(ptr[pixelIndex + 0]) / 255.0
//                let g = Float(ptr[pixelIndex + 1]) / 255.0
//                let b = Float(ptr[pixelIndex + 2]) / 255.0
//                
//                // Нормализация в диапазон [-1, 1]
//                let normR = (r - 0.5) * 2.0
//                let normG = (g - 0.5) * 2.0
//                let normB = (b - 0.5) * 2.0
//                
//                array[[0, y as NSNumber, x as NSNumber, 0]] = NSNumber(value: normR)
//                array[[0, y as NSNumber, x as NSNumber, 1]] = NSNumber(value: normG)
//                array[[0, y as NSNumber, x as NSNumber, 2]] = NSNumber(value: normB)
//            }
//        }
//        
//        return array
//    }
//}
//
//// Расширение для UIImage
//extension UIImage {
//    func resize(to size: CGSize) -> UIImage? {
//        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
//        defer { UIGraphicsEndImageContext() }
//        
//        draw(in: CGRect(origin: .zero, size: size))
//        return UIGraphicsGetImageFromCurrentImageContext()
//    }
//    
//    func toPixelBuffer() -> CVPixelBuffer? {
//        let width = Int(size.width)
//        let height = Int(size.height)
//        
//        var pixelBuffer: CVPixelBuffer?
//        let status = CVPixelBufferCreate(
//            kCFAllocatorDefault,
//            width,
//            height,
//            kCVPixelFormatType_32ARGB,
//            nil,
//            &pixelBuffer
//        )
//        
//        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
//            return nil
//        }
//        
//        CVPixelBufferLockBaseAddress(buffer, [])
//        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
//        
//        let context = CGContext(
//            data: CVPixelBufferGetBaseAddress(buffer),
//            width: width,
//            height: height,
//            bitsPerComponent: 8,
//            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
//            space: CGColorSpaceCreateDeviceRGB(),
//            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
//        )
//        
//        context?.draw(cgImage!, in: CGRect(x: 0, y: 0, width: width, height: height))
//        
//        return buffer
//    }
//}

//import CoreML
//import UIKit
//import Combine
//
//// Enum для ошибок
//enum FaceEmbeddingError: Error {
//    case invalidImage
//    case processingError
//    case modelError
//    
//    var localizedDescription: String {
//        switch self {
//        case .invalidImage:
//            return "Invalid image format or quality"
//        case .processingError:
//            return "Could not process the image"
//        case .modelError:
//            return "Error in model processing"
//        }
//    }
//}
//
//// Структура для хранения метаданных изображения
//struct ImageMetadata {
//    let quality: Float
//    let brightness: Float
//    let contrast: Float
//    let isBlurred: Bool
//}
//
//class FaceEmbeddingService: ObservableObject {
//    private let model: Facenet6
//
//    // Константы для предобработки
//    private let targetSize = CGSize(width: 160, height: 160) // FaceNet использует 160x160
//    private let imageNetMean: [Float] = [0.485, 0.456, 0.406]
//    private let imageNetStd: [Float] = [0.229, 0.224, 0.225]
//    
//    init() {
//        do {
//             
//            
//            // Пытаемся загрузить модель
//            do {
//                        self.model = try Facenet6(configuration: MLModelConfiguration())
//                        print("[FaceEmbeddingService] Facenet6 model loaded successfully")
//                    } catch {
//                        print("[FaceEmbeddingService] Failed to load Facenet6 model: \(error.localizedDescription)")
//                        fatalError("Failed to initialize FaceEmbeddingService: \(error.localizedDescription)")
//                    }
//        } catch {
//            print("[FaceEmbeddingService] Initialization failed: \(error.localizedDescription)")
//            fatalError("Failed to initialize FaceEmbeddingService: \(error.localizedDescription)")
//        }
//    }
//    
//    func getEmbedding(for image: UIImage) throws -> [Float] {
//        // Проверяем качество изображения
//        let metadata = checkImageQuality(image)
//        guard metadata.quality >= 0.7 else {
//            print("[FaceEmbeddingService] Изображение не прошло проверку качества: \(metadata)")
//            throw FaceEmbeddingError.invalidImage
//        }
//        
//        // Преобразуем UIImage в MLMultiArray
//        let multiArray = try imageToMLMultiArray(image)
//        
//        do {
//            let input = Facenet6Input(input: multiArray)
//            let output = try model.prediction(input: input)
//            let embedding = output.embeddings
//            
//            // Преобразуем MLMultiArray в [Float]
//            var result = [Float](repeating: 0, count: embedding.count)
//            for i in 0..<embedding.count {
//                result[i] = Float(truncating: embedding[i])
//            }
//            // Нормализуем embedding
//            let norm = sqrt(result.reduce(0) { $0 + $1 * $1 })
//            if norm > 0 {
//                result = result.map { $0 / norm }
//            }
//        return result
//        } catch {
//            print("[FaceEmbeddingService] Ошибка при обработке изображения: \(error)")
//            throw FaceEmbeddingError.processingError
//        }
//    }
//    
//    func calculateSimilarity(_ embedding1: [Float], _ embedding2: [Float]) -> Float {
//        // Косинусное сходство
//        let dotProduct = zip(embedding1, embedding2).map(*).reduce(0, +)
//        let norm1 = sqrt(embedding1.map { $0 * $0 }.reduce(0, +))
//        let norm2 = sqrt(embedding2.map { $0 * $0 }.reduce(0, +))
//        
//        let cosineSimilarity = dotProduct / (norm1 * norm2)
//        
//        // Евклидово расстояние
//        let euclideanDistance = sqrt(zip(embedding1, embedding2).map { pow($0 - $1, 2) }.reduce(0, +))
//        let maxDistance = sqrt(Float(embedding1.count)) // Максимально возможное расстояние
//        let normalizedDistance = 1 - (euclideanDistance / maxDistance)
//        
//        // Комбинированная метрика
//        return (cosineSimilarity + normalizedDistance) / 2
//    }
//    
//    private func checkImageQuality(_ image: UIImage) -> ImageMetadata {
//        let brightness = calculateBrightness(image)
//        let contrast = calculateContrast(image)
//        let isBlurred = detectBlur(image)
//        
//        // Рассчитываем общее качество
//        var quality: Float = 1.0
//        
//        // Штраф за низкую яркость
//        if brightness < 0.3 {
//            quality *= 0.7
//        } else if brightness < 0.5 {
//            quality *= 0.85
//        }
//        
//        // Штраф за низкий контраст
//        if contrast < 0.3 {
//            quality *= 0.7
//        } else if contrast < 0.5 {
//            quality *= 0.85
//        }
//        
//        // Штраф за размытие
////        if isBlurred {
////            quality *= 0.6
////        }
//        
//        return ImageMetadata(
//            quality: quality,
//            brightness: brightness,
//            contrast: contrast,
//            isBlurred: isBlurred
//        )
//    }
//    
//    private func calculateBrightness(_ image: UIImage) -> Float {
//        guard let cgImage = image.cgImage else { return 0 }
//        
//        let width = cgImage.width
//        let height = cgImage.height
//        let totalPixels = width * height
//        
//        var totalBrightness: Float = 0
//        
//        guard let data = cgImage.dataProvider?.data,
//              let bytes = CFDataGetBytePtr(data) else {
//            return 0
//        }
//        
//        let bytesPerPixel = 4
//        let bytesPerRow = cgImage.bytesPerRow
//        
//        for y in 0..<height {
//            for x in 0..<width {
//                let offset = y * bytesPerRow + x * bytesPerPixel
//                let r = Float(bytes[offset]) / 255.0
//                let g = Float(bytes[offset + 1]) / 255.0
//                let b = Float(bytes[offset + 2]) / 255.0
//                
//                // Формула для расчета яркости
//                let brightness = (0.299 * r + 0.587 * g + 0.114 * b)
//                totalBrightness += brightness
//            }
//        }
//        
//        return totalBrightness / Float(totalPixels)
//    }
//    
//    private func calculateContrast(_ image: UIImage) -> Float {
//        guard let cgImage = image.cgImage else { return 0 }
//        
//        let width = cgImage.width
//        let height = cgImage.height
//        
//        guard let data = cgImage.dataProvider?.data,
//              let bytes = CFDataGetBytePtr(data) else {
//            return 0
//        }
//        
//        let bytesPerPixel = 4
//        let bytesPerRow = cgImage.bytesPerRow
//        
//        var minBrightness: Float = 1.0
//        var maxBrightness: Float = 0.0
//        
//        for y in 0..<height {
//            for x in 0..<width {
//                let offset = y * bytesPerRow + x * bytesPerPixel
//                let r = Float(bytes[offset]) / 255.0
//                let g = Float(bytes[offset + 1]) / 255.0
//                let b = Float(bytes[offset + 2]) / 255.0
//                
//                let brightness = (0.299 * r + 0.587 * g + 0.114 * b)
//                minBrightness = min(minBrightness, brightness)
//                maxBrightness = max(maxBrightness, brightness)
//            }
//        }
//        
//        return maxBrightness - minBrightness
//    }
//    
//    private func detectBlur(_ image: UIImage) -> Bool {
//        guard let cgImage = image.cgImage else { return true }
//        
//        let width = cgImage.width
//        let height = cgImage.height
//        
//        guard let data = cgImage.dataProvider?.data,
//              let bytes = CFDataGetBytePtr(data) else {
//            return true
//        }
//        
//        let bytesPerPixel = 4
//        let bytesPerRow = cgImage.bytesPerRow
//        
//        var totalLaplacian: Float = 0
//        
//        for y in 1..<height-1 {
//            for x in 1..<width-1 {
//                let offset = y * bytesPerRow + x * bytesPerPixel
//                
//                // Получаем значения яркости соседних пикселей
//                let center = Float(bytes[offset]) / 255.0
//                let top = Float(bytes[offset - bytesPerRow]) / 255.0
//                let bottom = Float(bytes[offset + bytesPerRow]) / 255.0
//                let left = Float(bytes[offset - bytesPerPixel]) / 255.0
//                let right = Float(bytes[offset + bytesPerPixel]) / 255.0
//                
//                // Вычисляем лапласиан
//                let laplacian = abs(4 * center - top - bottom - left - right)
//                totalLaplacian += laplacian
//            }
//        }
//        
//        let averageLaplacian = totalLaplacian / Float((width - 2) * (height - 2))
//        return averageLaplacian < 0.1 // Порог для определения размытия
//    }
//    
//    // Преобразование UIImage в MLMultiArray для Facenet6
//    private func imageToMLMultiArray(_ image: UIImage) throws -> MLMultiArray {
//        // Изменяем размер изображения
//        guard let resizedImage = image.resize(to: targetSize) else {
//            print("[FaceEmbeddingService] Не удалось изменить размер изображения")
//            throw FaceEmbeddingError.processingError
//        }
//        guard let cgImage = resizedImage.cgImage else {
//            print("[FaceEmbeddingService] Не удалось получить cgImage")
//            throw FaceEmbeddingError.processingError
//        }
//        let width = Int(targetSize.width)
//        let height = Int(targetSize.height)
//        // Facenet6 ожидает [1, 160, 160, 3] или [1, 3, 160, 160]. Предположим [1, 160, 160, 3]
//        let shape: [NSNumber] = [1, NSNumber(value: height), NSNumber(value: width), 3]
//        let array = try MLMultiArray(shape: shape, dataType: .float32)
//        // Получаем пиксели
//        guard let context = CGContext(
//            data: nil,
//            width: width,
//            height: height,
//            bitsPerComponent: 8,
//            bytesPerRow: width * 4,
//            space: CGColorSpaceCreateDeviceRGB(),
//            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
//        ) else {
//            throw FaceEmbeddingError.processingError
//        }
//        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
//        guard let pixelBuffer = context.data else {
//            throw FaceEmbeddingError.processingError
//        }
//        let ptr = pixelBuffer.bindMemory(to: UInt8.self, capacity: width * height * 4)
//        // Заполняем MLMultiArray
//        for y in 0..<height {
//            for x in 0..<width {
//                let pixelIndex = (y * width + x) * 4
//                let r = Float(ptr[pixelIndex + 0]) / 255.0
//                let g = Float(ptr[pixelIndex + 1]) / 255.0
//                let b = Float(ptr[pixelIndex + 2]) / 255.0
//                // Нормализация (если требуется, например, [-1, 1])
//                let normR = (r - 0.5) * 2.0
//                let normG = (g - 0.5) * 2.0
//                let normB = (b - 0.5) * 2.0
//                // Индексы: [1, height, width, 3]
//                array[[0, y as NSNumber, x as NSNumber, 0]] = NSNumber(value: normR)
//                array[[0, y as NSNumber, x as NSNumber, 1]] = NSNumber(value: normG)
//                array[[0, y as NSNumber, x as NSNumber, 2]] = NSNumber(value: normB)
//            }
//        }
//        return array
//    }
//}
//
//// Расширение для UIImage
//extension UIImage {
//    func resize(to size: CGSize) -> UIImage? {
//        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
//        defer { UIGraphicsEndImageContext() }
//        
//        draw(in: CGRect(origin: .zero, size: size))
//        return UIGraphicsGetImageFromCurrentImageContext()
//    }
//    
//    func toPixelBuffer() -> CVPixelBuffer? {
//        let width = Int(size.width)
//        let height = Int(size.height)
//        
//        var pixelBuffer: CVPixelBuffer?
//        let status = CVPixelBufferCreate(
//            kCFAllocatorDefault,
//            width,
//            height,
//            kCVPixelFormatType_32ARGB,
//            nil,
//            &pixelBuffer
//        )
//        
//        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
//            return nil
//        }
//        
//        CVPixelBufferLockBaseAddress(buffer, [])
//        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
//        
//        let context = CGContext(
//            data: CVPixelBufferGetBaseAddress(buffer),
//            width: width,
//            height: height,
//            bitsPerComponent: 8,
//            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
//            space: CGColorSpaceCreateDeviceRGB(),
//            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
//        )
//        
//        context?.draw(cgImage!, in: CGRect(x: 0, y: 0, width: width, height: height))
//        
//        return buffer
//    }
//}
