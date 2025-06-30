//
//  AppCoordinator.swift
//  SharePhotoGroup
//
//  Created by Pavel Mac on 19/04/25
//

import SwiftUI

class AppCoordinator: ObservableObject {
    @Published var currentView: AnyView
    
    init() {
        // Начальный экран - HomeView
        self.currentView = AnyView(HomeView())
    }
    
    func showHome() {
        currentView = AnyView(HomeView())
    }
    
    func showMyFaces() {
        currentView = AnyView(MyFacesView())
    }
    
    func showReceivedPhotos() {
        currentView = AnyView(ReceivedPhotosView())
    }
    
    func showSettings() {
        currentView = AnyView(SettingsView())
    }
} 
