//
//  PhotoLibraryService.swift
//  SharePhotoGroup
//
//  Created by Pavel Mac on 27/04/25
//

import Photos
import UIKit
import Combine
import Vision

class PhotoLibraryService: ObservableObject {
    
    @Published var isAuthorized = false
    @Published var scannedPhotosCount: Int = 0
    @Published var scanningProgress: Double = 0
    @Published var isScanning = false
    
    private var photoStorage: PhotoStorageService?
    private var faceEmbeddingService: FaceEmbeddingService?
    private var faceLabelingService: FaceLabelingService?
    var deviceHistoryService: DeviceHistoryService
    var cancellables = Set<AnyCancellable>()
    
    private let processingQueue = DispatchQueue(label: "com.photolibrary.processing", qos: .userInitiated)
    
    // Кэш для эмбеддингов устройств
    private var deviceEmbeddingCache: [String: [Float]] = [:]
    
    init() {
        let context = PersistenceController.shared.container.viewContext
        self.deviceHistoryService = DeviceHistoryService(context: context)
        checkAuthorization()
    }
    
    func configure(photoStorage: PhotoStorageService, faceEmbeddingService: FaceEmbeddingService, faceLabelingService: FaceLabelingService) {
        self.photoStorage = photoStorage
        self.faceEmbeddingService = faceEmbeddingService
        self.faceLabelingService = faceLabelingService
    }
    
