//
//  ReceivedPhotosView.swift
//  SharePhotoGroup
//
//  Created by Pavel Mac on 24/04/25
//

import SwiftUI
import PhotosUI
import CoreData
import Vision


struct PhotoPackage: Identifiable {
    let id = UUID()
    let date: Date
    let photos: [ReceivedPhotoModel]
    var isExpanded: Bool = false
}

struct DetectedFace: Identifiable, Hashable {
    let id = UUID()
    let originalImage: UIImage
    let faceImage: UIImage
    let embedding: [Float]
}

struct ReceivedPhotosView: View {
    @EnvironmentObject var photoStorage: PhotoStorageService
    @EnvironmentObject var faceLabelingService: FaceLabelingService
    @State private var selectedPhoto: ReceivedPhotoModel?
    @State private var showingPhotoDetail = false
    
    @EnvironmentObject var faceStore: FaceStore
    @StateObject private var photoLibraryService = PhotoLibraryService()
    @StateObject private var faceEmbeddingService = FaceEmbeddingService()
    @State private var isScanning = false
    @State private var foundFaces: [DetectedFace] = []
    @State private var logs: [String] = []
    
    private func sectionTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return "Earlier"
        }
    }
    
    private var groupedPhotos: [(title: String, items: [ReceivedPhotoModel])] {
        let grouped = Dictionary(grouping: photoStorage.photos) { photo in
            let datePart = photo.dateReceived.map(sectionTitle(for:)) ?? "Earlier"
            let sender = photo.senderName ?? "Unknown"
            return "\(datePart) — \(sender)"
        }
        let order = ["Today", "Yesterday", "Earlier"]
        let sortedKeys = grouped.keys.sorted { key1, key2 in
            let date1 = order.firstIndex(where: { key1.hasPrefix($0) }) ?? order.count
            let date2 = order.firstIndex(where: { key2.hasPrefix($0) }) ?? order.count
            if date1 != date2 { return date1 < date2 }
            return key1 < key2
        }
        return sortedKeys.compactMap { key in
            guard let items = grouped[key], !items.isEmpty else { return nil }
            return (title: key, items: items)
        }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                HStack{
                    Text("Settings")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(AppColors.textPrimary)
                        .padding(.top, 16)
                        .padding(.leading, 20)
                    Spacer()
                }
                Divider().background(Color.gray)
                 if photoStorage.photos.isEmpty {
                    VStack(spacing: AppSpacing.grid3x) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 64))
                            .foregroundColor(AppColors.textSecondary)
                        Text("No Photos Yet")
                            .font(AppTypography.display(for: .title))
                            .foregroundColor(AppColors.textPrimary)
                        Text("Photos you receive will appear here. Start sharing moments with friends!")
                            .font(AppTypography.bodyText)
                            .foregroundColor(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppSpacing.grid4x)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: AppSpacing.sectionGap) {
                            ForEach(groupedPhotos, id: \.title) { section in
                                SectionView(section: section, onPhotoTap: { photo in
                                    selectedPhoto = photo
                                    showingPhotoDetail = true
                                })
                            }
                        }
                        .padding(.top, AppSpacing.grid3x)
                    }
                }
            }
             
//            .sheet(isPresented: $showingPhotoDetail) {
//                if let photo = selectedPhoto {
//                    PhotoDetailView(photo: photo)
//                }
//            }
        }
        .onAppear {
            photoLibraryService.configure(
                photoStorage: photoStorage,
                faceEmbeddingService: faceEmbeddingService,
                faceLabelingService: faceLabelingService
            )
            // Загружаем фотографии после конфигурации сервисов
            DispatchQueue.main.async {
                photoStorage.loadPhotos()
            }
        }
        .disabled(!photoLibraryService.isAuthorized)
        .onChange(of: photoStorage.photos) { _,_ in }
//        .onChange(of: photoLibraryService.isAuthorized) { newValue in
//            if newValue {
//                photoLibraryService.startScanning()
//            }
//        }
        .onDisappear{
            stopScanning()
        }
    }
//    private func startScanning() {
//        isScanning = true
//        foundFaces.removeAll()
//        logs.removeAll()
//        logs.append("НОВАЯ: Начат скан последних 100 фото")
//        let limitedAssets = Array(photoLibraryService.scannedPhotos.prefix(100))
//        if limitedAssets.isEmpty {
//            logs.append("НОВАЯ: Нет фото для сканирования")
//            isScanning = false
//            return
//        }
//        for (index, asset) in limitedAssets.enumerated() {
//            logs.append("НОВАЯ: Обработка фото \(index + 1) из \(limitedAssets.count)")
//            print("НОВАЯ: Найденные лица (\(foundFaces.count)):")
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
    
    private func detectFaceAndEmbed(in image: UIImage, index: Int) {
        guard let cgImage = image.cgImage else {
            logs.append("НОВАЯ: Не удалось получить CGImage для фото \(index)")
            return
        }
        let request = VNDetectFaceRectanglesRequest { request, error in
            if let error = error {
                logs.append("НОВАЯ: Ошибка Vision: \(error.localizedDescription)")
                return
            }
            guard let results = request.results as? [VNFaceObservation], let firstFace = results.first else {
                logs.append("НОВАЯ: Лицо не найдено на фото \(index)")
                return
            }
            let boundingBox = firstFace.boundingBox
            let width = CGFloat(cgImage.width)
            let height = CGFloat(cgImage.height)
            let padding: CGFloat = 0.2
            let rect = CGRect(
                x: (boundingBox.origin.x - padding) * width,
                y: (1 - boundingBox.origin.y - boundingBox.height - padding) * height,
                width: (boundingBox.width + padding * 2) * width,
                height: (boundingBox.height + padding * 2) * height
            ).integral
            let safeRect = CGRect(
                x: max(0, rect.origin.x),
                y: max(0, rect.origin.y),
                width: min(width - rect.origin.x, rect.width),
                height: min(height - rect.origin.y, rect.height)
            )
            guard let faceCgImage = cgImage.cropping(to: safeRect) else {
                logs.append("НОВАЯ: Не удалось кропнуть лицо на фото \(index)")
                return
            }
            let faceImage = UIImage(cgImage: faceCgImage)
            do {
                let embedding = try faceEmbeddingService.getEmbedding(for: faceImage)
                let detected = DetectedFace(originalImage: image, faceImage: faceImage, embedding: embedding)
                foundFaces.append(detected)
                logs.append("НОВАЯ: Лицо найдено и embedding создан для фото \(index)")
                let faceData = FaceData(image: faceImage, fullImage: image, embedding: embedding)
                DispatchQueue.main.async {
                    faceStore.add([faceData])
                    logs.append("НОВАЯ: В FaceStore теперь \(faceStore.faces.count) лиц")
                }
            } catch {
                logs.append("НОВАЯ: Не удалось создать embedding для фото \(index): \(error.localizedDescription)")
            }
        }
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            logs.append("НОВАЯ: Ошибка Vision perform: \(error.localizedDescription)")
        }
    }
    private func stopScanning() {
        isScanning = false
        logs.append("НОВАЯ: Сканирование остановлено")
    }
    
}

