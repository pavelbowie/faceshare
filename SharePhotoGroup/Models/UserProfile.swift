//
//  UserProfile.swift
//  SharePhotoGroup
//
//  Created by Pavel Mac on 22/04/25
//

import Foundation
import UIKit

class UserProfile: ObservableObject {
    @Published var profileImage: UIImage?
    @Published var faceEmbedding: [Float]?
    @Published var contactIdentifier: String?
    @Published var contactName: String?

    static let shared = UserProfile()

    private init() {
        loadFromDefaults()
    }

    func updateProfile(image: UIImage?, embedding: [Float]?, contactId: String?, contactName: String?) {
        self.profileImage = image
        self.faceEmbedding = embedding
        self.contactIdentifier = contactId
        self.contactName = contactName
        saveToDefaults()
    }

    private func saveToDefaults() {
        if let image = profileImage, let data = image.jpegData(compressionQuality: 0.9) {
            UserDefaults.standard.set(data, forKey: "profileImageData")
        } else {
            UserDefaults.standard.removeObject(forKey: "profileImageData")
        }
        if let embedding = faceEmbedding {
            let array = embedding.map { NSNumber(value: $0) }
            UserDefaults.standard.set(array, forKey: "faceEmbedding")
        } else {
            UserDefaults.standard.removeObject(forKey: "faceEmbedding")
        }
        UserDefaults.standard.set(contactIdentifier, forKey: "contactIdentifier")
        UserDefaults.standard.set(contactName, forKey: "contactName")
    }

    private func loadFromDefaults() {
        if let data = UserDefaults.standard.data(forKey: "profileImageData"),
           let image = UIImage(data: data) {
            self.profileImage = image
        }
        if let array = UserDefaults.standard.array(forKey: "faceEmbedding") as? [NSNumber] {
            self.faceEmbedding = array.map { $0.floatValue }
        }
        self.contactIdentifier = UserDefaults.standard.string(forKey: "contactIdentifier")
        self.contactName = UserDefaults.standard.string(forKey: "contactName")
    }
}
