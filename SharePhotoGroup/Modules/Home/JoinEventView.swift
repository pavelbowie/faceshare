//
//  JoinEventView.swift
//  SharePhotoGroup
//
//  Created by Pavel Mac on 21/04/25
//

import SwiftUI
import MultipeerConnectivity
import Vision

struct JoinEventView: View {
    @StateObject private var userProfile = UserProfile.shared
    @EnvironmentObject var multipeerService: MultipeerService
    @EnvironmentObject var photoStorage: PhotoStorageService
    @EnvironmentObject var faceStore: FaceStore
    @EnvironmentObject var faceEmbeddingService: FaceEmbeddingService
    @State private var isSearching = false
    @State private var logs: [String] = []
    @State private var searchText: String = ""
    @State private var photosToSend: [UIImage] = []
    @State private var showPhotoConfirmation = false
    @State private var selectedPeer: MCPeerID?
    @State private var showProfileSetupAlert = false
    @State private var showSettings = false
    
    var filteredPeers: [MCPeerID] {
        if searchText.isEmpty {
            return multipeerService.connectedPeers
        } else {
            return multipeerService.connectedPeers.filter { peer in
                let name = getPeerName(peer)
                return name.lowercased().contains(searchText.lowercased())
            }
        }
    }
    
    private func getPeerName(_ peer: MCPeerID) -> String {
        // Сначала проверяем MultipeerService
        if let contact = multipeerService.peerToContact[peer] {
            return contact.name
        }
        
        // Если нет в MultipeerService, ищем в PhotoStorageService
        if let photo = photoStorage.photos.first(where: { photo in
            // Проверяем наличие имени отправителя
            if let senderName = photo.senderName, !senderName.isEmpty {
                return true
            }
            // Проверяем наличие распознанных лиц
            if !photo.recognizedFaces.isEmpty {
                return true
            }
            return false
        }) {
            // Возвращаем имя отправителя или имя первого распознанного лица
            return photo.senderName ?? photo.recognizedFaces.first?.name ?? peer.displayName
        }
        
        // Если нигде не нашли, используем displayName как запасной вариант
        return peer.displayName
    }
    
