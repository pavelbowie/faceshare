//
//  PeopleView.swift
//  SharePhotoGroup
//
//  Created by Pavel Mac on 24/04/25
//

import SwiftUI
import PhotosUI
import CoreData
import Vision

struct PeopleView: View {
    
    @EnvironmentObject var photoStorage: PhotoStorageService
    @State private var selectedPhotos: Set<UUID> = []
    @State private var showingPhotoDetail = false
    @State private var selectedPhoto: ReceivedPhotoModel?
    @State private var searchText = ""
    @State private var showingFilters = false
    @State private var selectedFilter: PhotoFilter = .all
    @State private var viewMode: ViewMode = .grid
    @State private var selectedGroup: (name: String?, photos: [ReceivedPhotoModel])?
    @State private var showSheet = false
    

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
    
    // Группировка по распознанным лицам и нераспознанным
    private var groupedByPerson: [(name: String?, photos: [ReceivedPhotoModel])] {
        var groups: [String?: [ReceivedPhotoModel]] = [:]
        for photo in filteredPhotos {
            if let face = photo.recognizedFaces.first, let name = face.name, !name.isEmpty {
                groups[name, default: []].append(photo)
            } else {
                groups[nil, default: []].append(photo)
            }
        }
        // Сортируем: сначала с именем, потом без
        let sorted = groups.sorted { (lhs, rhs) in
            switch (lhs.key, rhs.key) {
            case let (l?, r?):
                return l < r
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return false
            }
        }
        return sorted.map { ($0.key, $0.value) }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    Text("People")
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
                    TextField("Search people by name or face", text: $searchText)
                        .font(.system(size: 19))
                        .foregroundColor(.gray)
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(18)
                .padding(.vertical)
                // Группы людей
                ScrollView(showsIndicators: false){
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(groupedByPerson, id: \.name) { group in
                            NavigationLink(
                                destination: PeopleDetailView(
                                    name: group.name ?? "Needs Labeling",
                                    avatar: group.photos.first?.image,
                                    photoCount: group.photos.count,
                                     photos: group.photos
                                )
                            ) {
                                PeopleCardView(group: group) {}
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding()
            .background(AppColors.cardBackground)
        }
    }

//    private func getLastSeen(for group: (name: String?, photos: [ReceivedPhotoModel])) -> String? {
//        // Пример: ищем максимальный lastSeen среди всех фото этого человека
//        let lastSeens = group.photos.compactMap { photo in
//            photo.recognizedFaces.first(where: { $0.name == group.name })?.lastSeen
//        }
//        return lastSeens.max()
//    }

    private func togglePhotoSelection(_ photo: ReceivedPhotoModel) {
        if selectedPhotos.contains(photo.id) {
            selectedPhotos.remove(photo.id)
        } else {
            selectedPhotos.insert(photo.id)
        }
    }
}
