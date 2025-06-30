//
//  HomeView.swift
//  SharePhotoGroup
//
//  Created by Pavel Mac on 21/04/25
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var multipeerService: MultipeerService
    
    var body: some View {
        ZStack {
            AppColors.background
                .ignoresSafeArea(.all)
            
            NavigationStack {
                ScrollView {
                    VStack(spacing: AppSpacing.grid3x) {
                        // Top spacing for visual balance
                        Spacer().frame(height: AppSpacing.grid3x)
                        
                        // Scan Photo Button
                        NavigationLink(destination: PhotoScanView()) {
                            HomeButton(
                                title: "Scan Photo",
                                systemImage: "photo.on.rectangle.angled",
                                description: "Take or select photos to share"
                            )
                        }
                        
                        // Join Event Button
                        NavigationLink(destination: JoinEventView()) {
                            HomeButton(
                                title: "Join Event",
                                systemImage: "person.2.fill",
                                description: "Connect with friends at events"
                            )
                        }
                        
                        // View Received Photos Button
                        NavigationLink(destination: ReceivedPhotosView()) {
                            HomeButton(
                                title: "View Received Photos",
                                systemImage: "photo.stack.fill",
                                description: "See photos shared with you"
                            )
                        }
                    }
                    .padding(.horizontal, AppSpacing.horizontalPadding)
                    .padding(.vertical, AppSpacing.grid3x)
                }
                .navigationTitle("Feed")
                .navigationBarTitleDisplayMode(.large)
            }
        }
    }
}

// Home Button Component
struct HomeButton: View {
    let title: String
    let systemImage: String
    let description: String
    
    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.grid3x) {
            // Icon
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(AppColors.primary)
                .frame(width: 44, height: 44)
                .background(AppColors.primary.opacity(0.1))
                .cornerRadius(AppSpacing.buttonCornerRadius)
            
            // Text content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTypography.sectionTitle)
                    .foregroundColor(AppColors.textPrimary)
                
                Text(description)
                    .font(AppTypography.subtext)
                    .foregroundColor(AppColors.textSecondary)
            }
            .multilineTextAlignment(.leading)
            
            Spacer()
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(AppSpacing.grid3x)
        .background(AppColors.cardBackground)
        .cornerRadius(AppSpacing.cardCornerRadius)
        .shadow(AppShadows.small)
    }
}

//#Preview {
//    HomeView()
//        .environmentObject(MultipeerService())
//}