    private func getPeerAvatar(_ peer: MCPeerID) -> UIImage? {
        // Сначала проверяем MultipeerService
        if let contact = multipeerService.peerToContact[peer] {
            return contact.avatar
        }
        
        // Если нет в MultipeerService, ищем в PhotoStorageService
        if let photo = photoStorage.photos.first(where: { photo in
            // Проверяем наличие аватарки отправителя
            return photo.senderAvatar != nil
        }) {
            return photo.senderAvatar
        }
        
        return nil
    }
    
    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: AppSpacing.sectionGap) {
                    // Top spacing to visually separate from nav bar
                    Spacer().frame(height: AppSpacing.grid3x)
                    
                    // User Profile Section
                    VStack(spacing: AppSpacing.grid2x) {
                        if let image = userProfile.profileImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipShape(Circle())
                                .shadow(AppShadows.medium)
                        } else {
                            Image(systemName: "person.crop.circle")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 80, height: 80)
                                .foregroundColor(AppColors.textSecondary)
                        }
                        
                        Text(userProfile.contactName ?? "Your Name")
                            .font(AppTypography.bodyText)
                            .foregroundColor(AppColors.textPrimary)
                    }
                    .padding(.bottom, AppSpacing.grid2x)
                    
                    SearchBarView(searchText: $searchText)
                    AutoSendToggleView(isOn: $multipeerService.autoSendPhotos)
                    
                    if isSearching {
                        SearchingView()
                    }
                    
                    if !filteredPeers.isEmpty {
                        AvailablePeopleView(
                            peers: filteredPeers,
                            getPeerName: getPeerName,
                            getPeerAvatar: getPeerAvatar,
                            onSend: handleSend
                        )
                    } else if !isSearching {
                        NoPeopleFoundView()
                    }
                    
                    if !logs.isEmpty {
                        LogsView(logs: logs)
                    }
                    
                    Spacer(minLength: AppSpacing.grid4x)
                }
            }
        }
        .navigationTitle("Join Event")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            checkProfileAndStartSearch()
        }
        .onDisappear { isSearching = false }
        .onChange(of: UserProfile.shared.faceEmbedding, perform: handleEmbeddingChange)
        .onChange(of: photoStorage.photos) { _ in }
        .sheet(isPresented: $showPhotoConfirmation) {
            PhotoConfirmationView(
                photos: $photosToSend,
                onConfirm: handlePhotoConfirmation,
                onCancel: { showPhotoConfirmation = false }
            )
        }
        .alert("Profile Setup Required", isPresented: $showProfileSetupAlert) {
            Button("Go to Settings") {
                showSettings = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please set up your profile (name and photo) in Settings before searching for devices.")
        }
        .sheet(isPresented: $showSettings) {
            NavigationView {
                SettingsView()
            }
        }
    }
    
    private func checkProfileAndStartSearch() {
        if let _ = UserProfile.shared.contactName,
           let _ = UserProfile.shared.profileImage {
            // Профиль настроен, начинаем поиск
            multipeerService.startBrowsing()
            multipeerService.startAdvertising()
        } else {
            // Профиль не настроен, показываем предупреждение
            showProfileSetupAlert = true
        }
    }
    private func handleSend(for peer: MCPeerID) {
        selectedPeer = peer
        // Проверяем наличие эмбеддинга у текущего пользователя
        guard let userEmbedding = UserProfile.shared.faceEmbedding else {
            logs.append("Error: You don't have a face embedding. Please add a profile photo in settings.")
            return
        }
        
        // Получаем эмбеддинг выбранного пира
        if let peerEmbedding = multipeerService.receivedEmbeddings.first(where: { $0.peerID == peer })?.embedding {
            logs.append("Starting search for similar photos for \(peer.displayName)")
            
            let similarPhotos = photoStorage.photos.filter { photo in
                // Проверяем каждое лицо на фотографии
                return photo.recognizedFaces.contains { face in
                    if let embeddingService = multipeerService.embeddingService {
                        // Получаем эмбеддинг для лица на фотографии
                        if let faceImage = photo.image,
                           let cgImage = faceImage.cgImage {
                            let request = VNDetectFaceRectanglesRequest()
                            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                            
                            do {
                                try handler.perform([request])
                                if let results = request.results as? [VNFaceObservation],
                                   let firstFace = results.first {
                                    // Кропаем лицо
                                    let boundingBox = firstFace.boundingBox
                                    let width = CGFloat(cgImage.width)
                                    let height = CGFloat(cgImage.height)
                                    let rect = CGRect(
                                        x: boundingBox.origin.x * width,
                                        y: (1 - boundingBox.origin.y - boundingBox.height) * height,
                                        width: boundingBox.width * width,
                                        height: boundingBox.height * height
                                    ).integral
                                    
                                    if let faceCgImage = cgImage.cropping(to: rect) {
                                        let faceImage = UIImage(cgImage: faceCgImage)
                                        // Получаем эмбеддинг для лица
                                        if let faceEmbedding = try? embeddingService.getEmbedding(for: faceImage) {
                                            // Сравниваем эмбеддинги
                                            let similarity = embeddingService.calculateSimilarity(faceEmbedding, peerEmbedding)
                                            let percent = Int(similarity * 100)
                                            logs.append("Similarity with \(face.name ?? "unknown"): \(percent)%")
                                            return similarity > 0.5 // Порог схожести 30%
                                        }
                                    }
                                }
                            } catch {
                                logs.append("Error detecting face: \(error.localizedDescription)")
                            }
                        }
                    }
                    return false
                }
            }
            
            // Получаем изображения из найденных фотографий
            photosToSend = similarPhotos.compactMap { $0.image }
            logs.append("Found \(photosToSend.count) photos with similarity > 30%")
            
            // Добавляем отладочную информацию
            if photosToSend.isEmpty {
                logs.append("⚠️ No photos selected for sending. Debug info:")
                logs.append("- Total photos in storage: \(photoStorage.photos.count)")
                logs.append("- Total faces in FaceStore: \(faceStore.faces.count)")
                logs.append("- Peer embedding exists: \(peerEmbedding.count) dimensions")
            } else {
                logs.append("✅ Selected photos for sending:")
                for (index, photo) in photosToSend.enumerated() {
                    logs.append("- Photo \(index + 1): size \(photo.size.width)x\(photo.size.height)")
                }
            }
        } else {
            photosToSend = []
            logs.append("Peer embedding not found. Wait for devices to exchange embeddings.")
        }
        showPhotoConfirmation = true
    }

