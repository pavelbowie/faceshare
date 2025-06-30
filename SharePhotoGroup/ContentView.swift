//
//  ContentView.swift
//  SharePhotoGroup
//
//  Created by Pavel Mac on 24/04/25
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @EnvironmentObject var multipeerService: MultipeerService
    @EnvironmentObject var photoStorage: PhotoStorageService
    @StateObject var faceStore = FaceStore()
    
    var body: some View {
        ZStack {
            // Using theme background color
            AppColors.background
                .ignoresSafeArea()
            
            TabView {
                ReceivedPhotosView()
                    .environmentObject(photoStorage)
                    .environmentObject(faceStore)
                    .tabItem {
                                Label("Feed", systemImage: "photo.stack")
                    }
                LibraryView()
                    .environmentObject(photoStorage)
                    .tabItem {
                        Label("Library", systemImage: "photo.on.rectangle.angled")
                    }
                PeopleView()
                    .environmentObject(photoStorage)
                    .tabItem {
                        Label("People", systemImage: "person.2")
                    }
                NavigationStack {
                    JoinEventView()
                }
                .tabItem {
                    Label("Join Event", systemImage: "calendar.badge.plus")
                }
                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
            }
            .accentColor(AppColors.accent) // Using theme accent color
            .onAppear {
                // Set tab bar appearance to match style guide
                let appearance = UITabBarAppearance()
                appearance.configureWithOpaqueBackground()
                appearance.backgroundColor = UIColor(AppColors.cardBackground)
                
                // Set tab bar item appearance
                let itemAppearance = UITabBarItemAppearance()
                itemAppearance.normal.iconColor = UIColor(AppColors.textSecondary)
                itemAppearance.selected.iconColor = UIColor(AppColors.accent)
                
                appearance.stackedLayoutAppearance = itemAppearance
                appearance.inlineLayoutAppearance = itemAppearance
                appearance.compactInlineLayoutAppearance = itemAppearance
                
                UITabBar.appearance().standardAppearance = appearance
                UITabBar.appearance().scrollEdgeAppearance = appearance
            }
        }
    }
}

