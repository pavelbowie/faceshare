//
//  PeopleCardView.swift
//  SharePhotoGroup
//
//  Created by Pavel Mac on 22/04/25
//

import SwiftUI

struct PeopleCardView: View {
    
    let group: (name: String?, photos: [ReceivedPhotoModel])
    let onTap: () -> Void
    var body: some View {
      
            VStack {
                if let firstPhoto = group.photos.first, let image = firstPhoto.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color(.systemGray5))
                        .frame(width: 100, height: 100)
                }
                VStack(alignment: .center) {
                    Text(group.name ?? "Unknown")
                        .font(.headline)
                    Text("\(group.photos.count) photos")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding()
            .overlay(
                RoundedRectangle(cornerRadius: AppSpacing.cardCornerRadius)
                    .stroke(AppColors.border, lineWidth: 1)
            )
            .contentShape(Rectangle())

      }
}
 
