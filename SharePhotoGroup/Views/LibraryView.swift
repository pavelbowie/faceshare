//
//  LibraryView.swift
//  SharePhotoGroup
//
//  Created by Pavel Mac on 22/04/25
//

import SwiftUI
import PhotosUI
import CoreData
import Vision

struct LibraryView: View {
    
    @EnvironmentObject var photoStorage: PhotoStorageService
    @State private var selectedPhotos: Set<UUID> = []
    @State private var showingPhotoDetail = false
    @State private var selectedPhoto: ReceivedPhotoModel?
    @State private var searchText = ""
    @State private var showingFilters = false
    @State private var selectedFilter: PhotoFilter = .all
    @State private var viewMode: ViewMode = .grid
    

    enum ViewMode {
        case grid
        case list
    }
    
    enum PhotoFilter {
        case all
        case withFaces
        case unshared
        case favorites
        case tagged(String)
    }
    
    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 130), spacing: AppSpacing.gridUnit)
    ]
    
    private var filteredPhotos: [ReceivedPhotoModel] {
        var photos = photoStorage.photos
        
        // Apply search filter
        if !searchText.isEmpty {
            let searchTerms = searchText.lowercased().split(separator: " ")
            photos = photos.filter { photo in
                // Поиск по имени отправителя
                if let senderName = photo.senderName?.lowercased(),
                   searchTerms.contains(where: { senderName.contains($0) }) {
                    return true
                }
                
                // Поиск по распознанным лицам
                if photo.recognizedFaces.contains(where: { face in
                    if let name = face.name?.lowercased() {
                        return searchTerms.contains(where: { name.contains($0) })
                    }
                    return false
                }) {
                    return true
                }
                
                // Поиск по дате
                if let date = photo.dateReceived {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateStyle = .medium
                    dateFormatter.timeStyle = .none
                    let dateString = dateFormatter.string(from: date).lowercased()
                    if searchTerms.contains(where: { dateString.contains($0) }) {
                        return true
                    }
                }
                
                return false
            }
        }
        
        // Apply selected filter
        switch selectedFilter {
        case .all:
            break
        case .withFaces:
            photos = photos.filter { !$0.recognizedFaces.isEmpty }
        case .unshared:
            photos = photos.filter { !$0.isShared }
        case .favorites:
            photos = photos.filter { $0.isFavorite }
        case .tagged(let person):
            photos = photos.filter { photo in
                photo.recognizedFaces.contains { $0.name == person }
            }
        }
        
        return photos
    }
    
    // Группировка по месяцу и году
    private var groupedPhotos: [(title: String, items: [ReceivedPhotoModel])] {
        let calendar = Calendar.current
        
        // Сначала группируем по лицам
        var faceGroups: [String: [ReceivedPhotoModel]] = [:]
        for photo in filteredPhotos {
            for face in photo.recognizedFaces {
                if let name = face.name {
                    if faceGroups[name] == nil {
                        faceGroups[name] = []
                    }
                    faceGroups[name]?.append(photo)
                }
            }
        }
        
        // Затем группируем по дате для фото без лиц
        let photosWithoutFaces = filteredPhotos.filter { $0.recognizedFaces.isEmpty }
        let dateGroups = Dictionary(grouping: photosWithoutFaces) { (photo) -> String in
            guard let date = photo.dateReceived else { return "Без даты" }
            let components = calendar.dateComponents([.year, .month], from: date)
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale.current
            dateFormatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
            if let date = calendar.date(from: components) {
                return dateFormatter.string(from: date)
            }
            return "Без даты"
        }
        
        // Объединяем группы лиц и дат
        var result: [(title: String, items: [ReceivedPhotoModel])] = []
        
        // Добавляем группы лиц
        for (name, photos) in faceGroups.sorted(by: { $0.key < $1.key }) {
            if photos.count >= 2 { // Показываем только группы с 2 и более фото
                result.append((title: "Лица: \(name)", items: photos))
            }
        }
        
        // Добавляем группы по дате
        let sortedKeys = dateGroups.keys.sorted { key1, key2 in
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale.current
            dateFormatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
            if let d1 = dateFormatter.date(from: key1), let d2 = dateFormatter.date(from: key2) {
                return d1 > d2
            }
            return key1 > key2
        }
        
        for key in sortedKeys {
            if let items = dateGroups[key], !items.isEmpty {
                result.append((title: key, items: items))
            }
        }
        
        return result
    }
    
    private var faceAlbums: [(id: String, title: String, count: Int)] {
        var albums: [(id: String, title: String, count: Int)] = []
        
        // Группируем фото по распознанным лицам
        var faceGroups: [String: [ReceivedPhotoModel]] = [:]
        for photo in photoStorage.photos {
            for face in photo.recognizedFaces {
                if let name = face.name {
                    if faceGroups[name] == nil {
                        faceGroups[name] = []
                    }
                    faceGroups[name]?.append(photo)
                }
            }
        }
        
        // Создаем альбомы для каждого лица с 2 и более фото
        for (name, photos) in faceGroups {
            if photos.count >= 2 {
                albums.append((id: name, title: "With \(name)", count: photos.count))
            }
        }
        
        return albums.sorted { $0.title < $1.title }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text("Library")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(AppColors.textPrimary)
                 Spacer()
            }
            .padding(.top, 8)
            .padding(.bottom, 4)
            // Поисковая строка
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Color(.systemGray3))
                TextField("Search photos by person, date, or lo", text: $searchText)
                    .font(.system(size: 19))
                    .foregroundColor(.gray)
            }
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(18)
            
            // Альбомы горизонтально
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    Button(action: {
                        selectedFilter = .all
                    }) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("All Photos")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.black)
                            Text("\(photoStorage.photos.count) photos")
                                .font(.system(size: 15))
                                .foregroundColor(.gray)
                        }
                        .frame(width: 140, height: 60)
                        .background(Color.white)
                        .cornerRadius(18)
                        .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
                    }
                    
                    ForEach(faceAlbums, id: \.id) { album in
                        Button(action: {
                            selectedFilter = .tagged(album.id)
                        }) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(album.title)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(.black)
                                Text("\(album.count) photos")
                                    .font(.system(size: 15))
                                    .foregroundColor(.gray)
                            }
                            .frame(width: 140, height: 60)
                            .background(Color.white)
                            .cornerRadius(18)
                            .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
            .padding(.vertical)
            // Сетка фото
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(filteredPhotos) { photo in
                        ZStack(alignment: .topTrailing) {
                            if let image = photo.image {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 120)
                                    .clipped()
                                    .cornerRadius(16)
                            } else {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(.systemGray5))
                                    .frame(width: 120, height: 120)
                                    .overlay(
                                        Image(systemName: "questionmark.square")
                                            .font(.system(size: 32))
                                            .foregroundColor(.gray)
                                    )
                            }
                            // Бейдж с именем, если есть совпадение
                            if let face = photo.recognizedFaces.first, let name = face.name, !name.isEmpty {
                                Text(name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.blue)
                                    .cornerRadius(14)
                                    .padding(6)
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .background(AppColors.cardBackground)
    }
    
    private func togglePhotoSelection(_ photo: ReceivedPhotoModel) {
        if selectedPhotos.contains(photo.id) {
            selectedPhotos.remove(photo.id)
        } else {
            selectedPhotos.insert(photo.id)
        }
    }
}

