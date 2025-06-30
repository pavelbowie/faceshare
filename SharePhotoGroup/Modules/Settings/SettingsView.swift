//
//  SettingsView.swift
//  SharePhotoGroup
//
//  Created by Pavel Mac on 21/04/25
//

import SwiftUI
import Contacts
import UIKit
import Photos
import PhotosUI
import MultipeerConnectivity

struct SettingsView: View {
    @StateObject private var userProfile = UserProfile.shared
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var contacts: [CNContact] = []
    @State private var showContactPicker = false
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var selectedImage: UIImage?
    @State private var showPhotoSourceMenu = false
    @State private var showDeviceList = false
    
    @EnvironmentObject var photoStorage: PhotoStorageService
    @EnvironmentObject var faceEmbeddingService: FaceEmbeddingService
    @EnvironmentObject var faceLabelingService: FaceLabelingService
    @StateObject private var photoLibraryService = PhotoLibraryService()
    @State private var showingScanAlert = false
    
    // UI-only toggles
    @State private var autoSharePhotos = false
    @State private var faceDetection = true
    @State private var photoShares = true
    @State private var eventInvites = true
    @State private var comments = false
    // Dummy storage values
    @State private var faceDataSize: Double = 45.2
    @State private var sharedPhotosSize: Double = 1.2
    