//    private func handleSend(for peer: MCPeerID) {
//        selectedPeer = peer
//        // Проверяем наличие эмбеддинга у текущего пользователя
//        guard let userEmbedding = UserProfile.shared.faceEmbedding else {
//            logs.append("Error: You don't have a face embedding. Please add a profile photo in settings.")
//            return
//        }
//        
//        // Получаем эмбеддинг выбранного пира
//        if let peerEmbedding = multipeerService.receivedEmbeddings.first(where: { $0.peerID == peer })?.embedding {
//            logs.append("Starting search for similar photos for \(peer.displayName)")
//            
//            // Ищем фотографии с похожими лицами в PhotoStorageService
//            let similarPhotos = photoStorage.photos.filter { photo in
//                // Проверяем каждое лицо на фотографии
//                photo.recognizedFaces.contains { face in
//                    // Проверяем, есть ли имя у лица
//                    if let name = face.name {
//                        // Ищем лицо в FaceStore по имени
//                        if let faceData = faceStore.faces.first(where: { $0.id == face.id }) {
//                            // Сравниваем эмбеддинги
//                            let similarity = faceEmbeddingService.calculateSimilarity(faceData.embedding, peerEmbedding)
//                            let percent = Int(similarity * 100)
//                            logs.append("Similarity with \(name): \(percent)%")
//                            return similarity > 0.6 // Увеличиваем порог схожести до 60%
//                        }
//                    }
//                    return false
//                }
//            }
//            
//            // Получаем изображения из найденных фотографий
//            photosToSend = similarPhotos.compactMap { $0.image }
//            logs.append("Found \(photosToSend.count) photos with similarity > 60%")
//            
//            // Добавляем отладочную информацию
//            if photosToSend.isEmpty {
//                logs.append("⚠️ No photos selected for sending. Debug info:")
//                logs.append("- Total photos in storage: \(photoStorage.photos.count)")
//                logs.append("- Total faces in FaceStore: \(faceStore.faces.count)")
//                logs.append("- Peer embedding exists: \(peerEmbedding.count) dimensions")
//                logs.append("- Peer name: \(peer.displayName)")
//            } else {
//                logs.append("✅ Selected photos for sending:")
//                for (index, photo) in photosToSend.enumerated() {
//                    logs.append("- Photo \(index + 1): size \(photo.size.width)x\(photo.size.height)")
//                }
//            }
//        } else {
//            photosToSend = []
//            logs.append("Peer embedding not found. Wait for devices to exchange embeddings.")
//        }
//        showPhotoConfirmation = true
//    }
    
    private func handleEmbeddingChange(_ newEmbedding: [Float]?) {
        if let embedding = newEmbedding {
            logs.append("Received new embedding, sending to all peers")
            // Отправляем новый эмбеддинг всем подключенным пирам
            for peer in multipeerService.connectedPeers {
                multipeerService.sendEmbedding(embedding, to: peer)
            }
        }
    }
    
    private func handlePhotoConfirmation() {
        if let peer = selectedPeer {
            for photo in photosToSend {
                multipeerService.sendPhoto(photo, to: peer)
            }
        }
        showPhotoConfirmation = false
    }
}

// MARK: - Subviews

struct SearchBarView: View {
    @Binding var searchText: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppColors.textSecondary)
            
            TextField("Search by name...", text: $searchText)
                .font(AppTypography.bodyText)
                .foregroundColor(AppColors.textPrimary)
            
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
        .padding(AppSpacing.grid2x)
        .background(AppColors.cardBackground)
        .cornerRadius(AppSpacing.buttonCornerRadius)
        .padding(.horizontal, AppSpacing.horizontalPadding)
    }
}

struct AutoSendToggleView: View {
    @Binding var isOn: Bool
    
    var body: some View {
        Toggle("Auto-send photos", isOn: $isOn)
            .font(AppTypography.bodyText)
            .foregroundColor(AppColors.textPrimary)
            .padding(.horizontal, AppSpacing.horizontalPadding)
            .padding(.vertical, AppSpacing.gridUnit)
            .background(AppColors.cardBackground)
            .cornerRadius(AppSpacing.buttonCornerRadius)
            .padding(.horizontal, AppSpacing.horizontalPadding)
    }
}

struct SearchingView: View {
    var body: some View {
        HStack {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: AppColors.primary))
            Text("Searching for devices...")
                .font(AppTypography.bodyText)
                .foregroundColor(AppColors.textSecondary)
        }
        .padding()
    }
}

struct AvailablePeopleView: View {
    let peers: [MCPeerID]
    let getPeerName: (MCPeerID) -> String
    let getPeerAvatar: (MCPeerID) -> UIImage?
    let onSend: (MCPeerID) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.gridUnit) {
            Text("Available People")
                .font(AppTypography.sectionTitle)
                .foregroundColor(AppColors.textPrimary)
                .padding(.horizontal, AppSpacing.horizontalPadding)
            
            ScrollView {
                VStack(spacing: AppSpacing.grid2x) {
                    ForEach(peers, id: \.self) { peer in
                        PeerCard(
                            peer: peer,
                            peerName: getPeerName(peer),
                            peerAvatar: getPeerAvatar(peer),
                            hasFaceEmbedding: UserProfile.shared.faceEmbedding != nil,
                            onSend: { onSend(peer) }
                        )
                    }
                }
                .padding(.horizontal, AppSpacing.horizontalPadding)
            }
        }
    }
}

