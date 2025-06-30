//
//  CryptoService.swift
//  SharePhotoGroup
//
//  Created by Pavel Mac on 21/04/25
//

import CryptoKit
import Foundation
import UIKit

class CryptoService {
    
    private let key: SymmetricKey
    
    init() {
        // Генерируем ключ при инициализации
        self.key = SymmetricKey(size: .bits256)
    }
    
    func encrypt(_ data: Data) throws -> Data {
        let nonce = try AES.GCM.Nonce(data: Data(repeating: 0, count: 12))
        let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)
        return sealedBox.combined ?? Data()
    }
    
    func decrypt(_ data: Data) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: key)
    }
    
    func encryptImage(_ image: UIImage) throws -> Data {
        guard let imageData = image.jpegData(compressionQuality: 0.5) else {
            throw CryptoError.imageConversionFailed
        }
        return try encrypt(imageData)
    }
    
    func decryptImage(_ data: Data) throws -> UIImage {
        let decryptedData = try decrypt(data)
        guard let image = UIImage(data: decryptedData) else {
            throw CryptoError.imageConversionFailed
        }
        return image
    }
    
    func encryptEmbedding(_ embedding: [Float]) throws -> Data {
        let data = try JSONEncoder().encode(embedding)
        return try encrypt(data)
    }
    
    func decryptEmbedding(_ data: Data) throws -> [Float] {
        let decryptedData = try decrypt(data)
        return try JSONDecoder().decode([Float].self, from: decryptedData)
    }
}

enum CryptoError: Error {
    case imageConversionFailed
    case encryptionFailed
    case decryptionFailed
} 