struct PhotoThumbnailView: View {
    let photo: ReceivedPhotoModel
    let isSelected: Bool
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let image = photo.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .frame(height: 120)
                    .clipped()
                    .overlay(
                        RoundedRectangle(cornerRadius: AppSpacing.cardCornerRadius)
                            .stroke(isSelected ? AppColors.accent : Color.clear, lineWidth: 3)
                    )
            }
            
            // Face Recognition Badge
            if !photo.recognizedFaces.isEmpty {
                HStack(spacing: 2) {
                    Image(systemName: "person.fill")
                        .font(.caption2)
                    Text("\(photo.recognizedFaces.count)")
                        .font(.caption2)
                }
                .padding(4)
                .background(AppColors.textPrimary.opacity(0.7))
                .foregroundColor(AppColors.cardBackground)
                .cornerRadius(AppSpacing.buttonCornerRadius)
                .padding(4)
            }
        }
        .cornerRadius(AppSpacing.cardCornerRadius)
        .shadow(AppShadows.small)
    }
}

struct FilterView: View {
    @Binding var selectedFilter: LibraryView.PhotoFilter
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Button("All Photos") {
                    selectedFilter = .all
                    dismiss()
                }
                Button("Photos with Faces") {
                    selectedFilter = .withFaces
                    dismiss()
                }
                Button("Unshared Photos") {
                    selectedFilter = .unshared
                    dismiss()
                }
                Button("Favorites") {
                    selectedFilter = .favorites
                    dismiss()
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    let faceEmbeddingService = FaceEmbeddingService()
    let faceLabelingService = FaceLabelingService(faceEmbeddingService: faceEmbeddingService)
    let photoStorage = PhotoStorageService(
        context: PersistenceController.shared.container.viewContext,
        faceLabelingService: faceLabelingService
    )
    
    return LibraryView()
        .environmentObject(photoStorage)
}

// MOCK DATA STRUCTURES (добавить в начало файла или заменить на свои реальные данные)
private struct Album: Identifiable { let id = UUID(); let title: String; let count: Int }
private let albumData: [Album] = [
    .init(title: "Recent Trips", count: 142),
    .init(title: "With Emma", count: 89),
    .init(title: "Not Yet Sent", count: 23)
]
private struct PhotoGridItem: Identifiable { let id = UUID(); let image: UIImage?; let badge: String? }
private let photoGridData: [PhotoGridItem] = [
    .init(image: UIImage(named: "emma"), badge: "Emma"),
    .init(image: UIImage(named: "group"), badge: "+3"),
    .init(image: UIImage(named: "mountain"), badge: nil),
    .init(image: nil, badge: "Sarah"),
    .init(image: UIImage(named: "hands"), badge: "+2"),
    .init(image: nil, badge: nil),
    .init(image: UIImage(named: "wave"), badge: "Dad"),
    .init(image: UIImage(named: "concert"), badge: "+5"),
    .init(image: UIImage(named: "hike"), badge: nil)
]