    func checkAuthorization() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            isAuthorized = true
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] newStatus in
                DispatchQueue.main.async {
                    self?.isAuthorized = (newStatus == .authorized || newStatus == .limited)
                }
            }
        default:
            isAuthorized = false
        }
    }
    
    func startScanning() {
        guard isAuthorized else { return }
        
        // Проверяем доступность необходимых сервисов
        guard let photoStorage = photoStorage,
              let faceEmbeddingService = faceEmbeddingService,
              let faceLabelingService = faceLabelingService else {
            print("❌ Необходимые сервисы недоступны (photoStorage: \(photoStorage != nil), faceEmbeddingService: \(faceEmbeddingService != nil), faceLabelingService: \(faceLabelingService != nil))")
            return
        }
        
        // [DEBUG] Логируем устройства из истории перед сканированием
        print("=== [DEBUG] Перед сканированием устройств в истории: \(deviceHistoryService.deviceHistory.count)")
        for device in deviceHistoryService.deviceHistory {
            print("   [DEBUG] Устройство: \(device.deviceName ?? device.deviceId ?? "Unknown"), аватар: \(device.avatarData != nil ? "есть" : "нет")")
        }
        
        isScanning = true
        scanningProgress = 0
        scannedPhotosCount = 0
        
        // Получаем все фото из библиотеки
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        // Сканируем все фото пакетами
        let batchSize = 20
        let totalCount = assets.count
        var processedCount = 0
        
        print("📱 Начинаем сканирование \(totalCount) фото")
        
        Task {
            for i in stride(from: 0, to: totalCount, by: batchSize) {
                guard isScanning else { break }
                
                let endIndex = min(i + batchSize, totalCount)
                let batch = (i..<endIndex).map { assets[$0] }
                
                print("📦 Обработка пакета \(i/batchSize + 1) из \(Int(ceil(Double(totalCount)/Double(batchSize))))")
                
                // Обрабатываем пакет фото
                await processBatch(batch, totalCount: totalCount)
                
                processedCount += batch.count
                DispatchQueue.main.async {
                    self.scanningProgress = Double(processedCount) / Double(totalCount)
                    print("📊 Общий прогресс: \(Int(self.scanningProgress * 100))%")
                }
            }
            
            DispatchQueue.main.async {
                self.isScanning = false
                print("✅ Сканирование завершено")
//                print("=== [DEBUG] Сканирование завершено. Всего обработано фото: \(scannedPhotosCount)")
            }
        }
    }
    
    func stopScanning() {
        isScanning = false
    }
    
    private func processBatch(_ assets: [PHAsset], totalCount: Int) async {
        print("🔍 Начинаем обработку пакета из \(assets.count) фото")
        for (index, asset) in assets.enumerated() {
            guard isScanning else { break }
            print("📸 Обработка фото \(index + 1) из \(assets.count)")
            let image = await withCheckedContinuation { continuation in
                getImage(from: asset, targetSize: CGSize(width: 600, height: 600)) { image in
                    continuation.resume(returning: image)
                }
            }
            guard let image = image else {
                print("❌ Не удалось получить изображение для обработки")
                continue
            }
            // Используем только новую функцию!
            await processPhoto(image)
        }
        print("✅ Пакет из \(assets.count) фото обработан")
    }
    
    func getImage(from asset: PHAsset, targetSize: CGSize, completion: @escaping (UIImage?) -> Void) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            completion(image)
        }
    }
    
    func saveImage(_ image: UIImage) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }) { success, error in
            if let error = error {
                print("Error saving image: \(error.localizedDescription)")
            }
        }
    }
    
    func processPhoto(_ photo: UIImage) async {
        guard let faceEmbeddingService = faceEmbeddingService,
              let photoStorage = photoStorage,
              let faceLabelingService = faceLabelingService else {
            print("❌ Необходимые сервисы недоступны (faceEmbeddingService: \(faceEmbeddingService != nil), photoStorage: \(photoStorage != nil), faceLabelingService: \(faceLabelingService != nil))")
            return
        }
        
        // Проверка размера изображения
        guard photo.size.width * photo.size.height < 4096 * 4096 else {
            print("❌ [PhotoLibraryService] Изображение слишком большое")
            return
        }
        
        print("🔍 [PhotoLibraryService] Начинаем обработку фото")
        let deviceHistory = deviceHistoryService.deviceHistory
        print("📱 [PhotoLibraryService] Устройств в истории: \(deviceHistory.count)")
        
        guard let cgImage = photo.cgImage else {
            print("❌ [PhotoLibraryService] Не удалось получить CGImage из фото")
            return
        }
        
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        do {
            try handler.perform([request])
            if let results = request.results as? [VNFaceObservation] {
                print("✅ [PhotoLibraryService] Найдено лиц на фото: \(results.count)")
                var recognizedFaces: [RecognizedFace] = []
                
                // Используем autoreleasepool для каждого лица
                for (index, face) in results.enumerated() {
                    print("\n🔍 [PhotoLibraryService] Обработка лица \(index + 1) из \(results.count)")
                    let boundingBox = face.boundingBox
                    let x = boundingBox.origin.x * CGFloat(cgImage.width)
                    let y = (1 - boundingBox.origin.y - boundingBox.height) * CGFloat(cgImage.height)
                    let width = boundingBox.width * CGFloat(cgImage.width)
                    let height = boundingBox.height * CGFloat(cgImage.height)
                    
                    // Проверка валидности размеров
                    guard width > 0, height > 0, width < CGFloat(cgImage.width), height < CGFloat(cgImage.height) else {
                        print("❌ [PhotoLibraryService] Некорректные размеры лица")
                        continue
                    }
                    
                    print("   [DEBUG] boundingBox: x=\(x), y=\(y), width=\(width), height=\(height)")
                    
                    // Используем autoreleasepool для операций с изображением
                    let faceImage: UIImage? = autoreleasepool {
                        guard let croppedCGImage = cgImage.cropping(to: CGRect(x: x, y: y, width: width, height: height)) else {
                            print("❌ [PhotoLibraryService] Не удалось получить изображение лица (cropping failed)")
                            return nil
                        }
                        return UIImage(cgImage: croppedCGImage)
                    }
                    
                    guard let faceImage = faceImage else { continue }
                    
                    do {
                        let faceEmbedding = try await faceEmbeddingService.getEmbedding(for: faceImage)
                        
                        // Проверка валидности эмбеддинга
                        guard !faceEmbedding.isEmpty else {
                            print("❌ [PhotoLibraryService] Получен пустой эмбеддинг")
                            continue
                        }
                        
                        print("🧬 [PhotoLibraryService] Embedding для лица получен (длина: \(faceEmbedding.count))")
                        var bestMatch: (name: String?, confidence: Float, source: LabelSource)? = nil
                        
                        // Сравнение с устройствами
                        for device in deviceHistory {
                            guard let deviceId = device.deviceId else {
                                print("[ERROR] deviceId is nil for device: \(device.deviceName ?? "Unknown")")
                                continue
                            }
                            
                            guard let avatarData = device.avatarData else {
                                print("[ERROR] avatarData is nil for deviceId: \(deviceId)")
                                continue
                            }
                            
                            guard let avatar = UIImage(data: avatarData) else {
                                print("[ERROR] Не удалось создать UIImage из avatarData для deviceId: \(deviceId)")
                                continue
                            }
                            
                            let deviceEmbedding: [Float]
                            if let cached = deviceEmbeddingCache[deviceId] {
                                deviceEmbedding = cached
                            } else {
                                do {
                                    deviceEmbedding = try await faceEmbeddingService.getEmbedding(for: avatar)
                                    deviceEmbeddingCache[deviceId] = deviceEmbedding
                                } catch {
                                    print("[PhotoLibraryService] Ошибка получения эмбеддинга для устройства: \(error) (deviceId: \(deviceId))")
                                    continue
                                }
                            }
                            
                            let similarity = faceEmbeddingService.calculateSimilarity(faceEmbedding, deviceEmbedding)
                            print("   🔸 Сравнение с устройством [\(device.deviceName ?? device.deviceId ?? "Unknown")]: similarity = \(similarity)")
                            
                            if similarity >= 0.6 && (bestMatch == nil || similarity > bestMatch!.confidence) {
                                bestMatch = (device.deviceName ?? device.deviceId, similarity, LabelSource.peer)
                            }
                        }
                        
                        // Сравнение с контактами и профилем пользователя
                        let knownFaces = faceLabelingService.getKnownFaces().filter { $0.labelSource == .contact || $0.labelSource == .userProfile }
                        for contact in knownFaces {
                            let similarity = faceEmbeddingService.calculateSimilarity(faceEmbedding, contact.faceVector)
                            let sourceType = contact.labelSource == .userProfile ? "профиль" : "контакт"
                            print("   🔸 Сравнение с \(sourceType) [\(contact.name ?? "Unknown")]: similarity = \(similarity)")
                            
                            if similarity >= 0.6 && (bestMatch == nil || similarity > bestMatch!.confidence) {
                                bestMatch = (contact.name, similarity, contact.labelSource)
                            }
                        }
                        
                        if let match = bestMatch {
                            recognizedFaces.append(RecognizedFace(name: match.name, confidence: match.confidence, source: match.source))
                            print("   ✅ Лучшее совпадение: [\(match.name ?? "Unknown")] (similarity: \(match.confidence), source: \(match.source))")
                        } else {
                            print("   ❌ Совпадений выше порога не найдено")
                        }
                        
                    } catch {
                        print("[PhotoLibraryService] Ошибка получения embedding для лица: \(error) (index: \(index))")
                    }
                }
                
                print("[PhotoLibraryService] Сохраняем фото с \(recognizedFaces.count) распознанными лицами...")
                await photoStorage.savePhoto(photo, senderName: nil, senderAvatar: nil, recognizedFaces: recognizedFaces)
                print("[PhotoLibraryService] Фото сохранено!")
            } else {
                print("❌ [PhotoLibraryService] Лица не найдены (results == nil)")
                await photoStorage.savePhoto(photo, senderName: nil, senderAvatar: nil, recognizedFaces: [])
            }
        } catch {
            print("❌ [PhotoLibraryService] Ошибка обработки фото: \(error)")
            await photoStorage.savePhoto(photo, senderName: nil, senderAvatar: nil, recognizedFaces: [])
        }
    }
}

