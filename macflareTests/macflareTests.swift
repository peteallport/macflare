//
//  macflareTests.swift
//  macflareTests
//
//  Created by Peter C. Allport on 6/24/25.
//

import Foundation
import SwiftData
import Testing
@testable import macflare

@MainActor
struct ItemPersistenceTests {
    @Test("Saved items can be fetched, updated, and deleted in independent contexts")
    func savedItemLifecycle() throws {
        let configuration = ModelConfiguration(
            "ItemTests-\(UUID().uuidString)",
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: Item.self, configurations: configuration)
        let originalTimestamp = Date(timeIntervalSince1970: 1_750_723_200)
        let updatedTimestamp = originalTimestamp.addingTimeInterval(3_600)

        let insertionContext = ModelContext(container)
        insertionContext.autosaveEnabled = false
        insertionContext.insert(Item(timestamp: originalTimestamp))
        try insertionContext.save()

        // Fetch in a fresh context so the assertion checks saved data, not the inserted instance.
        let updateContext = ModelContext(container)
        updateContext.autosaveEnabled = false
        let insertedItems = try updateContext.fetch(FetchDescriptor<Item>())
        try #require(insertedItems.count == 1)
        let insertedItem = try #require(insertedItems.first)
        #expect(insertedItem.timestamp == originalTimestamp)

        insertedItem.timestamp = updatedTimestamp
        try updateContext.save()

        let deletionContext = ModelContext(container)
        deletionContext.autosaveEnabled = false
        let updatedItems = try deletionContext.fetch(FetchDescriptor<Item>())
        try #require(updatedItems.count == 1)
        let updatedItem = try #require(updatedItems.first)
        #expect(updatedItem.timestamp == updatedTimestamp)
        #expect(updatedItem.persistentModelID == insertedItem.persistentModelID)

        deletionContext.delete(updatedItem)
        try deletionContext.save()

        let verificationContext = ModelContext(container)
        #expect(try verificationContext.fetchCount(FetchDescriptor<Item>()) == 0)
    }
}
