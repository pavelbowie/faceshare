//
//  ReceivedPhotoEntity.swift
//  SharePhotoGroup
//
//  Created by Pavel Mac on 21/04/25
//

import CoreData
import UIKit

extension ReceivedPhotoEntity {
    var image: UIImage? {
        get {
            guard let data = imageData else { return nil }
            return UIImage(data: data)
        }
        set {
            imageData = newValue?.jpegData(compressionQuality: 0.8)
        }
    }
} 
