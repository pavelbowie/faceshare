//
//  Theme.swift
//  SharePhotoGroup
//
//  Created by Pavel Mac on 21/04/25
//

import Foundation
//
//  PhotoModels.swift
//  SharePhotoGroup
//
//  Created by Pavel Mac on 19/04/25
//

import UIKit

//Импортируем LabelSource из FaceLabelingService
//@_exported import enum SharePhotoGroup.LabelSource

struct ReceivedPhotoModel: Identifiable, Equatable {
    let id: UUID
    let image: UIImage?
    let dateReceived: Date?
    var recognizedFaces: [RecognizedFace] = []
    var senderName: String?
    var senderAvatar: UIImage?
    var isShared: Bool = false
    var isFavorite: Bool = false
    
    static func == (lhs: ReceivedPhotoModel, rhs: ReceivedPhotoModel) -> Bool {
        return lhs.id == rhs.id
    }
}

struct RecognizedFace: Identifiable {
    let id = UUID()
    let name: String?
    let confidence: Float
    let source: LabelSource
} 
