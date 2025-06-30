//
//  MyFacesView.swift
//  SharePhotoGroup
//
//  Created by Pavel Mac on 21/04/25
//

import SwiftUI
import Photos
import Combine

struct MyFacesView: View {
    @EnvironmentObject var faceStore: FaceStore
    @StateObject private var photoLibraryService = PhotoLibraryService()
    @StateObject private var faceDetectionService = FaceDetectionService()
    @StateObject private var faceEmbeddingService = FaceEmbeddingService()
    @State private var isRefreshing = false
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                if faceStore.faces.isEmpty {
                    VStack(spacing: AppSpacing.grid3x) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 60))
                            .foregroundColor(AppColors.textSecondary)
                        Text("No faces discovered yet")
                            .font(AppTypography.sectionTitle)
                            .foregroundColor(AppColors.textPrimary)
                        Text("Scan your photos to find faces.")
                            .font(AppTypography.bodyText)
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .padding(.top, AppSpacing.grid4x)
                } else {
                    ScrollView {
                        VStack(spacing: AppSpacing.grid2x) {
                            ForEach(faceStore.faces) { faceData in
                                FaceRow(image: faceData.image, faceData: faceData)
                            }
                        }
                        .padding(.top, AppSpacing.grid2x)
                        .padding(.horizontal, AppSpacing.horizontalPadding)
                    }
                }
            }
            if isRefreshing {
                Color.black.opacity(0.1).ignoresSafeArea()
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: AppColors.accent))
                    .scaleEffect(1.5)
            }
        }
        .navigationTitle("My Faces")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    refreshFaces()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                        .foregroundColor(AppColors.accent)
                }
                .disabled(isRefreshing)
            }
        }
        .onAppear {
            // Не сканируем автоматически, просто отображаем
        }
    }
    
    private func refreshFaces() {
        isRefreshing = true
        faceStore.clear()
        cancellables.removeAll()
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        for i in 0..<min(assets.count, 2) {
            let asset = assets[i]
            photoLibraryService.getImage(from: asset, targetSize: CGSize(width: 800, height: 800)) { [weak faceDetectionService] image in
                guard let image = image else { return }
                faceDetectionService?.detectFaces(in: image)
                    .sink(receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            print("Error detecting faces: \(error)")
                        }
                    }, receiveValue: { observations in
                        for observation in observations {
                            if let faceImage = faceDetectionService?.cropFace(from: image, observation: observation) {
                                do {
                                    let embedding = try faceEmbeddingService.getEmbedding(for: faceImage)
                                    let faceData = FaceData(image: faceImage, fullImage: image, embedding: embedding)
                                    DispatchQueue.main.async {
                                        faceStore.add([faceData])
                                    }
                                } catch {
                                    print("Ошибка получения embedding: \(error)")
                                }
                            }
                        }
                        if i == min(assets.count, 2) - 1 {
                            DispatchQueue.main.async {
                                isRefreshing = false
                            }
                        }
                    })
                    .store(in: &cancellables)
            }
        }
    }
}

struct FaceRow: View {
    let image: UIImage
    let faceData: FaceData

    var body: some View {
        HStack(spacing: AppSpacing.grid3x) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(Circle())
                .shadow(AppShadows.small)
            VStack(alignment: .leading, spacing: 4) {
                Text("Face discovered")
                    .font(AppTypography.bodyText)
                    .foregroundColor(AppColors.textPrimary)
                Text("Embedding: \(faceData.embedding.prefix(5).map { String(format: "%.2f", $0) }.joined(separator: ", ")) ...")
                    .font(AppTypography.subtext)
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Circle()
                .fill(Color.green)
                .frame(width: 12, height: 12)
        }
        .padding(AppSpacing.grid2x)
        .background(AppColors.cardBackground)
        .cornerRadius(AppSpacing.cardCornerRadius)
        .shadow(AppShadows.small)
    }
}

struct MyFacesView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            MyFacesView().environmentObject(FaceStore())
        }
    }
} 