    var body: some View {
        ZStack {
            AppColors.cardBackground.ignoresSafeArea()
            ScrollView {
                HStack{
                    Text("Settings")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(AppColors.textPrimary)
                        .padding(.top, 16)
                        .padding(.leading, 20)
                    Spacer()
                }
                Divider()
                    .frame(height: 1)
                    .background(AppColors.border)

                VStack(alignment: .leading, spacing: AppSpacing.sectionGap) {
                    ProfileHeader(userProfile: userProfile)
                    AccountSection()
                    PrivacySection(autoSharePhotos: $autoSharePhotos, faceDetection: $faceDetection)
                    NotificationsSection(photoShares: $photoShares, eventInvites: $eventInvites, comments: $comments)
                    StorageSection(faceDataSize: $faceDataSize, sharedPhotosSize: $sharedPhotosSize)
                    SupportSection()
                    Spacer(minLength: AppSpacing.grid4x)
                }
                .padding(.top)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showContactPicker) {
            ContactPickerView(contacts: contacts) { selectedContact in
                Task {
                    await loadContactPhoto(selectedContact)
                }
            }
        }
        .onChange(of: autoSharePhotos) { newValue in
            if newValue {
                Task {
                    photoLibraryService.deviceHistoryService.reloadHistory()
                    Task {
                        await startScanning()
                    }
                }
            } else {
                photoLibraryService.stopScanning()
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $selectedImage)
        }
        .sheet(isPresented: $showCamera) {
            CameraView(image: $selectedImage)
        }
        .sheet(isPresented: $showDeviceList) {
            DeviceListView()
        }
 
        .onChange(of: selectedImage) { newImage in
            if let image = newImage {
                Task {
                    await processSelectedImage(image)
                }
            }
        }
    }
    
    private func processSelectedImage(_ image: UIImage) async {
        do {
            let embedding = try faceEmbeddingService.getEmbedding(for: image)
            userProfile.updateProfile(
                image: image,
                embedding: embedding,
                contactId: userProfile.contactIdentifier,
                contactName: userProfile.contactName
            )
            // Добавляем лицо в FaceLabelingService
            if let name = userProfile.contactName {
                await faceLabelingService.addUserProfileFace(image: image, name: name)
            }
            errorMessage = nil
        } catch FaceEmbeddingError.invalidImage {
            errorMessage = "Invalid image format"
        } catch FaceEmbeddingError.processingError {
            errorMessage = "Could not process the image"
        } catch {
            errorMessage = "Error generating face embedding: \(error.localizedDescription)"
        }
    }
    
    private func startScanning() async {
        // Запрашиваем разрешение на доступ к фотографиям
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        switch status {
        case .notDetermined:
            // Запрашиваем разрешение
            let granted = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            if granted == .authorized {
                await startPhotoScanning()
            } else {
                errorMessage = "Для сканирования фото необходим доступ к галерее"
            }
            
        case .restricted, .denied:
            errorMessage = "Для сканирования фото необходим доступ к галерее. Пожалуйста, разрешите доступ в настройках приложения."
            
        case .authorized, .limited:
            await startPhotoScanning()
            
        @unknown default:
            errorMessage = "Неизвестная ошибка при запросе доступа к галерее"
        }
    }
    
    private func startPhotoScanning() async {
        photoLibraryService.configure(
            photoStorage: photoStorage,
            faceEmbeddingService: faceEmbeddingService,
            faceLabelingService: faceLabelingService
        )
        photoLibraryService.startScanning()
    }
    
    private func loadContacts() async {
        isLoading = true
        errorMessage = nil
        do {
            let granted = try await ContactService.shared.requestAccess()
            guard granted else {
                errorMessage = "Access to contacts was denied"
                isLoading = false
                return
            }
            if let meContact = try await ContactService.shared.fetchUserContact() {
                await loadContactPhoto(meContact)
            } else {
                contacts = try await ContactService.shared.fetchAllContactsWithPhotos()
                if contacts.isEmpty {
                    errorMessage = "No contacts with photos found"
                } else {
                    showContactPicker = true
                }
            }
        } catch {
            errorMessage = "Error loading contacts: \(error.localizedDescription)"
        }
        isLoading = false
    }
    
    private func loadContactPhoto(_ contact: CNContact) {
        guard let image = ContactService.shared.getContactImage(from: contact) else {
            errorMessage = "No photo found for selected contact"
            return
        }
        do {
            let embedding = try faceEmbeddingService.getEmbedding(for: image)
            let contactName = ContactService.shared.getContactName(from: contact)
            userProfile.updateProfile(
                image: image,
                embedding: embedding,
                contactId: contact.identifier,
                contactName: contactName
            )
            // Добавляем лицо в FaceLabelingService
            Task {
                await faceLabelingService.addUserProfileFace(image: image, name: contactName)
            }
            errorMessage = nil
        } catch FaceEmbeddingError.invalidImage {
            errorMessage = "Invalid image format"
        } catch FaceEmbeddingError.processingError {
            errorMessage = "Could not process the image"
        } catch {
            errorMessage = "Error generating face embedding: \(error.localizedDescription)"
        }
    }
}

struct ContactPickerView: View {
    let contacts: [CNContact]
    let onSelect: (CNContact) -> Void
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            List(contacts, id: \.identifier) { contact in
                Button(action: {
                    onSelect(contact)
                    presentationMode.wrappedValue.dismiss()
                }) {
                    HStack(spacing: AppSpacing.grid2x) {
                        if let image = ContactService.shared.getContactImage(from: contact) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 48, height: 48)
                                .clipShape(Circle())
                                .shadow(AppShadows.small)
                        } else {
                            Image(systemName: "person.crop.circle")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 48, height: 48)
                                .foregroundColor(AppColors.textSecondary)
                        }
                        Text(ContactService.shared.getContactName(from: contact))
                            .font(AppTypography.bodyText)
                            .foregroundColor(AppColors.textPrimary)
                            .padding(.leading, AppSpacing.gridUnit)
                    }
                    .padding(.vertical, AppSpacing.gridUnit)
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Select Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(AppColors.accent)
                }
            }
        }
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.presentationMode.wrappedValue.dismiss()
            
            guard let provider = results.first?.itemProvider else { return }
            
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { image, _ in
                    DispatchQueue.main.async {
                        self.parent.image = image as? UIImage
                    }
                }
            }
        }
    }
}

struct CameraView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView
        
        init(_ parent: CameraView) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

struct DeviceListView: View {
    @EnvironmentObject var multipeerService: MultipeerService
    @StateObject private var deviceHistoryService: DeviceHistoryService
    @Environment(\.presentationMode) var presentationMode
    @State private var selectedTab = 0
    
    init() {
        let context = PersistenceController.shared.container.viewContext
        _deviceHistoryService = StateObject(wrappedValue: DeviceHistoryService(context: context))
    }
    
