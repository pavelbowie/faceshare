//
//  ContactService.swift
//  SharePhotoGroup
//
//  Created by Pavel Mac on 21/04/25
//

import Foundation
import Contacts
import UIKit

class ContactService {
    
    static let shared = ContactService()
    private let contactStore = CNContactStore()
    
    private init() {}
    
    func requestAccess() async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            contactStore.requestAccess(for: .contacts) { granted, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }
    
    func fetchUserContact() async throws -> CNContact? {
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactImageDataKey as CNKeyDescriptor,
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactTypeKey as CNKeyDescriptor
        ]
        
        // Сначала пытаемся найти контакт "Me"
        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        request.predicate = nil
        
        var meContact: CNContact?
        try contactStore.enumerateContacts(with: request) { contact, stop in
            // Проверяем, является ли контакт "Me"
            if contact.contactType == .person && 
               (contact.nickname.lowercased() == "me" || 
                contact.givenName.lowercased() == "me" ||
                contact.identifier == "me") {
                meContact = contact
                stop.pointee = true
            }
        }
        
        return meContact
    }
    
    func fetchContact(byIdentifier identifier: String) async throws -> CNContact? {
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactImageDataKey as CNKeyDescriptor,
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor
        ]
        
        return try contactStore.unifiedContact(withIdentifier: identifier, keysToFetch: keysToFetch)
    }
    
    func fetchAllContactsWithPhotos() async throws -> [CNContact] {
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactImageDataKey as CNKeyDescriptor,
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor
        ]
        
        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        request.predicate = nil
        
        var contacts: [CNContact] = []
        try contactStore.enumerateContacts(with: request) { contact, stop in
            if contact.imageData != nil {
                contacts.append(contact)
            }
        }
        
        return contacts
    }
    
    func getContactImage(from contact: CNContact) -> UIImage? {
        guard let imageData = contact.imageData else { return nil }
        return UIImage(data: imageData)
    }
    
    func getContactName(from contact: CNContact) -> String {
        if !contact.nickname.isEmpty {
            return contact.nickname
        }
        let givenName = contact.givenName
        let familyName = contact.familyName
        if !givenName.isEmpty && !familyName.isEmpty {
            return "\(givenName) \(familyName)"
        }
        return givenName.isEmpty ? familyName : givenName
    }
} 