struct NoPeopleFoundView: View {
    var body: some View {
        VStack(spacing: AppSpacing.grid3x) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 60))
                .foregroundColor(AppColors.textSecondary)
            
            Text("No people found")
                .font(AppTypography.sectionTitle)
                .foregroundColor(AppColors.textPrimary)
            
            Text("Make sure Bluetooth and Wi-Fi are enabled")
                .font(AppTypography.bodyText)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LogsView: View {
    let logs: [String]
    
    var body: some View {
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
}

// MARK: - Existing Components

struct PeerCard: View {
    let peer: MCPeerID
    let peerName: String
    let peerAvatar: UIImage?
    let hasFaceEmbedding: Bool
    let onSend: () -> Void
    
    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.grid3x) {
            // Avatar
            if let avatar = peerAvatar {
                Image(uiImage: avatar)
                    .resizable()
                    .scaledToFill()
                    .frame(width: AppSpacing.avatarSize, height: AppSpacing.avatarSize)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: AppSpacing.avatarSize, height: AppSpacing.avatarSize)
                    .foregroundColor(AppColors.textSecondary)
            }
            
            // Name
            Text(peerName)
                .font(AppTypography.bodyText)
                .foregroundColor(AppColors.textPrimary)
            
            Spacer()
            
            // Send button
            Button(action: onSend) {
                Text("Send")
                    .font(AppTypography.button)
                    .foregroundColor(AppColors.cardBackground)
                    .padding(.horizontal, AppSpacing.grid3x)
                    .padding(.vertical, AppSpacing.gridUnit)
                    .background(
                        RoundedRectangle(cornerRadius: AppSpacing.buttonCornerRadius)
                            .fill(hasFaceEmbedding ? AppColors.primary : AppColors.textSecondary)
                    )
            }
            .disabled(!hasFaceEmbedding)
        }
        .padding(AppSpacing.grid3x)
        .background(AppColors.cardBackground)
        .cornerRadius(AppSpacing.cardCornerRadius)
        .shadow(AppShadows.small)
    }
}

struct PhotoConfirmationView: View {
    @Binding var photos: [UIImage]
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        NavigationView {
            ZStack {
                AppColors.background
                    .ignoresSafeArea()
                
                VStack(spacing: AppSpacing.sectionGap) {
                    // Header
                    Text("Confirm Photos")
                        .font(AppTypography.display(for: .title))
                        .foregroundColor(AppColors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, AppSpacing.horizontalPadding)
                        .padding(.top, AppSpacing.grid3x)
                    
                    // Photos grid
                    if photos.isEmpty {
                        VStack(spacing: AppSpacing.grid3x) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 60))
                                .foregroundColor(AppColors.textSecondary)
                            
                            Text("No photos found")
                                .font(AppTypography.sectionTitle)
                                .foregroundColor(AppColors.textPrimary)
                            
                            Text("No similar photos were found for this person")
                                .font(AppTypography.bodyText)
                                .foregroundColor(AppColors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 120))], spacing: AppSpacing.grid2x) {
                                ForEach(Array(photos.enumerated()), id: \.offset) { index, photo in
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: photo)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 100, height: 100)
                                            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.buttonCornerRadius))
                                        
                                        Button(action: {
                                            photos.remove(at: index)
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(AppColors.error)
                                                .background(Circle().fill(AppColors.cardBackground))
                                        }
                                        .offset(x: 8, y: -8)
                                    }
                                }
                            }
                            .padding(AppSpacing.horizontalPadding)
                        }
                    }
                    
                    Spacer()
                    
                    // Action buttons
                    HStack(spacing: AppSpacing.grid3x) {
                        Button(action: onCancel) {
                            Text("Cancel")
                                .font(AppTypography.button)
                                .foregroundColor(AppColors.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppSpacing.grid2x)
                                .background(
                                    RoundedRectangle(cornerRadius: AppSpacing.buttonCornerRadius)
                                        .stroke(AppColors.textSecondary, lineWidth: 1)
                                )
                        }
                        
                        Button(action: onConfirm) {
                            Text("Send")
                                .font(AppTypography.button)
                                .foregroundColor(AppColors.cardBackground)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppSpacing.grid2x)
                                .background(
                                    RoundedRectangle(cornerRadius: AppSpacing.buttonCornerRadius)
                                        .fill(AppColors.accent)
                                )
                        }
                    }
                    .padding(.horizontal, AppSpacing.horizontalPadding)
                    .padding(.bottom, AppSpacing.grid3x)
                }
            }
            .navigationBarHidden(true)
        }
    }
}

struct JoinEventView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            JoinEventView()
        }
    }
}
