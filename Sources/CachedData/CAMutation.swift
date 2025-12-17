//
//  DataMutation.swift
//  cached-data
//
//  Created by Kai Shao on 2025/6/6.
//

import SQLiteData

// MARK: - Mutation Handlers

/// Concrete implementation of `CAHandlers` protocol that manages all cache mutation operations.
///
/// This struct is responsible for coordinating CRUD operations on cached items, including:
/// - Fetching items from cache
/// - Inserting new items with optimistic updates
/// - Updating existing items with rollback support
/// - Deleting items with state management
/// - Managing item IDs when server returns different IDs
/// - Triggering cache reload events across views
///
/// All mutation operations follow the same pattern:
/// 1. Update cache with optimistic state (inserting/updating/deleting)
/// 2. Execute the actual server operation
/// 3. Update cache with final state on success, or rollback on failure
struct Handlers: CAHandlers {
    @Dependency(\.defaultDatabase) var db
    @Dependency(\.caLogger) var logger

    // MARK: - Cache Fetching
    
    /// Fetches a single cached item by its ID.
    ///
    /// - Parameters:
    ///   - id: The unique identifier of the item to fetch
    ///   - type: The type of the item to fetch (used for type inference)
    /// - Returns: The cached item if found, nil otherwise
    /// - Throws: Database errors if the query fails
    func fetchCachedItem<Item>(id: String, forType type: Item.Type) async throws -> Item? where Item : CAItem {
        try await db.read { db in
            try StoredCacheItem
                .where { $0.id == id }
                .fetchOne(db)
                .map { .init(fromCacheJSONString: $0.json_string, state: $0.caState) }
        }
    }

    /// Fetches multiple cached items by their IDs, maintaining the order of the input IDs.
    ///
    /// - Parameters:
    ///   - ids: Array of item identifiers to fetch
    ///   - type: The type of items to fetch (used for type inference)
    /// - Returns: Array of cached items in the same order as the input IDs
    /// - Throws: Database errors if the query fails
    func fetchCachedItems<Item>(ids: [String], forType type: Item.Type) async throws -> [Item] where Item : CAItem {
        try await db.read { db in
            try StoredCacheItem
                .where { $0.id.in(ids) }
                .fetchAll(db)
                .map { .init(fromCacheJSONString: $0.json_string, state: $0.caState) }
                .sorted { ids.firstIndex(of: $0.idString) ?? 0 < ids.firstIndex(of: $1.idString) ?? 0 }
        }
    }

    // MARK: - Direct Cache Operations
    
    /// Updates the cache item's JSON content while maintaining its state.
    ///
    /// This is a direct cache operation that doesn't trigger any server calls.
    /// Useful for updating local cache when you already have the updated data.
    ///
    /// - Parameters:
    ///   - item: The item with updated data to save in cache
    ///   - state: The state to assign to the cached item
    /// - Throws: CAMutationError if the database update fails
    func updateCache<Item>(_ item: Item, state: CAItemState) async throws(CAMutationError) where Item : CAItem {
        try await CAMutationError.catch { @Sendable in
            try await db.write { db in
                try StoredCacheItem
                    .where { $0.id == item.idString }
                    .update { $0.json_string = item.toCacheItem(state: state).json_string }
                    .execute(db)
            }
        }
    }

    /// Inserts a new item into the cache and creates a view mapping.
    ///
    /// This is a direct cache operation that doesn't trigger any server calls.
    /// Creates both the cache item entry and the view mapping in a single transaction.
    ///
    /// - Parameters:
    ///   - item: The item to insert into cache
    ///   - state: The state to assign to the cached item
    ///   - viewId: The view identifier to associate this item with
    /// - Throws: CAMutationError if the database insertion fails
    func insertCache<Item>(_ item: Item, state: CAItemState, viewId: String) async throws(CAMutationError) where Item : CAItem {
        try await CAMutationError.catch { @Sendable in
            try await db.write { db in
                try StoredCacheItem
                    .insert { item.toCacheItem(state: state) }
                    .execute(db)

                // Create view mapping with order -1 (will be reordered later)
                try StoredCacheItemMap
                    .insert { 
                        StoredCacheItemMap(
                            view_id: viewId,
                            item_id: item.idString, 
                            order: -1,
                        )
                    }
                    .execute(db)
            }
        }
    }