    var body: some View {
        NavigationView {
            VStack {
                Picker("View", selection: $selectedTab) {
                    Text("Connected").tag(0)
                    Text("History").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                if selectedTab == 0 {
                    List {
                        ForEach(multipeerService.connectedPeers, id: \.self) { peer in
                            DeviceRow(peer: peer, contactInfo: multipeerService.peerToContact[peer])
                        }
                    }
                } else {
                    List {
                        ForEach(deviceHistoryService.deviceHistory, id: \.deviceId) { device in
                            DeviceHistoryRow(device: device)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                deviceHistoryService.deleteDeviceHistory(deviceHistoryService.deviceHistory[index])
                            }
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Devices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(AppColors.accent)
                }
            }
        }
    }
}

struct DeviceHistoryRow: View {
    let device: DeviceHistoryEntity
    
    var body: some View {
        HStack(spacing: AppSpacing.grid2x) {
            if let avatarData = device.avatarData, let avatar = UIImage(data: avatarData) {
                Image(uiImage: avatar)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                    .shadow(AppShadows.small)
            } else {
                Image(systemName: "person.crop.circle")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .foregroundColor(AppColors.textSecondary)
            }
            
            VStack(alignment: .leading, spacing: AppSpacing.gridUnit) {
                Text(device.deviceName ?? device.deviceId ?? "Unknown Device")
                    .font(AppTypography.bodyText)
                    .foregroundColor(AppColors.textPrimary)
                
                if let lastConnected = device.lastConnected {
                    Text("Last connected: \(lastConnected.formatted(.relative(presentation: .named)))")
//                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
        .padding(.vertical, AppSpacing.gridUnit)
    }
}

struct DeviceRow: View {
    let peer: MCPeerID
    let contactInfo: (name: String, avatar: UIImage?)?
    
    var body: some View {
        HStack(spacing: AppSpacing.grid2x) {
            if let avatar = contactInfo?.avatar {
                Image(uiImage: avatar)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                    .shadow(AppShadows.small)
            } else {
                Image(systemName: "person.crop.circle")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .foregroundColor(AppColors.textSecondary)
            }
            
            VStack(alignment: .leading, spacing: AppSpacing.gridUnit) {
                Text(contactInfo?.name ?? peer.displayName)
                    .font(AppTypography.bodyText)
                    .foregroundColor(AppColors.textPrimary)
                
                Text(peer.displayName)
//                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
            .padding(.leading, AppSpacing.gridUnit)
        }
        .padding(.vertical, AppSpacing.gridUnit)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SettingsView()
        }
    }
}

// MARK: - UI Components

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(AppColors.textPrimary)
            .padding(.horizontal, AppSpacing.horizontalPadding)
            .padding(.top, AppSpacing.grid3x)
            .padding(.bottom, AppSpacing.gridUnit)
    }
}

struct SettingsRow: View {
    let title: String
    var titleColor: Color = AppColors.textPrimary
    var body: some View {
        HStack {
            (title != "Account" ? Text(title) : Text(title).bold())
                .font(AppTypography.bodyText)
                .foregroundColor(titleColor)
             Spacer()
            if title != "Account" {
                Image(systemName: "chevron.right")
                    .foregroundColor(AppColors.textSecondary)
                    .font(.system(size: 15, weight: .medium))
            }
        }
        .padding(.horizontal, AppSpacing.horizontalPadding)
        .frame(height: 48)
        .contentShape(Rectangle())
    }
}

struct SettingsToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                (title != "Privacy & Sharing" ? Text(title) : Text(title).bold())
                    .font(AppTypography.bodyText)
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                if title != "Privacy & Sharing" {
                    Toggle("", isOn: $isOn)
                        .labelsHidden()
                }
            }
            if let subtitle = subtitle, title != "Privacy & Sharing"{
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .padding(.horizontal, AppSpacing.horizontalPadding)
        .frame(height: subtitle == nil ? 48 : 56, alignment: .center)
        .contentShape(Rectangle())
    }
}
struct NotificationsToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                (title != "Notifications" ? Text(title) : Text(title).bold())
                    .font(AppTypography.bodyText)
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                if title != "Notifications" {
                    Toggle("", isOn: $isOn)
                        .labelsHidden()
                }
            }
            if let subtitle = subtitle, title != "Notifications"{
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .padding(.horizontal, AppSpacing.horizontalPadding)
        .frame(height: subtitle == nil ? 48 : 56, alignment: .center)
        .contentShape(Rectangle())
    }
}

