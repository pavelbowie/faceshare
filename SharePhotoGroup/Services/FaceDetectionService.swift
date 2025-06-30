//
//  FaceDetectionService.swift
//  SharePhotoGroup
//
//  Created by Pavel Mac on 25/04/25
//

import Vision
import UIKit
import Combine

class FaceDetectionService: ObservableObject {
    
    private let faceDetectionRequest = VNDetectFaceRectanglesRequest()
    private let faceLandmarksRequest = VNDetectFaceLandmarksRequest()
    private let sequenceHandler = VNSequenceRequestHandler()
    private let faceDetectionQueue = DispatchQueue(label: "faceDetectionQueue", qos: .userInitiated)
    
    func detectFaces(in image: UIImage) -> AnyPublisher<[VNFaceObservation], Error> {
        return Future<[VNFaceObservation], Error> { [weak self] promise in
            guard let self = self,
                  let cgImage = image.cgImage else {
                promise(.failure(NSError(domain: "FaceDetectionService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid image"])))
                return
            }
            
            self.faceDetectionQueue.async {
                let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                
                do {
                    try requestHandler.perform([self.faceDetectionRequest])
                    if let observations = self.faceDetectionRequest.results as? [VNFaceObservation] {
                        promise(.success(observations))
                    } else {
                        promise(.success([]))
                    }
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    func cropFace(from image: UIImage, observation: VNFaceObservation) -> UIImage? {
        let imageSize = image.size
        let boundingBox = observation.boundingBox
        
        // Конвертируем координаты из Vision в UIKit
        let rect = CGRect(
            x: boundingBox.origin.x * imageSize.width,
            y: (1 - boundingBox.origin.y - boundingBox.height) * imageSize.height,
            width: boundingBox.width * imageSize.width,
            height: boundingBox.height * imageSize.height
        )
        
        // Добавляем отступы
        let padding: CGFloat = 0.2
        let paddedRect = rect.insetBy(dx: -rect.width * padding, dy: -rect.height * padding)
        
        // Обрезаем изображение
        UIGraphicsBeginImageContextWithOptions(paddedRect.size, false, image.scale)
        image.draw(at: CGPoint(x: -paddedRect.origin.x, y: -paddedRect.origin.y))
        let croppedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return croppedImage
    }
}

enum FaceDetectionError: Error {
    case invalidImage
    case noFacesDetected
    case processingError
} 