    // MARK: - Cache Reload Events
    
    /// Broadcasts a cache reload event to all subscribers.
    ///
    /// This triggers fetchers listening to this item type to reload their data from cache.
    /// The event can be scoped to a specific view or broadcast to all views.
    ///
    /// - Parameters:
    ///   - type: The type of items that were updated
    ///   - viewId: Optional view identifier to reload (nil reloads all views)
    ///   - excludingViewIds: Array of view IDs to exclude from the reload
    func reload<Item: CAItem>(_ type: Item.Type, viewId: String?, excludingViewIds: [String]) {
        // Publish a cache reload event to notify subscribers on the main actor
        Task { @MainActor in
            caCacheReloadSubject.send(.init(viewId: viewId, excludingViewIds: excludingViewIds, itemTypeName: Item.typeName))
        }
    }
    
    // MARK: - CRUD Operations
    
    /// Deletes an item with optimistic UI update and rollback on failure.
    ///
    /// Flow:
    /// 1. Sets item state to .deleting in cache (optimistic update)
    /// 2. Calls the item's delete() method to perform server deletion
    /// 3. Removes item from cache on success
    /// 4. Reverts to .normal state on failure (rollback)
    ///
    /// - Parameter item: The item to delete
    /// - Throws: CAMutationError if the deletion fails
    func delete<Item: CAMutableItem>(_ item: Item) async throws(CAMutationError) {
        do {
            try await deleteImpl(item)
        } catch {
            logger.error(error)
            throw error
        }
    }
    
    /// Updates an item with optimistic cache update, server call, and optional ID replacement.
    ///
    /// This method handles the complete update flow with proper error handling:
    /// 1. Captures current cache state for potential rollback
    /// 2. Updates cache with .updating state and new data (optimistic)
    /// 3. Calls the item's update() method to perform server update
    /// 4. Updates item ID in cache if server returns a different ID
    /// 5. Sets item state to .normal on success
    /// 6. Rolls back cache to previous state on failure
    ///
    /// - Parameters:
    ///   - item: The item to update with its modified data
    ///   - action: View action that defines cache behavior and view targeting
    ///   - updatedId: Optional new ID from server (e.g., normalized or canonical ID)
    /// - Throws: CAMutationError if the update fails
    func update<Item>(_ item: Item, action: CAUpdateViewAction, updatedId: String? = nil) async throws(CAMutationError) where Item : CAMutableItem {
        do {
            try await CAMutationError.catch { @Sendable in
                var cache = CAUpdateViewAction.Cache()
                let originalId = item.idString
                
                // Step 1: Prepare cache for mutation (captures old state)
                try await action.cacheBeforeMutation(item: item, cache: &cache)
                
                do {
                    // Step 2: Execute server update
                    try await item.update()
                } catch {
                    // Step 3: Rollback cache if server update fails
                    try await action.cacheRollback(item: item, cache: &cache)
                    throw error
                }
                
                // Step 4: Update item ID in cache if server returned a different one
                if let newId = updatedId, newId != originalId {
                    try await updateItemId(from: originalId, to: newId, typeName: Item.typeName, viewId: action.viewId)
                }
                
                // Step 5: Finalize cache update (sets state to .normal)
                try await action.cacheAfterMutation(item: item)
            }
        } catch {
            logger.error(error)
            throw error
        }
    }
    
