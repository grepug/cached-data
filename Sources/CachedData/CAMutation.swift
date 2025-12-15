//
//  DataMutation.swift
//  cached-data
//
//  Created by Kai Shao on 2025/6/6.
//

import SQLiteData

struct Handlers: CAHandlers {
    @Dependency(\.defaultDatabase) var db
    @Dependency(\.caLogger) var logger

    func fetchCachedItem<Item>(id: String, forType type: Item.Type) async throws -> Item? where Item : CAItem {
        try await db.read { db in
            try StoredCacheItem
                .where { $0.id == id }
                .fetchOne(db)
                .map { .init(fromCacheJSONString: $0.json_string, state: $0.caState) }
        }
    }

    func fetchCachedItems<Item>(ids: [String], forType type: Item.Type) async throws -> [Item] where Item : CAItem {
        try await db.read { db in
            try StoredCacheItem
                .where { $0.id.in(ids) }
                .fetchAll(db)
                .map { .init(fromCacheJSONString: $0.json_string, state: $0.caState) }
                .sorted { ids.firstIndex(of: $0.idString) ?? 0 < ids.firstIndex(of: $1.idString) ?? 0 }
        }
    }

    /// Updates the cache item for the given item with the specified state.
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

    /// Inserts a new cache item for the given item with the specified state.
    func insertCache<Item>(_ item: Item, state: CAItemState, viewId: String) async throws(CAMutationError) where Item : CAItem {
        try await CAMutationError.catch { @Sendable in
            try await db.write { db in
                try StoredCacheItem
                    .insert { item.toCacheItem(state: state) }
                    .execute(db)

                // Update the view ID for the inserted item
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

    func reload<Item: CAItem>(_ type: Item.Type, viewId: String?, excludingViewIds: [String]) {
        // Publish a cache reload event to notify subscribers
        Task { @MainActor in
            caCacheReloadSubject.send(.init(viewId: viewId, excludingViewIds: excludingViewIds, itemTypeName: Item.typeName))
        }
    }
    
    func delete<Item: CAMutableItem>(_ item: Item) async throws(CAMutationError) {
        do {
            try await deleteImpl(item)
        } catch {
            logger.error(error)
            throw error
        }
    }
    
    func update<Item>(_ item: Item, action: CAUpdateViewAction) async throws(CAMutationError) where Item : CAMutableItem {
        do {
            try await CAMutationError.catch { @Sendable in
                var cache = CAUpdateViewAction.Cache()
                
                try await action.cacheBeforeMutation(item: item, cache: &cache)
                
                do {
                    try await item.update()
                } catch {
                    try await action.cacheRollback(item: item, cache: &cache)
                    throw error
                }
                
                try await action.cacheAfterMutation(item: item)
            }
        } catch {
            logger.error(error)
            throw error
        }
    }
    
    func insert<Item>(_ item: Item, action: CAInsertViewAction) async throws(CAMutationError) where Item : CAMutableItem {
        do {
            try await CAMutationError.catch { @Sendable in
                var cache = CAInsertViewAction.Cache()
                
                try await action.cacheBeforeMutation(item: item, cache: &cache)
                
                do {
                    try await item.insert()
                } catch {
                    try await action.cacheRollback(item: item, cache: &cache)
                    throw error
                }
                
                try await action.cacheAfterMutation(item: item)
            }
        } catch {
            logger.error(error)
            throw error
        }
    }
}

// MARK: - Private Implementation
private extension Handlers {
    func deleteImpl<Item: CAMutableItem>(_ item: Item) async throws(CAMutationError) {
        // first set the item in the cache that is being deleted
        try await changeState(item, state: .deleting)
        
        do {
            // fire the real mutation
            try await item.delete()
            
            // delete for good
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
            // roll back if deletion fails
            try await changeState(item, state: .normal)
            throw error
        }
    }
    
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
}
