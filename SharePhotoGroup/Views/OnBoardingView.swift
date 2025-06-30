//
//  OnBoardingView.swift
//  SharePhotoGroup
//
//  Created by Pavel Mac on 22/04/25
//

import SwiftUI

struct OnBoardingView: View {
    
    @State private var step: Int = 1
    @State private var name: String = ""
    @State private var selectedImage: UIImage?
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @EnvironmentObject var faceEmbeddingService: FaceEmbeddingService
    @ObservedObject private var userProfile = UserProfile.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @EnvironmentObject var coordinator: AppCoordinator
    @EnvironmentObject var faceLabelingService: FaceLabelingService
    @FocusState private var isFocused: Bool
    @Namespace private var animation // для matchedGeometryEffect (если хочешь плавность перехода)

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            VStack {
                ProgressView(value: Double(step), total: 4)
                    .progressViewStyle(LinearProgressViewStyle(tint: Color.blue.opacity(0.7)))
                    .padding(.top, 16)
                    .padding(.horizontal)
                HStack {
                    Text("Step \(step) of 4")
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                    Spacer()
                    Text("\(step * 25)%")
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                }
                .padding(.horizontal)
                Spacer(minLength: 0)
                content
                Spacer(minLength: 0)
            }
            .padding(.vertical)
//            if isProcessing {
//                Color.black.opacity(0.1).ignoresSafeArea()
//                ProgressView("Processing...")
//                    .progressViewStyle(CircularProgressViewStyle(tint: AppColors.accent))
//                    .scaleEffect(1.5)
//            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $selectedImage)
        }
        .sheet(isPresented: $showCamera) {
            CameraView(image: $selectedImage)
        }
        .onChange(of: selectedImage) { newImage in
            if let image = newImage {
                processImage(image)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 1:
            VStack(spacing: 24) {
                Image(systemName: "camera")
                    .resizable()
                    .frame(width: 30, height: 30)
                    .foregroundColor(Color.blue)
                    .padding(20) // Добавим отступы, чтобы иконка не прилипала к кругу
                    .background(
                        Circle()
                            .fill(Color.blue.opacity(0.3))
                    )
                    .padding(.top, 32)
                Text("Welcome to\nFaceShare")
                    .font(.largeTitle).bold()
                    .multilineTextAlignment(.center)
                Text("Let's set up your profile so others can recognize and share photos with you automatically.")
                    .font(.system(size: 16))
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                HStack{
                    VStack(alignment: .center, spacing: 13) {
                        Text("What's your name?")
                            .font(.system(size: 20))
                            .bold()
                        TextField("Enter your full name", text: $name)
                                .padding()
                                .background(AppColors.sectionBackground)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(isFocused ? Color.blue : Color.clear, lineWidth: 2)
                                )
                                .focused($isFocused)
                                .animation(.easeInOut(duration: 0.2), value: isFocused)
                    }
                    .padding()
                }
                .background(Color.white)
                .cornerRadius(13)
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)

                 

                
                Button(action: { step = 2 }) {
                    HStack {
                        Spacer()
                        Text("Continue")
                            .font(.headline)
                            .foregroundColor(.white)
                        Image(systemName: "arrow.right")
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding()
                    .background(name.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray.opacity(0.3) : Color.blue)
                    .cornerRadius(12)
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
            }
            .padding(.horizontal)
        case 2:
            VStack(spacing: 24) {
                Text("Add Your Photo")
                    .font(.largeTitle).bold()
                    .multilineTextAlignment(.center)
                    .padding(.top, 32)
                Text("Choose how you'd like to add your profile photo. This helps the app recognize you in photos.")
                    .font(.body)
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                VStack(spacing: 16) {
                    Button(action: { showCamera = true }) {
                        HStack {
                            Image(systemName: "camera")
                                .foregroundColor(AppColors.accent)
                                .frame(width: 32, height: 32)
                            VStack(alignment: .leading) {
                                Text("Take a Selfie").font(.headline)
                                Text("Use your camera to take a new photo").font(.subheadline).foregroundColor(AppColors.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(AppColors.textSecondary)
                        }
                        .padding()
                        .background(Color.white)
                        .cornerRadius(13)
                        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                    }
                    Button(action: { showImagePicker = true }) {
                        HStack {
                            Image(systemName: "arrow.up.circle")
                                .foregroundColor(.green)
                                .frame(width: 32, height: 32)
                            VStack(alignment: .leading) {
                                Text("Choose from Library").font(.headline)
                                Text("Select an existing photo").font(.subheadline).foregroundColor(AppColors.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(AppColors.textSecondary)
                        }
                        .padding()
                        .background(Color.white)
                        .cornerRadius(13)
                        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                    }
                }
                
                Button("Back") { step = 1 }
                    .foregroundColor(Color.blue)
                    .padding(.top, 16)
                Spacer()
            }
            .padding(.horizontal)
        case 3:
            VStack(spacing: 24) {
                Text("Take Your Photo")
                    .font(.largeTitle).bold()
                    .multilineTextAlignment(.center)
                    .padding(.top, 32)
                Text("Make sure your face is clearly visible and well-lit for best results.")
                    .font(.body)
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                ZStack {
                    if let image = selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                            .clipped()
                    } else {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(AppColors.cardBackground)
                            .frame(maxWidth: .infinity, maxHeight: 300)
                            .overlay(
                                VStack {
                                    Image(systemName: "camera")
                                        .font(.system(size: 48))
                                        .foregroundColor(AppColors.textSecondary)
                                    Text("Camera viewfinder")
                                        .foregroundColor(AppColors.textSecondary)
                                }
                            )
                    }
                }
                .padding()
                Button(action: {
                    if selectedImage != nil {
                        step = 4
                    } else {
                        showCamera = true
                    }
                }) {
                    Text(selectedImage == nil ? "Capture Photo" : "Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
//                        .background(AppColors.accent)
//                        .cornerRadius(12)
                }
                .background(name.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray.opacity(0.3) : Color.blue)
                .cornerRadius(12)
                .padding()
              
                Button("Back") { step = 2 }
                    .foregroundColor(AppColors.accent)
                Spacer()
            }
        case 4:
            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .frame(width: 80, height: 80)
                    .foregroundColor(.green.opacity(0.3))
                    .padding(.top, 32)
                Text("All Set!")
                    .font(.largeTitle).bold()
                Text("Your profile is ready. You can now start sharing photos automatically with friends and family.")
                    .font(.body)
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                HStack{
                    VStack{
                        if let image = selectedImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipShape(Circle())
                        }
                        Text(name)
                            .font(.title2).bold()
                        Text("Profile created successfully")
                            .foregroundColor(AppColors.textSecondary)
                    }
                     .frame(maxWidth: .infinity)
                     .padding()

                }
                .background(Color.white)
                .cornerRadius(13)
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                 
                
                VStack(alignment: .center, spacing: 10) {
                    Text("What happens next?")
                        .font(.headline)
                        .bold()
                        .foregroundColor(Color.blue.opacity(0.7))

                    Text("• The app will scan your photos for faces\n• When you're near friends, it will automatically detect matches\n• Photos will be shared instantly and privately")
                        .font(.subheadline)
                        .foregroundColor(Color.blue.opacity(0.7))
                }
                .padding()
                 .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
 
                Button(action: finishOnboarding) {
                    Text("Start Using FaceShare")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .foregroundColor(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                Spacer()
            }
        default:
            EmptyView()
        }
    }

    private func processImage(_ image: UIImage) {
        isProcessing = true
        errorMessage = nil
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let embedding = try faceEmbeddingService.getEmbedding(for: image)
                DispatchQueue.main.async {
                    self.userProfile.updateProfile(image: image, embedding: embedding, contactId: nil, contactName: self.name)
                    // Добавляем лицо в FaceLabelingService
                    Task {
                        await self.faceLabelingService.addUserProfileFace(image: image, name: self.name)
                    }
                    self.isProcessing = false
                    self.step = 3
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.isProcessing = false
                }
            }
        }
    }

    private func finishOnboarding() {
        hasCompletedOnboarding = true
        coordinator.showHome()
    }
}

#Preview {
    OnBoardingView()
}
