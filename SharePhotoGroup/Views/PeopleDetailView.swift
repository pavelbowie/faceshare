//
//  PeopleDetailView.swift
//  SharePhotoGroup
//
//  Created by Pavel Mac on 24/04/25
//

import SwiftUI

struct PeopleDetailView: View {
    
    @Environment(\.dismiss) private var dismiss

    let name: String
    let avatar: UIImage?
    let photoCount: Int
    
    // let lastSeen: String? // Формат: "2 hours ago" или nil
    let photos: [ReceivedPhotoModel]
    // TODO: tabs data, actions, etc.

    var body: some View {
        ScrollView {
             HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundColor(.black)
                }
                Spacer()
                Text(name)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: { /* menu */ }) {
                    Image(systemName: "ellipsis")
                        .font(.title2)
                        .rotationEffect(.degrees(90))
                        .foregroundColor(.black)
                }
            }
            .padding()
            Divider()
             VStack(spacing: 12) {
                if let avatar = avatar {
                    Image(uiImage: avatar)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color(.systemGray5))
                        .frame(width: 80, height: 80)
                }
                Text(name)
                    .font(.title2)
                    .fontWeight(.bold)
                HStack(spacing: 6) {
                    Text("\(photoCount) photos")
                        .foregroundColor(.gray)
 
                }
                HStack(spacing: 12) {
                    Button(action: { /* send photos */ }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Send Photos")
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    Button(action: { /* message */ }) {
                        HStack {
                            Image(systemName: "message")
                            Text("Message")
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray6))
                        .foregroundColor(.black)
                        .cornerRadius(12)
                    }
                }
            }
             .frame(maxWidth: .infinity)
             .padding(.vertical)
            .background(Color.white)
            .cornerRadius(24)
            .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
            .padding()
 
            Spacer()
                     LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(photos) { photo in
                            if let image = photo.image {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 120)
                                    .clipped()
                                    .cornerRadius(16)
                            } else {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(.systemGray5))
                                    .frame(width: 120, height: 120)
                                    .overlay(
                                        Image(systemName: "questionmark.square")
                                            .font(.system(size: 32))
                                            .foregroundColor(.gray)
                                    )
                            }
                        }
                    }
                    .padding()
              Spacer()
            // Quick Actions
            VStack(alignment: .leading, spacing: 0) {
                Text("Quick Actions")
                    .font(.headline)
                    .padding(.bottom, 8)
                Button(action: { /* send all photos */ }) {
                    Text("Send all photos to \(name)")
                        .foregroundColor(.black)
                        .padding(.vertical, 8)
                }
                Divider()
                Button(action: { /* create event */ }) {
                    Text("Create event with \(name)")
                        .foregroundColor(.black)
                        .padding(.vertical, 8)
                }
                Divider()
                Button(action: { /* remove from photos */ }) {
                    Text("Remove from photos")
                        .foregroundColor(.red)
                        .padding(.vertical, 8)
                }
            }
            .padding()
            .background(Color.white)
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
            .padding([.horizontal, .bottom])
        }
        .background(Color.white.ignoresSafeArea())
        .navigationBarBackButtonHidden()
    }
}

//#Preview {
//    PeopleDetailView(name: "John Doe", avatar: UIImage(named: "john_doe_avatar"), photoCount: 12, lastSeen: "2 hours ago", photos: [])
//}
