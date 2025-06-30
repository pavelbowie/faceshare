//
//  PhotoScanView.swift
//  SharePhotoGroup
//
//  Created by Pavel Mac on 21/04/25
//

import SwiftUI
import Photos
import Vision

//struct DetectedFace: Identifiable, Hashable {
//    let id = UUID()
//    let originalImage: UIImage
//    let faceImage: UIImage
//    let embedding: [Float]
//}

struct PhotoScanView: View {
    @EnvironmentObject var faceStore: FaceStore
    @StateObject private var photoLibraryService = PhotoLibraryService()
    @StateObject private var faceEmbeddingService = FaceEmbeddingService()
    @State private var isScanning = false
    @State private var foundFaces: [DetectedFace] = []
    @State private var logs: [String] = []
    
    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: AppSpacing.sectionGap) {
                    // Top spacing for visual balance
                    Spacer().frame(height: AppSpacing.grid3x)
                    
                    if isScanning {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: AppColors.primary))
                        Text("Scanning last 4 photos...")
                            .font(AppTypography.bodyText)
                            .foregroundColor(AppColors.textSecondary)
                    }
                    
                    Button(action: {
                        if isScanning {
                            stopScanning()
                        } else {
//                            startScanning()
                        }
                    }) {
                        Text(isScanning ? "Stop" : "Start scanning")
                            .font(AppTypography.button)
                            .foregroundColor(AppColors.cardBackground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppSpacing.grid2x)
                            .background(isScanning ? AppColors.error : AppColors.primary)
                            .cornerRadius(AppSpacing.buttonCornerRadius)
                    }
                    .padding(.horizontal, AppSpacing.horizontalPadding)
                    .disabled(!photoLibraryService.isAuthorized)
                    
                    if !foundFaces.isEmpty {
                        VStack(alignment: .leading, spacing: AppSpacing.grid2x) {
                            Text("Found faces (\(foundFaces.count)):")
                                .font(AppTypography.sectionTitle)
                                .foregroundColor(AppColors.textPrimary)
                                .padding(.horizontal, AppSpacing.horizontalPadding)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: AppSpacing.grid3x) {
                                    ForEach(foundFaces) { face in
                                        VStack(spacing: AppSpacing.gridUnit) {
                                            Image(uiImage: face.faceImage)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 100, height: 100)
                                                .clipShape(Circle())
                                                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                                            Text("Embedding: \(face.embedding.prefix(3).map { String(format: "%.2f", $0) }.joined(separator: ", "))...")
                                                .font(AppTypography.subtext)
                                                .foregroundColor(AppColors.textSecondary)
                                                .lineLimit(1)
                                            Button(action: {
                                                // Показывать оригинал
                                            }) {
                                                Image(uiImage: face.originalImage)
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 60, height: 60)
                                                    .clipShape(RoundedRectangle(cornerRadius: AppSpacing.buttonCornerRadius))
                                                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                                            }
                                        }
                                        .padding(AppSpacing.gridUnit)
                                        .background(AppColors.cardBackground)
                                        .cornerRadius(AppSpacing.cardCornerRadius)
                                        .shadow(AppShadows.small)
                                    }
                                }
                                .padding(.horizontal, AppSpacing.horizontalPadding)
                            }
                        }
                    } else {
                        Text("No faces found")
                            .font(AppTypography.bodyText)
                            .foregroundColor(AppColors.textSecondary)
                            .padding(.top, AppSpacing.grid2x)
                    }
                    
                    // Logs section
                    if !logs.isEmpty {
                        VStack(alignment: .leading, spacing: AppSpacing.gridUnit) {
                            Text("Activity Log")
                                .font(AppTypography.sectionTitle)
                                .foregroundColor(AppColors.textPrimary)
                                .padding(.horizontal, AppSpacing.horizontalPadding)
                            ScrollView {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(logs, id: \.self) { log in
                                        Text(log)
                                            .font(AppTypography.subtext)
                                            .foregroundColor(AppColors.textSecondary)
                                            .padding(.horizontal, AppSpacing.horizontalPadding)
                                    }
                                }
                            }
                            .frame(maxHeight: 150)
                            .background(AppColors.cardBackground)
                            .cornerRadius(AppSpacing.cardCornerRadius)
                            .padding(.horizontal, AppSpacing.horizontalPadding)
                        }
                    }
                    Spacer(minLength: AppSpacing.grid4x)
                }
            }
        }
        .navigationTitle("Scanning Photo")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            print("НОВАЯ: PhotoScanView: faceStore = \(Unmanaged.passUnretained(faceStore).toOpaque())")
        }
        .onChange(of: photoLibraryService.isAuthorized) { newValue in
            if newValue && isScanning {
                photoLibraryService.startScanning()
            }
        }
    }
    
