//
//  CAFetcher.swift
//  ContextBackendModels
//
//  Created by Kai Shao on 2025/6/4.
//

import SwiftUI
import ErrorKit
import SharingGRDB
import Combine

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
    
    public var reloadError: CAFetchError?
    
    /// Current state of the fetcher
    var state = State.initializing
    
    /// Indicates whether initial data has been fetched
    public var initialFetched: Bool {
        state.rawValue >= State.idle.rawValue
    }
    
    // MARK: - Fetch Parameters & Configuration
    
    /// Parameters used for fetching items
    @ObservationIgnored
    var params: Params
    
    /// Information about pagination for fetched items
    @ObservationIgnored
    var pageInfo: PageInfo?
    
    /// Optional filter to apply to items
    @ObservationIgnored
    var itemFilter: ((Item) -> Bool)?
    
    @ObservationIgnored
    let animation: Animation
    
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
    var cancellable: AnyCancellable?
    
    // MARK: - Item Storage & Access
    
    public typealias FetchedValue = CAFetchedValue<Item>
    
    /// Items fetched from the database or network
    @ObservationIgnored
    @Fetch(ItemRequest<Item>()) var fetchedItems = .initial
    
    /// Filtered items excluding deleted ones and applying custom filter
    public var items: [Item] {
        switch fetchedItems {
        case .fetched(let items):
            items.filter {
                $0.caState != .deleting &&
                itemFilter?($0) != false
            }
        case .empty, .initial:
            []
        }
    }
    
    /// First item or a default initialized one if none exists
    public var item: Item {
        items.first ?? .init()
    }
    
    /// Optional first item, nil if no items exist
    public var optionalItem: Item? {
        items.first
    }
    
    // MARK: - Pagination Support
    
    /// Indicates whether more pages are available for fetching
    public var hasNext: Bool {
        pageInfo?.hasNext == true
    }
    
    // MARK: - Publishers
    
    /// Publisher for fetched values, providing a wrapper around items
    public var fetchedValuePublisher: AnyPublisher<FetchedValue, Never> {
        $fetchedItems
            .publisher
            .eraseToAnyPublisher()
    }
    
    /// AsyncSequence version of fetchedValuePublisher
    public var asyncFetchedValue: AsyncPublisher<some Publisher<FetchedValue, Never>> {
        fetchedValuePublisher.values
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
        animation: Animation = .spring(duration: 0.3),
        itemFilter: ((Item) -> Bool)? = nil,
    ) {
        self.fetchType = fetchType
        self.params = params
        self.itemFilter = itemFilter
        self.animation = animation
        
        cancellable = caCacheReloadSubject
            .filter { $0.itemTypeName == Item.typeName }
            .sink { [weak self] event in
                self?.handleEvent(event)
            }
    }
    
    deinit {
        print("deinit CAFetcher for \(Item.typeName)")
    }
    
    // MARK: - Public API
    
    /// Set up the fetcher and perform initial load
    public func setup(cacheOnly: Bool = false) async throws(CAFetchError) {
        do {
            try await setupImpl(cacheOnly: cacheOnly)
        } catch {
            logger.error(ErrorKit.userFriendlyMessage(for: error), [
                "trace": "\(ErrorKit.errorChainDescription(for: error))"
            ])
            
            throw error
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
    var hasSetup: Bool {
        state != .initializing
    }
    
    /// Implementation of the setup process
    func setupImpl(cacheOnly: Bool) async throws(CAFetchError) {
        guard !hasSetup else {
            return
        }
        
        state = .loadingFirst
        
        try await loadRequest(all: false)
        
        // Set to idle state regardless of whether items were loaded
        state = .idle
        
        if !cacheOnly {
            try await load(reset: true)
            
            if !isFetchOne {
                try await loadRequest()
            }
        }
    }
    
    /// Implementation of loading next page
    func loadNextIfAnyImpl() async throws(CAFetchError) {
        guard hasNext else {
            assertionFailure("loadNextIfAny should not be called when there is no next page")
            throw .noMoreNextPage
        }
        
        try await load(reset: false)
    }
    
    /// Core loading function that handles both initial loads and pagination
    /// - Parameter reset: Whether to reset pagination information
    func load(reset: Bool) async throws(CAFetchError) {
        assert(hasSetup)
        
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
    func fetch(allPages: Bool = false) async throws(CAFetchError) {
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
            items
        } else {
            items + newItems
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
                    .insert(or: .replace) { items }
                    .execute(db)
                
                // Create mappings if a view ID is provided
                if let viewId {
                    let maps = finalItems.enumerated().map { index, item in
                        StoredCacheItemMap(view_id: viewId, item_id: item.idString, order: Double(index))
                    }
                    
                    try StoredCacheItemMap
                        .insert(or: .replace) { maps }
                        .execute(db)
                }
            }
        }
    }
    
    /// Load items from the database
    /// - Parameter all: Whether to load all items or just the first page
    func loadRequest(all: Bool = true, hasFetchedFromRemote: Bool = false) async throws(CAFetchError) {
        try await CAFetchError.catch { @Sendable in
            try await $fetchedItems.load(
                ItemRequest(
                    fetchType: fetchType,
                    loadingAll: all,
                    hasFetchedFromRemote: hasFetchedFromRemote,
                ),
                animation: animation,
            )
        }
    }
    
    /// Fetch items from the network with pagination support
    /// - Parameter fetchAll: Whether to fetch all pages
    /// - Returns: Array of fetched items
    func fetchItems(fetchAllPages: Bool) async throws -> [Item] {
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
        
        try await loadRequest(hasFetchedFromRemote: true)
        
        return finalItems
    }
    
    /// Handle cache update events
    /// - Parameter event: The event to handle
    func handleEvent(_ event: CACacheReloadEvent) {
        if let currentViewId = viewId {
            if let viewId = event.viewId {
                guard viewId == currentViewId else {
                    return
                }
            }
            
            guard !event.excludingViewIds.contains(currentViewId) else {
                return
            }
        }
        
        Task {
            do {
                try await load(reset: true)
            } catch {
                if let error = error as? CAFetchError {
                    reloadError = error
                } else {
                    logger.error("Failed to reload items: \(error)")
                }
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
