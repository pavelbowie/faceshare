//
//  SharePhotoGroupApp.swift
//  SharePhotoGroup
//
//  Created by Pavel Mac on 30/04/25
//

import SwiftUI

@main
struct SharePhotoGroupApp: App {
    let persistenceController = PersistenceController.shared
    
    @StateObject private var coordinator = AppCoordinator()
    @StateObject private var faceEmbeddingService = FaceEmbeddingService()
    @StateObject private var faceLabelingService: FaceLabelingService
    @StateObject private var photoStorage: PhotoStorageService
    @StateObject private var multipeerService: MultipeerService
    @StateObject private var faceStore = FaceStore()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    init() {
        let faceEmbeddingService = FaceEmbeddingService()
        let faceLabelingService = FaceLabelingService(faceEmbeddingService: faceEmbeddingService)
        let photoStorage = PhotoStorageService(
            context: PersistenceController.shared.container.viewContext,
            faceLabelingService: faceLabelingService
        )
        
        _faceEmbeddingService = StateObject(wrappedValue: faceEmbeddingService)
        _faceLabelingService = StateObject(wrappedValue: faceLabelingService)
        _photoStorage = StateObject(wrappedValue: photoStorage)
        _multipeerService = StateObject(wrappedValue: MultipeerService(photoStorage: photoStorage))
    }

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                ContentView()
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
                    .environmentObject(coordinator)
                    .environmentObject(photoStorage)
                    .environmentObject(multipeerService)
                    .environmentObject(faceEmbeddingService)
                    .environmentObject(faceLabelingService)
                    .environmentObject(faceStore)
                    .onAppear {
                        // Загружаем фотографии при запуске приложения
                        photoStorage.loadPhotos()
                        
                        multipeerService.configure(
                            faceStore: faceStore,
                            embeddingService: faceEmbeddingService,
                            labelingService: faceLabelingService
                        )
                        multipeerService.startBrowsing()
                        multipeerService.startAdvertising()
                    }
            } else {
                OnBoardingView()
                    .environmentObject(faceEmbeddingService)
                    .environmentObject(coordinator)
                    .environmentObject(faceLabelingService)
            }
        }
    }
}