struct StorageRow: View {
    let title: String
    let value: String
    let progress: Double
    let color: Color
    var body: some View {
        VStack(spacing: 2) {
            HStack {
                (title != "Storage" ? Text(title) : Text(title).bold())
                    .font(AppTypography.bodyText)
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                if title != "Storage" {
                    Text(value)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            if title != "Storage" {
                ProgressView(value: progress)
                    .accentColor(color)
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, AppSpacing.horizontalPadding)
        .padding(.vertical, AppSpacing.gridUnit)
    }
}

struct ProfileHeader: View {
    let userProfile: UserProfile
    @EnvironmentObject var faceLabelingService: FaceLabelingService
    @State private var isEditing = false
    @State private var editedName: String = ""
    @State private var showPhotoSourceMenu = false
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var selectedImage: UIImage?
    @State private var tempProfileImage: UIImage?
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                if !isEditing {
                    if let image = userProfile.profileImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                            .shadow(AppShadows.medium)
                    } else {
                        Image(systemName: "person.crop.circle")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 56, height: 56)
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
  
                VStack(alignment: .center, spacing: 20) {
                    if isEditing {
                        if let image = tempProfileImage ?? userProfile.profileImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .clipShape(Circle())
                                .shadow(AppShadows.medium)
                                .onTapGesture {
                                    showPhotoSourceMenu = true
                                }
                        } else {
                            Image(systemName: "person.crop.circle")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 100, height: 100)
                                .foregroundColor(AppColors.textSecondary)
                                .onTapGesture {
                                    showPhotoSourceMenu = true
                                }
                        }
                        TextField("Enter name", text: $editedName)
                            .padding(14)
                            .background(AppColors.sectionBackground)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                            )
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Color.black.opacity(0.3))

                        Button(action: {
                            showPhotoSourceMenu = true
                        }) {
                            Text("Change Photo")
                                .font(AppTypography.button)
                                .foregroundColor(AppColors.cardBackground)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppSpacing.grid2x)
                                .background(Color.blue.opacity(0.9))
                                .cornerRadius(13)
                        }
                        Button(action: {
                            saveChanges()
                        }) {
                            Text("Save")
                                .font(AppTypography.button)
                                .foregroundColor(AppColors.cardBackground)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppSpacing.grid2x)
                                .background(Color.blue.opacity(0.9))
                                .cornerRadius(13)
                        }
                    } else {
                        Text(userProfile.contactName ?? "John Doe")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(AppColors.textPrimary)
                    }
                }
                
                Spacer()
                
                if !isEditing {
                    Button("Edit") {
                        editedName = userProfile.contactName ?? ""
                        tempProfileImage = userProfile.profileImage
                        isEditing = true
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(AppColors.accent)
                }
            }
            .padding(.vertical, AppSpacing.grid2x)
            .padding(.horizontal, AppSpacing.horizontalPadding)
        }
        .background(AppColors.cardBackground)
        .cornerRadius(AppSpacing.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: AppSpacing.cardCornerRadius)
                .stroke(AppColors.border, lineWidth: 1)
        )
        .padding(.horizontal, AppSpacing.horizontalPadding)
        .confirmationDialog("Choose Photo Source", isPresented: $showPhotoSourceMenu) {
            Button("Camera") {
                showCamera = true
            }
            Button("Photo Library") {
                showImagePicker = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $selectedImage)
        }
        .sheet(isPresented: $showCamera) {
            CameraView(image: $selectedImage)
        }
        .onChange(of: selectedImage) { newImage in
            if let image = newImage {
                tempProfileImage = image
            }
        }
    }
    
    private func saveChanges() {
        if let newImage = tempProfileImage {
            userProfile.updateProfile(
                image: newImage,
                embedding: userProfile.faceEmbedding,
                contactId: userProfile.contactIdentifier,
                contactName: editedName
            )
            // Добавляем лицо в FaceLabelingService
            Task {
                await faceLabelingService.addUserProfileFace(image: newImage, name: editedName)
            }
        } else {
            userProfile.updateProfile(
                image: userProfile.profileImage,
                embedding: userProfile.faceEmbedding,
                contactId: userProfile.contactIdentifier,
                contactName: editedName
            )
            // Добавляем лицо в FaceLabelingService
            if let image = userProfile.profileImage {
                Task {
                    await faceLabelingService.addUserProfileFace(image: image, name: editedName)
                }
            }
        }
        isEditing = false
        tempProfileImage = nil
    }
}
struct SupportSection: View {
    var body: some View {
        VStack(spacing: 0) {
            SettingsRow(title: "Support")
            Divider().background(AppColors.border)
            SettingsRow(title: "Help Center")
            Divider().background(AppColors.border)
            SettingsRow(title: "Privacy Policy")
            Divider().background(AppColors.border)
            SettingsRow(title: "About", titleColor: AppColors.error)
        }
        .background(AppColors.cardBackground)
        .cornerRadius(AppSpacing.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: AppSpacing.cardCornerRadius)
                .stroke(AppColors.border, lineWidth: 1)
        )
        .padding(.horizontal, AppSpacing.horizontalPadding)
    }
}
struct AccountSection: View {
    var body: some View {
        VStack(spacing: 0) {
            SettingsRow(title: "Account")
            Divider().background(Color.gray)
            SettingsRow(title: "Device Management")
            Divider().background(Color.gray)
            SettingsRow(title: "Export Data")
            Divider().background(Color.gray)
            SettingsRow(title: "Sign Out", titleColor: AppColors.error)
        }
        .background(AppColors.cardBackground)
        .cornerRadius(AppSpacing.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: AppSpacing.cardCornerRadius)
                .stroke(AppColors.border, lineWidth: 1)
        )
        .padding(.horizontal, AppSpacing.horizontalPadding)
    }
}

