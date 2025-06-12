//
//  CAFetcher.swift
//  ContextBackendModels
//
//  Created by Kai Shao on 2025/6/4.
//

import Foundation
import ErrorKit
import SharingGRDB
import Combine

// MARK: - Cache Update Event Definition

/// Structure representing a cache update event that can be published to notify subscribers.
struct CACacheUpdateEvent {
    /// Types of cache update events
    enum Kind {
        /// Indicates items should be reloaded after new data was inserted
        case reloadAfterInsertion
    }
    
    /// The view identifier associated with this event
    let viewId: String
    
    /// The type name of the item that was updated
    let itemTypeName: String
    
    /// The kind of update event
    let kind: Kind
}

/// Global subject for broadcasting cache update events throughout the app
@MainActor
let caCacheUpdatedSubject = PassthroughSubject<CACacheUpdateEvent, Never>()

// MARK: - CAFetcher Class

/// A generic fetcher class that manages loading, caching, and retrieving items
/// of type `Item` which conforms to the `CAItem` protocol.
///
/// This class provides functionality for initial loading, pagination, and database caching.
@Observable
@MainActor
public class CAFetcher<Item: CAItem> {
    // MARK: - Type Aliases
    
    typealias PageInfo = Item.PageInfo
    public typealias Params = Item.Params
    
    // MARK: - Fetch State Management
    
    /// Represents the current state of the fetcher
    enum State: Int {
        case initializing  // Initial state before any fetch operations
        case loadingFirst  // Loading first batch of data
        case idle          // Ready for next fetch operation
        case loading       // Currently fetching data
    }
    
    /// Current state of the fetcher
    var state = State.initializing
    
    /// Indicates whether initial data has been fetched
    public var initialFetched: Bool {
        state.rawValue >= State.idle.rawValue
    }
    
    // MARK: - Fetch Parameters & Configuration
    
    /// Parameters used for fetching items
    var params: Params
    
    /// Information about pagination for fetched items
    var pageInfo: PageInfo?
    
    /// Optional filter to apply to items
    var itemFilter: ((Item) -> Bool)?
    
    /// Determines the fetch strategy (fetch one item or fetch multiple items)
    @ObservationIgnored
    let fetchType: CAFetchType
    
    /// view identifier
    var viewId: String? {
        switch fetchType {
        case .fetchOne: nil
        case .fetchAll(let viewId, _): viewId
        }
    }
    
    var isFetchOne: Bool {
        switch fetchType {
        case .fetchOne: true
        case .fetchAll: false
        }
    }
    
    // MARK: - Dependencies & Resources
    
    /// Database access
    @ObservationIgnored
    @Dependency(\.defaultDatabase) var database
    
    /// Logger for error reporting
    @ObservationIgnored
    @Dependency(\.caLogger) var logger
    
    /// Set of cancellables for managing subscriptions
    @ObservationIgnored
    var cancellables = Set<AnyCancellable>()
    
    // MARK: - Item Storage & Access
    
    /// Items fetched from the database or network
    @ObservationIgnored
    @Fetch(ItemRequest<Item>()) var fetchedItems = []
    
    /// Filtered items excluding deleted ones and applying custom filter
    public var items: [Item] {
        fetchedItems.filter {
            $0.caState != .deleting &&
            itemFilter?($0) != false
        }
    }
    
    /// First item or a default initialized one if none exists
    public var item: Item {
        fetchedItems.first ?? .init()
    }
    
    /// Optional first item, nil if no items exist
    public var optionalItem: Item? {
        fetchedItems.first
    }
    
    // MARK: - Pagination Support
    
    /// Indicates whether more pages are available for fetching
    public var hasNext: Bool {
        pageInfo?.hasNext == true
    }
    
    // MARK: - Publishers
    
    /// Publisher for the first item
    public var itemPublisher: AnyPublisher<Item, Never> {
        $fetchedItems
            .publisher
            .compactMap { $0.first }
            .eraseToAnyPublisher()
    }
    
    /// Publisher for all items
    public var itemsPublisher: AnyPublisher<[Item], Never> {
        $fetchedItems
            .publisher
            .eraseToAnyPublisher()
    }
    
