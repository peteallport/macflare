//
//  CloudflareModels.swift
//  macflare
//
//  Created by Peter C. Allport on 6/24/25.
//

import Foundation
import SwiftData
import CloudKit

// MARK: - Authentication Models

@Model
final class CloudflareAccount {
    var id: String
    var email: String
    var name: String
    var organizationName: String?
    var avatarURL: String?
    var isActive: Bool
    var lastSyncDate: Date
    var createdAt: Date
    var updatedAt: Date
    
    // Relationships
    @Relationship(deleteRule: .cascade) var zones: [CloudflareZone] = []
    @Relationship(deleteRule: .cascade) var offlineActions: [OfflineAction] = []
    
    init(id: String, email: String, name: String, organizationName: String? = nil, avatarURL: String? = nil) {
        self.id = id
        self.email = email
        self.name = name
        self.organizationName = organizationName
        self.avatarURL = avatarURL
        self.isActive = true
        self.lastSyncDate = Date()
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

@Model
final class CloudflareZone {
    var id: String
    var name: String
    var status: String
    var plan: String
    var isActive: Bool
    var developmentMode: Bool
    var lastSyncDate: Date
    var createdAt: Date
    var updatedAt: Date
    
    // Relationship
    var account: CloudflareAccount?
    @Relationship(deleteRule: .cascade) var dnsRecords: [DNSRecord] = []
    
    init(id: String, name: String, status: String, plan: String) {
        self.id = id
        self.name = name
        self.status = status
        self.plan = plan
        self.isActive = true
        self.developmentMode = false
        self.lastSyncDate = Date()
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

@Model
final class DNSRecord {
    var id: String
    var type: String
    var name: String
    var content: String
    var ttl: Int
    var proxied: Bool
    var lastSyncDate: Date
    var createdAt: Date
    var updatedAt: Date
    
    // Relationship
    var zone: CloudflareZone?
    
    init(id: String, type: String, name: String, content: String, ttl: Int, proxied: Bool) {
        self.id = id
        self.type = type
        self.name = name
        self.content = content
        self.ttl = ttl
        self.proxied = proxied
        self.lastSyncDate = Date()
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

@Model
final class OfflineAction {
    var id: String
    var type: String // "create", "update", "delete"
    var resource: String // "dns_record", "zone_setting", etc.
    var resourceId: String?
    var payload: Data // JSON data for the action
    var createdAt: Date
    var isCompleted: Bool
    var error: String?
    
    // Relationship
    var account: CloudflareAccount?
    
    init(type: String, resource: String, resourceId: String? = nil, payload: Data) {
        self.id = UUID().uuidString
        self.type = type
        self.resource = resource
        self.resourceId = resourceId
        self.payload = payload
        self.createdAt = Date()
        self.isCompleted = false
    }
}

// MARK: - OAuth Token Models (for Keychain storage)

struct CloudflareOAuthToken: Codable {
    let accessToken: String
    let refreshToken: String?
    let tokenType: String
    let expiresIn: Int
    let scope: String
    let createdAt: Date
    
    var isExpired: Bool {
        let expirationDate = createdAt.addingTimeInterval(TimeInterval(expiresIn))
        return Date() >= expirationDate
    }
    
    var expiresAt: Date {
        return createdAt.addingTimeInterval(TimeInterval(expiresIn))
    }
}

// MARK: - Network State

enum NetworkState {
    case connected
    case disconnected
    case connecting
}

// MARK: - Authentication State

enum AuthenticationState {
    case unauthenticated
    case authenticating
    case authenticated(CloudflareAccount)
    case failed(Error)
}
