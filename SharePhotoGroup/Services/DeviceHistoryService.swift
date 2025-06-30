//
//  DeviceHistoryService.swift
//  SharePhotoGroup
//
//  Created by Pavel Mac on 25/04/25
//

import CoreData
import UIKit
import MultipeerConnectivity

class DeviceHistoryService: ObservableObject {
    
    private let context: NSManagedObjectContext
    @Published var deviceHistory: [DeviceHistoryEntity] = []
    
    init(context: NSManagedObjectContext) {
        self.context = context
        loadDeviceHistory()
    }
    
    func loadDeviceHistory() {
        let request: NSFetchRequest<DeviceHistoryEntity> = DeviceHistoryEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \DeviceHistoryEntity.lastConnected, ascending: false)]
        
        do {
            deviceHistory = try context.fetch(request)
            print("📱 Загружено \(deviceHistory.count) устройств из истории")
        } catch {
            print("❌ Ошибка загрузки истории устройств: \(error)")
        }
    }
    
    func updateDeviceHistory(peer: MCPeerID, name: String?, avatar: UIImage?) {
        let request: NSFetchRequest<DeviceHistoryEntity> = DeviceHistoryEntity.fetchRequest()
        request.predicate = NSPredicate(format: "deviceId == %@", peer.displayName)
        
        do {
            let results = try context.fetch(request)
            let device: DeviceHistoryEntity
            var deviceName = name
            
            if let existingDevice = results.first {
                device = existingDevice
                print("📱 Обновляем существующее устройство: \(peer.displayName)")
                
                // Сохраняем существующие данные, если новые не предоставлены
                if deviceName == nil {
                    deviceName = device.deviceName
                }
                if avatar == nil && device.avatarData != nil {
                    // Не обновляем аватар, если он уже есть и новый не предоставлен
                    try context.save()
                    loadDeviceHistory()
                    return
                }
            } else {
                device = DeviceHistoryEntity(context: context)
                device.deviceId = peer.displayName
                print("📱 Добавляем новое устройство: \(peer.displayName)")
            }
            
            // Обновляем только если есть новые данные
            if let deviceName = deviceName {
                device.deviceName = deviceName
            } else {
                device.deviceName = peer.displayName
            }
            device.lastConnected = Date()
            
            if let avatar = avatar {
                device.avatarData = avatar.jpegData(compressionQuality: 0.8)
            }
            
            try context.save()
            loadDeviceHistory()
            print("✅ История устройств обновлена")
        } catch {
            print("❌ Ошибка обновления истории устройств: \(error)")
        }
    }
    
    func deleteDeviceHistory(_ device: DeviceHistoryEntity) {
        context.delete(device)
        do {
            try context.save()
            loadDeviceHistory()
            print("✅ Устройство удалено из истории")
        } catch {
            print("❌ Ошибка удаления устройства из истории: \(error)")
        }
    }
    
    func reloadHistory() {
        print("🔄 [DeviceHistoryService] Принудительная перезагрузка истории устройств")
        loadDeviceHistory()
    }
} 