    /// AsyncSequence version of itemPublisher
    public var asyncItem: AsyncPublisher<some Publisher<Item, Never>> {
        itemPublisher.values
    }
    
    /// AsyncSequence version of itemsPublisher
    public var asyncItems: AsyncPublisher<some Publisher<Array<Item>, Never>> {
        itemsPublisher.values
    }
    
    // MARK: - Initialization & Lifecycle
    
    /// Initialize a new CAFetcher with specified parameters
    /// - Parameters:
    ///   - fetchType: Strategy for fetching (one or multiple items)
    ///   - itemType: The type of item to fetch
    ///   - params: Parameters for fetching
    ///   - itemFilter: Optional filter to apply to fetched items
    public init(
        _ fetchType: CAFetchType,
        itemType: Item.Type,
        params: Params,
        itemFilter: ((Item) -> Bool)? = nil,
    ) {
        self.fetchType = fetchType
        self.params = params
        self.itemFilter = itemFilter
        
        // Subscribe to cache update events for this item type
        // ⚠️ FIXME: This might cause a self retain cycle - consider alternative approaches
        caCacheUpdatedSubject
            .filter { $0.itemTypeName == Item.typeName }
            .sink { [weak self] event in
                self?.handleEvent(event)
            }
            .store(in: &cancellables)
    }
    
    deinit {
        print("deinit CAFetcher for \(Item.typeName)")
    }
    
    // MARK: - Public API
    
    /// Fetches a single item without using the cache
    /// - Returns: The fetched item or nil if none exists
    public func loadItemWithoutCache() async throws -> Item? {
        try await loadItemsWithoutCache().first
    }
    
    /// Fetches items without using the cache
    /// - Returns: Array of fetched items
    public func loadItemsWithoutCache() async throws -> [Item] {
        try await Item.fetch(params: params).items
    }
    
    /// Set up the fetcher and perform initial load
    public func setup() async throws(CAFetchError) {
        do {
            try await setupImpl()
        } catch {
            logger.error(ErrorKit.userFriendlyMessage(for: error), [
                "trace": "\(ErrorKit.errorChainDescription(for: error))"
            ])
        }
    }
    
    /// Reload all items
    public func reload() async throws(CAFetchError) {
        do {
            try await load(reset: true)
        } catch {
            logger.error(error)
            throw error
        }
    }
    
    /// Load the next page if available
    public func loadNextIfAny() async throws(CAFetchError) {
        do {
            try await loadNextIfAnyImpl()
        } catch {
            logger.error(error)
            throw error
        }
    }
}

// MARK: - Private Implementation

private extension CAFetcher {
    /// Implementation of the setup process
    private func setupImpl() async throws(CAFetchError) {
        guard state == .initializing else {
            return
        }
        
        state = .loadingFirst
        
        try await loadRequest(all: false)
        
        // Set to idle state regardless of whether items were loaded
        state = .idle
        
        try await load(reset: true)
        
        if !isFetchOne {
            try await loadRequest(all: true)
        }
    }
    
    /// Implementation of loading next page
    private func loadNextIfAnyImpl() async throws(CAFetchError) {
        guard hasNext else {
            assertionFailure("loadNextIfAny should not be called when there is no next page")
            throw .noMoreNextPage
        }
        
        try await load(reset: false)
    }
    
    /// Core loading function that handles both initial loads and pagination
    /// - Parameter reset: Whether to reset pagination information
    private func load(reset: Bool) async throws(CAFetchError) {
        guard reset || hasNext else {
            return
        }
        
        // Prevent concurrent load operations
        guard state == .idle else {
            throw CAFetchError.lastPageIsLoading
        }
        
        state = .loading
        
        if reset {
            pageInfo = nil
            params = params.setEndCursor(nil)
        }
        
        do {
            switch fetchType {
            case .fetchAll(_, let allPages):
                try await fetch(allPages: allPages)
            case .fetchOne:
                try await fetch()
            }
            
            state = .idle
        } catch {
            state = .idle
            throw error
        }
    }
    