struct SectionView: View {
    let section: (title: String, items: [ReceivedPhotoModel])
    let onPhotoTap: (ReceivedPhotoModel) -> Void

    var body: some View {
        let first = section.items.first!
        FeedPostCard(photo: first, photosInGroup: section.items, onPhotoTap: onPhotoTap)
            .padding(.vertical, 8)
    }
}

struct FeedPostCard: View {
    let photo: ReceivedPhotoModel
    let photosInGroup: [ReceivedPhotoModel]
    let onPhotoTap: (ReceivedPhotoModel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Верхняя строка: аватар, имя, время, лайк
            HStack(alignment: .center) {
                if let avatar = photo.senderAvatar {
                    Image(uiImage: avatar)
                        .resizable()
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(AppColors.textSecondary.opacity(0.2))
                        .frame(width: 40, height: 40)
                        .overlay(Image(systemName: "person.fill").foregroundColor(AppColors.textSecondary))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(photo.senderName ?? "Unknown")
                        .font(.headline)
                    Text(timeAgoString(from: photo.dateReceived))
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Spacer()
                Image(systemName: "heart.fill")
                    .foregroundColor(.red)
            }
            // Текст поста (заглушка)
            Text("Wedding photos from yesterday! 💕")
                .font(.body)
            // Сетка фото 2x3
            FeedPhotoGrid(photos: photosInGroup, onPhotoTap: onPhotoTap)
            // Действия: комментарии и Save all
            HStack {
                Button(action: {}) {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left")
                        Text("12 comments")
                    }
                }
                .foregroundColor(.blue)
                Spacer()
                Button(action: {}) {
                    Text("Save all")
                }
                .foregroundColor(.blue)
            }
            .font(.subheadline)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        .padding(.horizontal)
    }

    private func timeAgoString(from date: Date?) -> String {
        guard let date = date else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct FeedPhotoGrid: View {
    let photos: [ReceivedPhotoModel]
    let onPhotoTap: (ReceivedPhotoModel) -> Void

    var body: some View {
        let maxPhotos = 6
        let gridItems = Array(photos.prefix(maxPhotos))
        let missing = maxPhotos - gridItems.count
        let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(0..<maxPhotos, id: \ .self) { i in
                if i < gridItems.count, let image = gridItems[i].image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 80)
                        .clipped()
                        .cornerRadius(10)
                        .onTapGesture { onPhotoTap(gridItems[i]) }
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.systemGray5))
                        VStack {
                            Text("Photo \(i+1)")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Image(systemName: "questionmark.square")
                                .font(.system(size: 24))
                                .foregroundColor(.gray)
                        }
                    }
                    .frame(height: 80)
                }
            }
        }
    }
}

//struct PhotoDetailView: View {
//    let photo: ReceivedPhotoModel
//    @Environment(\.dismiss) private var dismiss
//    
//    var body: some View {
//        NavigationView {
//            ScrollView {
//                VStack {
//                    if let image = photo.image {
//                        Image(uiImage: image)
//                            .resizable()
//                            .scaledToFit()
//                            .frame(maxWidth: .infinity)
//                    }
//                    if let date = photo.dateReceived {
//                        Text(date, style: .date)
//                            .font(AppTypography.subtext)
//                            .foregroundColor(AppColors.textSecondary)
//                            .padding(.top)
//                    }
//                    ForEach(photo.recognizedFaces) { face in
//                        VStack(alignment: .leading) {
//                            Text("\(face.name ?? "Unknown")")
//                                .font(AppTypography.bodyText)
//                                .foregroundColor(AppColors.textPrimary)
//                            Text("Уверенность: \(Int(face.confidence * 100))%")
//                                .font(AppTypography.subtext)
//                                .foregroundColor(AppColors.textSecondary)
//                        }
//                        .padding(.vertical, 4)
//                    }
//                }
//                .padding()
//            }
//            .navigationTitle("Детали фото")
//            .navigationBarTitleDisplayMode(.inline)
//            .toolbar {
//                ToolbarItem(placement: .navigationBarTrailing) {
//                    Button("Готово") {
//                        dismiss()
//                    }
//                }
//            }
//        }
//    }
//}

#Preview {
    ReceivedPhotosView()
    .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
    .environmentObject(FaceStore())
}
