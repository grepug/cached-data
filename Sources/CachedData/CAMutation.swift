//
//  DataMutation.swift
//  cached-data
//
//  Created by Kai Shao on 2025/6/6.
//

import SharingGRDB

public protocol CAMutation: Sendable {
    func delete<Item: CAMutableItem>(_ item: Item) async throws
    func update<Item: CAMutableItem>(_ item: Item, viewId: String, action: CAUpdateAction) async throws
    func insert<Item: CAMutableItem>(_ item: Item, viewId: String, action: CAInsertAction) async throws
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

public enum CAUpdateAction: Sendable {
    // when moving the item to another relation,
    // delete the cache for current view
    case deleteCacheForView
}

public enum CAInsertAction: Sendable {
    case prepend
    case append
    case insertBefore(id: String)
    case insertAfter(id: String)
}

@MainActor
public class DataMutation: CAMutation {
    @Dependency(\.defaultDatabase) var db
    @Dependency(\.caLogger) var logger
    
    public func delete<Item: CAMutableItem>(_ item: Item) async throws {
        // first set the item in the cache that is being deleted
        try await changeState(item, state: .deleting)
        
        do {
            // fire the real mutation
            try await item.delete()
            
            // delete for good
            try! await db.write { db in
                try StoredCacheItem.where {
                    $0.id == item.idString
                }
                .delete()
                .execute(db)
            }
        } catch {
            // roll back if deletion fails
            try await changeState(item, state: .normal)
        }
    }
    
    public func update<Item: CAMutableItem>(_ item: Item, viewId: String, action: CAUpdateAction) async throws {
        try await db.write { db in
            try StoredCacheItem.where {
                $0.id == item.idString
            }
            .update(set: { a in
                a.json_string = item.toCacheItem(state: .normal).json_string
            })
            .execute(db)
            
            // used when updating relation
            if case .deleteCacheForView = action {
                try StoredCacheItemMap
                    .where { $0.view_id == viewId }
                    .and(.where { $0.item_id == item.idString })
                .delete()
                .execute(db)
            }
        }
        
        try await item.update()
    }
    
    public func insert<Item: CAMutableItem>(_ item: Item, viewId: String, action: CAInsertAction) async throws {
        try await db.write { db in
            let cacheItem = item.toCacheItem(state: .inserting)
            
            try StoredCacheItem
                .insert(cacheItem)
                .execute(db)
            
            switch action {
            case .prepend:
                let smallestOrder = try StoredCacheItemMap
                    .where { $0.view_id == viewId }
                    .join(StoredCacheItem.where { $0.type_name == Item.typeName }) { $0.item_id.eq($1.id) }
                    .limit(1)
                    .order(by: \.order)
                    .fetchOne(db)
                    .map { $0.0 }?
                    .order ?? 0
                
                let newOrder = smallestOrder - 1
                let map = StoredCacheItemMap(view_id: viewId, item_id: item.idString, order: newOrder)
                
                try StoredCacheItemMap
                    .insert(map)
                    .execute(db)
            default:
                fatalError("unimplemented!")
            }
        }
        
        try await item.insert()
    }
}

extension DataMutation {
    private func changeState<Item: CAItem>(_ item: Item, state: CAItemState) async throws {
        try await db.write { db in
            try StoredCacheItem.where {
                $0.id == item.idString
            }
            .update { $0.state = state.rawValue }
            .execute(db)
        }
    }
}