    /// Inserts a new item with optimistic cache update and rollback on failure.
    ///
    /// This method handles the complete insertion flow:
    /// 1. Inserts item into cache with .inserting state
    /// 2. Creates view mapping at the specified position
    /// 3. Calls the item's insert() method to perform server insertion
    /// 4. Sets item state to .normal on success
    /// 5. Removes item and mappings from cache on failure (rollback)
    ///
    /// - Parameters:
    ///   - item: The new item to insert
    ///   - action: Insert action that defines position and view targeting
    /// - Throws: CAMutationError if the insertion fails
    func insert<Item>(_ item: Item, action: CAInsertViewAction) async throws(CAMutationError) where Item : CAMutableItem {
        do {
            try await CAMutationError.catch { @Sendable in
                var cache = CAInsertViewAction.Cache()
                
                // Step 1: Insert into cache with .inserting state
                try await action.cacheBeforeMutation(item: item, cache: &cache)
                
                do {
                    // Step 2: Execute server insertion
                    try await item.insert()
                } catch {
                    // Step 3: Remove from cache if server insertion fails
                    try await action.cacheRollback(item: item, cache: &cache)
                    throw error
                }
                
                // Step 4: Finalize cache (sets state to .normal)
                try await action.cacheAfterMutation(item: item)
            }
        } catch {
            logger.error(error)
            throw error
        }
    }
}

// MARK: - Private Implementation

/// Private helper methods for internal mutation operations
private extension Handlers {
    /// Internal implementation of delete with state management and rollback.
    ///
    /// This method encapsulates the deletion logic with proper error handling.
    /// It first marks the item as deleting (for UI feedback), attempts the server
    /// deletion, and either removes the item from cache or reverts its state.
    ///
    /// - Parameter item: The item to delete
    /// - Throws: CAMutationError if any step fails
    func deleteImpl<Item: CAMutableItem>(_ item: Item) async throws(CAMutationError) {
        // Mark item as deleting for UI feedback
        try await changeState(item, state: .deleting)
        
        do {
            // Execute server deletion
            try await item.delete()
            
            // Permanently remove from cache on success
            try await CAMutationError.catch { @Sendable in
                try await db.write { db in
                    try StoredCacheItem.where {
                        $0.id == item.idString
                    }
                    .delete()
                    .execute(db)
                }
            }
        } catch {
            // Revert to normal state if deletion fails
            try await changeState(item, state: .normal)
            throw error
        }
    }
    
    /// Changes the state of a cached item.
    ///
    /// This is a low-level operation used internally to update item states
    /// during mutation operations (e.g., .updating, .inserting, .deleting, .normal).
    ///
    /// - Parameters:
    ///   - item: The item whose state to change
    ///   - state: The new state to set
    /// - Throws: CAMutationError if the database update fails
    func changeState<Item: CAItem>(_ item: Item, state: CAItemState) async throws(CAMutationError) {
        try await CAMutationError.catch { @Sendable in
            try await db.write { db in
                try StoredCacheItem.where {
                    $0.id == item.idString
                }
                .update { $0.state = state.rawValue }
                .execute(db)
            }
        }
    }
    
    /// Updates an item's ID in both the cache and view mappings.
    ///
    /// This is crucial for handling cases where the server returns a different ID
    /// than the temporary one used by the client (e.g., UUID → server-generated ID,
    /// or normalized canonical ID).
    ///
    /// The update is performed atomically in a single database transaction to ensure
    /// consistency between the cache item and its view mappings.
    ///
    /// - Parameters:
    ///   - oldId: The current ID of the item in the cache
    ///   - newId: The new ID to replace it with (from server response)
    ///   - typeName: The type name of the item (for scoped updates)
    ///   - viewId: Optional view ID to update mappings (nil updates all mappings)
    /// - Throws: CAMutationError if the database update fails
    func updateItemId(from oldId: String, to newId: String, typeName: String, viewId: String?) async throws(CAMutationError) {
        try await CAMutationError.catch { @Sendable in
            try await db.write { db in
                // Update the primary item ID in the cache
                try StoredCacheItem
                    .where { $0.id == oldId && $0.type_name == typeName }
                    .update { $0.id = newId }
                    .execute(db)
                
                // Update all view mappings that reference this item
                if let viewId {
                    try StoredCacheItemMap
                        .where { $0.view_id == viewId && $0.item_id == oldId }
                        .update { $0.item_id = newId }
                        .execute(db)
                }
            }
        }
    }
}
