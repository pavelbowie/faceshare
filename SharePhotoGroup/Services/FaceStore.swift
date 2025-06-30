//
//  FaceData.swift
//  SharePhotoGroup
//
//  Created by Pavel Mac on 22/04/25
//

import SwiftUI
import CoreData

struct FaceData: Identifiable {
    let id: UUID
    let image: UIImage
    let fullImage: UIImage
    let embedding: [Float]
    
    init(image: UIImage, fullImage: UIImage, embedding: [Float]) {
        self.id = UUID()
        self.image = image
        self.fullImage = fullImage
        self.embedding = embedding
    }
    
    init(from entity: FaceEntity) {
        self.id = entity.id ?? UUID()
        self.image = entity.faceImage.flatMap { UIImage(data: $0) } ?? UIImage()
        self.fullImage = entity.fullImage.flatMap { UIImage(data: $0) } ?? UIImage()
        self.embedding = entity.embedding ?? []
    }
}

class FaceStore: ObservableObject {
    @Published var faces: [FaceData] = []
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.context = context
        loadFaces()
    }
    
    private func loadFaces() {
        let request: NSFetchRequest<FaceEntity> = FaceEntity.fetchRequest()
        do {
            let entities = try context.fetch(request)
            faces = entities.map { FaceData(from: $0) }
        } catch {
            print("Error loading faces: \(error)")
        }
    }
    
    func add(_ newFaces: [FaceData]) {
        for face in newFaces {
            let entity = FaceEntity(context: context)
            entity.id = face.id
            entity.faceImage = face.image.jpegData(compressionQuality: 0.8)
            entity.fullImage = face.fullImage.jpegData(compressionQuality: 0.8)
            entity.embedding = face.embedding
        }
        
        do {
            try context.save()
            loadFaces() // Reload faces after saving
        } catch {
            print("Error saving faces: \(error)")
        }
    }
    
    func clear() {
        let request: NSFetchRequest<NSFetchRequestResult> = FaceEntity.fetchRequest()
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        
        do {
            try context.execute(deleteRequest)
            try context.save()
            faces.removeAll()
        } catch {
            print("Error clearing faces: \(error)")
        }
    }
} 