struct PrivacySection: View {
    @Binding var autoSharePhotos: Bool
    @Binding var faceDetection: Bool
    var body: some View {
        VStack(spacing: 0) {
            SettingsToggleRow(title: "Privacy & Sharing", subtitle: "", isOn: $autoSharePhotos)
            Divider().background(AppColors.border)
            SettingsToggleRow(title: "Auto-Share Photos", subtitle: "Share photos automatically when face matches are found", isOn: $autoSharePhotos)
            Divider().background(AppColors.border)
            SettingsToggleRow(title: "Face Detection", subtitle: "Allow app to detect faces in your photos", isOn: $faceDetection)
            Divider().background(AppColors.border)
            SettingsRow(title: "Sharing Permissions")
            Divider().background(AppColors.border)
            SettingsRow(title: "Data Export")
        }
        .background(AppColors.cardBackground)
        .cornerRadius(AppSpacing.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: AppSpacing.cardCornerRadius)
                .stroke(AppColors.border, lineWidth: 1)
        )
        .padding(.horizontal, AppSpacing.horizontalPadding)
    }
}

struct NotificationsSection: View {
    @Binding var photoShares: Bool
    @Binding var eventInvites: Bool
    @Binding var comments: Bool
    var body: some View {
        VStack(spacing: 0) {
            NotificationsToggleRow(title: "Notifications", isOn: $photoShares)
            Divider().background(AppColors.border)
            NotificationsToggleRow(title: "Photo Shares", isOn: $photoShares)
            Divider().background(AppColors.border)
            NotificationsToggleRow(title: "Event Invites", isOn: $eventInvites)
            Divider().background(AppColors.border)
            NotificationsToggleRow(title: "Comments", isOn: $comments)
        }
        .background(AppColors.cardBackground)
        .cornerRadius(AppSpacing.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: AppSpacing.cardCornerRadius)
                .stroke(AppColors.border, lineWidth: 1)
        )
        .padding(.horizontal, AppSpacing.horizontalPadding)
    }
}

struct StorageSection: View {
    @Binding var faceDataSize: Double
    @Binding var sharedPhotosSize: Double
    var body: some View {
        VStack(spacing: 0) {
            StorageRow(title: "Storage", value: String(format: "%.1f MB", faceDataSize), progress: faceDataSize/100, color: .blue)
            StorageRow(title: "Face Data", value: String(format: "%.1f MB", faceDataSize), progress: faceDataSize/100, color: .blue)
            StorageRow(title: "Shared Photos", value: String(format: "%.1f GB", sharedPhotosSize), progress: sharedPhotosSize/2, color: .green)
            Divider().background(AppColors.border)
            SettingsRow(title: "Clear Cache", titleColor: AppColors.error)
        }
        .background(AppColors.cardBackground)
        .cornerRadius(AppSpacing.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: AppSpacing.cardCornerRadius)
                .stroke(AppColors.border, lineWidth: 1)
        )
        .padding(.horizontal, AppSpacing.horizontalPadding)
    }
}
