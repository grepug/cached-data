//
//  DataMutation.swift
//  cached-data
//
//  Created by Kai Shao on 2025/6/6.
//

import SharingGRDB

public protocol CAMutation: Sendable {
    func delete<Item: CAMutableItem>(_ item: Item) async throws(CAMutationError)
    func insert<Item: CAMutableItem>(_ item: Item, action: CAInsertViewAction) async throws(CAMutationError)
    func update<Item: CAMutableItem>(_ item: Item, action: CAUpdateViewAction) async throws(CAMutationError)
}

private enum MutationKey: DependencyKey {
    static let liveValue: any CAMutation = DataMutation()
}

public extension DependencyValues {
    var caMutation: CAMutation {
        get { self[MutationKey.self] }
        set { self[MutationKey.self] = newValue }
    }
}

public typealias Dep = Dependency

@MainActor
public class DataMutation: CAMutation {
    @Dependency(\.defaultDatabase) var db
    @Dependency(\.caLogger) var logger
    
    public func delete<Item: CAMutableItem>(_ item: Item) async throws(CAMutationError) {
        do {
            try await deleteImpl(item)
        } catch {
            logger.error(error)
            throw error
        }
    }
    
    public func update<Item>(_ item: Item, action: CAUpdateViewAction) async throws(CAMutationError) where Item : CAMutableItem {
        do {
            var cache = CAUpdateViewAction.Cache()
            
            try await action.cacheBeforeMutation(item: item, cache: &cache)

            do {
                try await item.update()
            } catch {
                try await action.cacheRollback(item: item, cache: &cache)
                throw error
            }
            
            try await action.cacheAfterMutation(item: item)
        } catch {
            logger.error(error)
            
            try CAMutationError.catch { @Sendable in
                throw error
            }
        }
    }
    
    public func insert<Item>(_ item: Item, action: CAInsertViewAction) async throws(CAMutationError) where Item : CAMutableItem {
        do {
            var cache: () = CAInsertViewAction.Cache()

            try await action.cacheBeforeMutation(item: item, cache: &cache)

            do {
                try await item.insert()
            } catch {
                try await action.cacheRollback(item: item, cache: &cache)
                throw error
            }
            
            try await action.cacheAfterMutation(item: item)
        } catch {
            logger.error(error)
            
            try CAMutationError.catch { @Sendable in
                throw error
            }
        }
    }
}

// MARK: - Private Implementation
private extension DataMutation {
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