//import Photos
//import UIKit
//import Combine
//import Vision
//
//class PhotoLibraryService: ObservableObject {
//    @Published var isAuthorized = false
//    @Published var scannedPhotosCount: Int = 0
//    @Published var scanningProgress: Double = 0
//    @Published var isScanning = false
//    
//    private var photoStorage: PhotoStorageService?
//    private var faceEmbeddingService: FaceEmbeddingService?
//    private var faceLabelingService: FaceLabelingService?
//    var deviceHistoryService: DeviceHistoryService
//    var cancellables = Set<AnyCancellable>()
//    
//    private let processingQueue = DispatchQueue(label: "com.photolibrary.processing", qos: .userInitiated)
//    
//    init() {
//        let context = PersistenceController.shared.container.viewContext
//        self.deviceHistoryService = DeviceHistoryService(context: context)
//        checkAuthorization()
//    }
//    
//    func configure(photoStorage: PhotoStorageService, faceEmbeddingService: FaceEmbeddingService, faceLabelingService: FaceLabelingService) {
//        self.photoStorage = photoStorage
//        self.faceEmbeddingService = faceEmbeddingService
//        self.faceLabelingService = faceLabelingService
//    }
//    
//    func checkAuthorization() {
//        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
//        switch status {
//        case .authorized, .limited:
//            isAuthorized = true
//        case .notDetermined:
//            PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] newStatus in
//                DispatchQueue.main.async {
//                    self?.isAuthorized = (newStatus == .authorized || newStatus == .limited)
//                }
//            }
//        default:
//            isAuthorized = false
//        }
//    }
//    
//    func startScanning() {
//        guard isAuthorized else { return }
//        
//        // [DEBUG] Логируем устройства из истории перед сканированием
//        print("=== [DEBUG] Перед сканированием устройств в истории: \(deviceHistoryService.deviceHistory.count)")
//        for device in deviceHistoryService.deviceHistory {
//            print("   [DEBUG] Устройство: \(device.deviceName ?? device.deviceId ?? "Unknown"), аватар: \(device.avatarData != nil ? "есть" : "нет")")
//        }
//        
//        isScanning = true
//        scanningProgress = 0
//        scannedPhotosCount = 0
//        
//        // Получаем все фото из библиотеки
//        let fetchOptions = PHFetchOptions()
//        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
//        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
//        
//        // Сканируем все фото пакетами
//        let batchSize = 20
//        let totalCount = assets.count
//        var processedCount = 0
//        
//        print("📱 Начинаем сканирование \(totalCount) фото")
//        
//        Task {
//            for i in stride(from: 0, to: totalCount, by: batchSize) {
//                guard isScanning else { break }
//                
//                let endIndex = min(i + batchSize, totalCount)
//                let batch = (i..<endIndex).map { assets[$0] }
//                
//                print("📦 Обработка пакета \(i/batchSize + 1) из \(Int(ceil(Double(totalCount)/Double(batchSize))))")
//                
//                // Обрабатываем пакет фото
//                await processBatch(batch, totalCount: totalCount)
//                
//                processedCount += batch.count
//                DispatchQueue.main.async {
//                    self.scanningProgress = Double(processedCount) / Double(totalCount)
//                    print("📊 Общий прогресс: \(Int(self.scanningProgress * 100))%")
//                }
//            }
//            
//            DispatchQueue.main.async {
//                self.isScanning = false
//                print("✅ Сканирование завершено")
//                //                print("=== [DEBUG] Сканирование завершено. Всего обработано фото: \(scannedPhotosCount)")
//            }
//        }
//    }
//    
//    func stopScanning() {
//        isScanning = false
//    }
//    
//    private func processBatch(_ assets: [PHAsset], totalCount: Int) async {
//        print("🔍 Начинаем обработку пакета из \(assets.count) фото")
//        for (index, asset) in assets.enumerated() {
//            guard isScanning else { break }
//            print("📸 Обработка фото \(index + 1) из \(assets.count)")
//            let image = await withCheckedContinuation { continuation in
//                getImage(from: asset, targetSize: CGSize(width: 600, height: 600)) { image in
//                    continuation.resume(returning: image)
//                }
//            }
//            guard let image = image else {
//                print("❌ Не удалось получить изображение для обработки")
//                continue
//            }
//            // Используем только новую функцию!
//            await processPhoto(image)
//        }
//        print("✅ Пакет из \(assets.count) фото обработан")
//    }
//    
//    func getImage(from asset: PHAsset, targetSize: CGSize, completion: @escaping (UIImage?) -> Void) {
//        let options = PHImageRequestOptions()
//        options.deliveryMode = .highQualityFormat
//        options.isNetworkAccessAllowed = true
//        
//        PHImageManager.default().requestImage(
//            for: asset,
//            targetSize: targetSize,
//            contentMode: .aspectFill,
//            options: options
//        ) { image, _ in
//            completion(image)
//        }
//    }
//    
//    func saveImage(_ image: UIImage) {
//        PHPhotoLibrary.shared().performChanges({
//            PHAssetChangeRequest.creationRequestForAsset(from: image)
//        }) { success, error in
//            if let error = error {
//                print("Error saving image: \(error.localizedDescription)")
//            }
//        }
//    }
////    if let contactMatch = await faceLabelingService.getContactDisplayInfo(for: embedding) {
////        //                        print("✅ [PhotoLibraryService] Найдено совпадение в контактах: \(contactMatch.name)")
////        recognizedFaces.append(RecognizedFace(
////            name: contactMatch.name,
////            confidence: 0.8,
////            source: .contact
////        ))
////    } else {
////        //                        print("❌ [PhotoLibraryService] Совпадений не найдено среди устройств, известных лиц и контактов")
////    }
////}
////    func processPhoto(_ photo: UIImage) async {
////        guard let faceEmbeddingService = faceEmbeddingService,
////              let photoStorage = photoStorage,
////              let faceLabelingService = faceLabelingService else {
////            print("❌ Необходимые сервисы недоступны")
////            return
////        }
////        
////        print("🔍 [PhotoLibraryService] Начинаем обработку фото")
////        
////        // Получаем историю устройств
////        let deviceHistory = deviceHistoryService.deviceHistory
////        print("📱 [PhotoLibraryService] Устройств в истории: \(deviceHistory.count)")
////        // [DEBUG] Логируем устройства из истории для текущего фото
////        print("=== [DEBUG] Сравниваем с устройствами из истории (\(deviceHistory.count)):")
////        for device in deviceHistory {
////            print("   [DEBUG] \(device.deviceName ?? device.deviceId ?? "Unknown"), аватар: \(device.avatarData != nil ? "есть" : "нет")")
////        }
////        
////        // Создаем запрос для обнаружения лиц
////        guard let cgImage = photo.cgImage else {
////            print("❌ [PhotoLibraryService] Не удалось получить CGImage из фото")
////            return
////        }
////        let request = VNDetectFaceRectanglesRequest()
////        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
////        
////        do {
////            try handler.perform([request])
////            
////            if let results = request.results as? [VNFaceObservation] {
////                print("✅ [PhotoLibraryService] Найдено лиц на фото: \(results.count)")
////                
////                var recognizedFaces: [RecognizedFace] = []
////                
////                for (index, face) in results.enumerated() {
////                    print("\n🔍 [PhotoLibraryService] Обработка лица \(index + 1) из \(results.count)")
////                    
////                    // Получаем изображение лица
////                    let boundingBox = face.boundingBox
////                    let x = boundingBox.origin.x * CGFloat(cgImage.width)
////                    let y = (1 - boundingBox.origin.y - boundingBox.height) * CGFloat(cgImage.height)
////                    let width = boundingBox.width * CGFloat(cgImage.width)
////                    let height = boundingBox.height * CGFloat(cgImage.height)
////                    
////                    guard let croppedCGImage = cgImage.cropping(to: CGRect(x: x, y: y, width: width, height: height)) else {
////                        print("❌ [PhotoLibraryService] Не удалось получить изображение лица")
////                        continue
////                    }
////                    let faceImage = UIImage(cgImage: croppedCGImage)
////                    
////                    // Получаем embedding для лица
////                    let embedding = try await faceEmbeddingService.getEmbedding(for: faceImage)
////                    print("🧬 [PhotoLibraryService] Embedding для лица получен")
////                    
////                    // 1. Сравнение с устройствами из DeviceListView (peer)
////                    var bestMatch: (name: String, confidence: Float)? = nil
////                    for device in deviceHistory {
////                        if let avatarData = device.avatarData, let avatar = UIImage(data: avatarData) {
////                            do {
////                                let deviceEmbedding = try await faceEmbeddingService.getEmbedding(for: avatar)
////                                let similarity = faceEmbeddingService.calculateSimilarity(deviceEmbedding, embedding)
////                                let name = device.deviceName ?? device.deviceId ?? "Unknown"
////                                print("   🔸 Сравнение с устройством [\(name)]: similarity = \(similarity)")
////                                if similarity > 0.5 && (bestMatch == nil || similarity > bestMatch!.confidence) {
////                                    bestMatch = (name, similarity)
////                                    print("   ✅ Лучшее совпадение на данный момент: [\(name)] (similarity: \(similarity))")
////                                }
////                            } catch {
////                                let name = device.deviceName ?? device.deviceId ?? "Unknown"
////                                print("   ❌ Ошибка embedding для устройства [\(name)]: \(error)")
////                            }
////                        }
////                    }
////                    if let match = bestMatch {
////                        //                        print("✅ [PhotoLibraryService] Финальное совпадение с устройством: [\(match.name)] (similarity: \(match.confidence))")
////                        recognizedFaces.append(RecognizedFace(
////                            name: match.name,
////                            confidence: match.confidence,
////                            source: .peer
////                        ))
////                        continue
////                    }
////                    
//// 
////                    // 3. Сравнение с контактами
////                    //                    print("🔍 [PhotoLibraryService] Сравнение с контактами...")
////                    if let contactMatch = await faceLabelingService.getContactDisplayInfo(for: embedding) {
////                        //                        print("✅ [PhotoLibraryService] Найдено совпадение в контактах: \(contactMatch.name)")
////                        recognizedFaces.append(RecognizedFace(
////                            name: contactMatch.name,
////                            confidence: 0.8,
////                            source: .contact
////                        ))
////                    } else {
////                        //                        print("❌ [PhotoLibraryService] Совпадений не найдено среди устройств, известных лиц и контактов")
////                    }
////                }
////                // Итоговый лог по распознанным лицам
////                let names = recognizedFaces.map { $0.name ?? "Unknown" }
////                print("\n📝 [PhotoLibraryService] Итог: распознано лиц: \(recognizedFaces.count), имена: \(names)")
////                // Сохраняем фото с распознанными лицами
////                await photoStorage.savePhoto(photo, senderName: nil, senderAvatar: nil, recognizedFaces: recognizedFaces)
////                print("✅ [PhotoLibraryService] Фото сохранено с \(recognizedFaces.count) распознанными лицами")
////            } else {
////                print("❌ [PhotoLibraryService] Лица не найдены")
////                // Сохраняем фото даже если лица не найдены
////                await photoStorage.savePhoto(photo, senderName: nil, senderAvatar: nil, recognizedFaces: [])
////            }
////        } catch {
////            print("❌ [PhotoLibraryService] Ошибка при обработке фото: \(error)")
////            // Сохраняем фото даже при ошибке
////            await photoStorage.savePhoto(photo, senderName: nil, senderAvatar: nil, recognizedFaces: [])
////        }
////    }
//} 