//    private func startScanning() {
//        isScanning = true
//        foundFaces.removeAll()
//        logs.removeAll()
//        logs.append("НОВАЯ: Начат скан последних 4 фото")
//        let limitedAssets = Array(photoLibraryService.scannedPhotos.prefix(4))
//        if limitedAssets.isEmpty {
//            logs.append("НОВАЯ: Нет фото для сканирования")
//            isScanning = false
//            return
//        }
//        for (index, asset) in limitedAssets.enumerated() {
//            logs.append("НОВАЯ: Обработка фото \(index + 1) из \(limitedAssets.count)")
//            photoLibraryService.getImage(from: asset, targetSize: CGSize(width: 800, height: 800)) { image in
//                guard let image = image else {
//                    logs.append("НОВАЯ: Не удалось загрузить фото \(index + 1)")
//                    return
//                }
//                detectFaceAndEmbed(in: image, index: index + 1)
//            }
//        }
//        isScanning = false
//    }
//    
//    private func detectFaceAndEmbed(in image: UIImage, index: Int) {
//        guard let cgImage = image.cgImage else {
//            logs.append("НОВАЯ: Не удалось получить CGImage для фото \(index)")
//            return
//        }
//        let request = VNDetectFaceRectanglesRequest { request, error in
//            if let error = error {
//                logs.append("НОВАЯ: Ошибка Vision: \(error.localizedDescription)")
//                return
//            }
//            guard let results = request.results as? [VNFaceObservation], let firstFace = results.first else {
//                logs.append("НОВАЯ: Лицо не найдено на фото \(index)")
//                return
//            }
//            // Кроп лица
//            let boundingBox = firstFace.boundingBox
//            let width = CGFloat(cgImage.width)
//            let height = CGFloat(cgImage.height)
//            
//            // Добавляем отступы для лучшего кропа
//            let padding: CGFloat = 0.2
//            let rect = CGRect(
//                x: (boundingBox.origin.x - padding) * width,
//                y: (1 - boundingBox.origin.y - boundingBox.height - padding) * height,
//                width: (boundingBox.width + padding * 2) * width,
//                height: (boundingBox.height + padding * 2) * height
//            ).integral
//            
//            // Проверяем, что кроп не выходит за границы изображения
//            let safeRect = CGRect(
//                x: max(0, rect.origin.x),
//                y: max(0, rect.origin.y),
//                width: min(width - rect.origin.x, rect.width),
//                height: min(height - rect.origin.y, rect.height)
//            )
//            
//            guard let faceCgImage = cgImage.cropping(to: safeRect) else {
//                logs.append("НОВАЯ: Не удалось кропнуть лицо на фото \(index)")
//                return
//            }
//            let faceImage = UIImage(cgImage: faceCgImage)
//            
//            // Эмбеддинг
//            do {
//                let embedding = try faceEmbeddingService.getEmbedding(for: faceImage)
//                let detected = DetectedFace(originalImage: image, faceImage: faceImage, embedding: embedding)
//                foundFaces.append(detected)
//                logs.append("НОВАЯ: Лицо найдено и embedding создан для фото \(index)")
//                // Добавляем в общий FaceStore для сравнения в MultipeerService
//                let faceData = FaceData(image: faceImage, fullImage: image, embedding: embedding)
//                DispatchQueue.main.async {
//                    faceStore.add([faceData])
//                    logs.append("НОВАЯ: В FaceStore теперь \(faceStore.faces.count) лиц")
//                }
//            } catch {
//                logs.append("НОВАЯ: Не удалось создать embedding для фото \(index): \(error.localizedDescription)")
//            }
//        }
//        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
//        do {
//            try handler.perform([request])
//        } catch {
//            logs.append("НОВАЯ: Ошибка Vision perform: \(error.localizedDescription)")
//        }
//    }
    
    private func stopScanning() {
        isScanning = false
        logs.append("НОВАЯ: Сканирование остановлено")
    }
}

struct PhotoScanView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            PhotoScanView().environmentObject(FaceStore())
        }
    }
} 