    /// Fetch items and update the database
    /// - Parameters:
    ///   - viewId: Optional view identifier for mapping
    ///   - allPages: Whether to fetch all pages
    private func fetch(allPages: Bool = false) async throws(CAFetchError) {
        let isFirstFetch = pageInfo == nil
        let viewId = viewId
         
        // Fetch items from the network
        let newItems = try await CAFetchError.catch { @Sendable in
            try await fetchItems(fetchAllPages: allPages)
        }
        
        // Determine the final set of items based on fetch type and existing items
        let finalItems: [Item] = if isFirstFetch {
            newItems
        } else if isFetchOne && !newItems.isEmpty {
            newItems
        } else if isFetchOne {
            fetchedItems
        } else {
            fetchedItems + newItems
        }
        
        if isFetchOne {
            assert(finalItems.count <= 1)
        }
        
        // Update the database with the fetched items
        try await CAFetchError.catch { @Sendable in
            try await database.write { db in
                // Delete existing mappings if a view ID is provided
                if let viewId {
                    try db.deleteItemMapsForView(viewId, itemTypeName: Item.typeName)
                }
                
                let items = finalItems.map { $0.toCacheItem(state: .normal) }
                
                // Check for duplicates to avoid database conflicts
                assert(
                    items.count == Set(items.map(\.id)).count,
                    "There are duplicate items in the fetched items",
                )
                
                // Insert or replace items
                try StoredCacheItem
                    .insert(or: .replace, items)
                    .execute(db)
                
                // Create mappings if a view ID is provided
                if let viewId {
                    let maps = finalItems.enumerated().map { index, item in
                        StoredCacheItemMap(view_id: viewId, item_id: item.idString, order: Double(index))
                    }
                    
                    try StoredCacheItemMap
                        .insert(or: .replace, maps)
                        .execute(db)
                }
            }
        }
    }
    
    /// Load items from the database
    /// - Parameter all: Whether to load all items or just the first page
    private func loadRequest(all: Bool) async throws(CAFetchError) {
        try await CAFetchError.catch { @Sendable in
            try await $fetchedItems.load(
                ItemRequest(
                    fetchType: fetchType,
                    loadingAll: all,
                ),
                animation: .default,
            )
        }
    }
    
    /// Fetch items from the network with pagination support
    /// - Parameter fetchAll: Whether to fetch all pages
    /// - Returns: Array of fetched items
    private func fetchItems(fetchAllPages: Bool) async throws -> [Item] {
        var finalItems: [Item] = []
        var fetched = false
        var maxPage = CAFetchError.maxPageCount
        
        // Fetch items page by page
        while (hasNext && fetchAllPages) || !fetched {
            fetched = true
            
            let result = try await Item.fetch(params: params)
            
            finalItems.append(contentsOf: result.items)
            
            pageInfo = result.pageInfo
            params = params.setEndCursor(pageInfo?.endCursor)
            
            maxPage -= 1
            
            // Safety mechanism to prevent infinite loops
            if maxPage == 0 {
                throw CAFetchError.maxPageReached
            }
        }
        
        // Check for duplicates
        assert(
            finalItems.count == Set(finalItems.map(\.idString)).count,
            "There are duplicate items in the fetched items",
        )
        
        return finalItems
    }
    
    /// Handle cache update events
    /// - Parameter event: The event to handle
    func handleEvent(_ event: CACacheUpdateEvent) {
        switch event.kind {
        case .reloadAfterInsertion:
            Task {
                try await load(reset: true)
            }
        }
    }
}

// MARK: - Database Extension

private extension Database {
    /// Deletes item maps for a specific view and item type
    /// - Parameters:
    ///  - viewId: The identifier of the view
    ///  - itemTypeName: The type name of the items to delete
    ///  - Throws: An error if the SQL execution fails
    func deleteItemMapsForView(_ viewId: String, itemTypeName: String) throws {
        try execute(sql:
            """
            DELETE FROM "storedCacheItemMaps"
            WHERE "view_id" = '\(viewId)'
              AND "item_id" IN (
                SELECT "id" FROM "storedCacheItems"
                WHERE "type_name" = '\(itemTypeName)'
              );
            """
        )
    }
}
