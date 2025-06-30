//
//  SceneDelegate.swift
//  SharePhotoGroup
//
//  Created by Pavel Mac on 19/04/25
//

import SwiftUI

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    let appCoordinator = AppCoordinator()
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(
            rootView: ContentView()
                .environmentObject(appCoordinator)
        )
        self.window = window
        window.makeKeyAndVisible()
    }
} 
