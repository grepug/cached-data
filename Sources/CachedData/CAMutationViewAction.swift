//
//  CAMutationViewAction.swift
//  cached-data
//
//  Created by Kai Shao on 2025/6/10.
//

import Foundation
import SharingGRDB

public protocol CAMutationViewAction: Sendable {
    associatedtype Kind: Sendable, Hashable
    associatedtype Cache: Sendable = ()
    
    var viewId: String? { get }
    var kind: Kind { get }
    
    func cacheBeforeMutation(item: any CAMutableItem, cache: inout Cache) async throws
    func cacheAfterMutation(item: any CAMutableItem) async throws
    func cacheRollback(item: any CAMutableItem, cache: inout Cache) async throws
}

public struct CAInsertViewAction: CAMutationViewAction {
    public enum Kind: Sendable, Hashable {
        case prepend
        case append
        case insertBefore(id: String)
        case insertAfter(id: String)
        case noAction
    }
    
    public let viewId: String?
    public let kind: Kind
    
    public struct Cache: Sendable {}
    
    @Dependency(\.caLogger) var logger
    @Dependency(\.defaultDatabase) var db
    
    init(_ kind: Kind, viewId: String?) {
        self.viewId = viewId
        self.kind = kind
    }
    
    public static func action(_ kind: Kind, viewId: String? = nil) -> Self {
        self.init(kind, viewId: viewId)
    }
    
    public static var noAction: CAInsertViewAction {
        self.init(.noAction, viewId: "")
    }

    public func cacheBeforeMutation(item: any CAMutableItem, cache: inout Cache) async throws {
        try await db.write { db in
            try handleBeforeInsertion(db: db, item: item)
        }
    }
    
    public func cacheAfterMutation(item: any CAMutableItem) async throws {
        try await db.write { db in
            try handleAfterInsertion(db: db, item: item)
        }
    }
    
    public func cacheRollback(item: any CAMutableItem, cache: inout Cache) async throws {
        try await db.write { db in
            try handleRollbackInsertion(db: db, item: item)
        }
    }
}

public struct CAUpdateViewAction: CAMutationViewAction {
    public enum Kind: Sendable, Hashable {
        case deleteCacheForView
        case refresh
    }
    
    public struct Cache: Sendable {
        var oldItem: StoredCacheItem?
    }
    
    
    public let viewId: String?
    public let kind: Kind
    
    @Dependency(\.caLogger) var logger
    @Dependency(\.defaultDatabase) var db
    
    init(_ kind: Kind, viewId: String?) {
        self.viewId = viewId
        self.kind = kind
    }
    
    public static func action(_ kind: Kind, viewId: String? = nil) -> Self {
        self.init(kind, viewId: viewId)
    }
    
    public func cacheBeforeMutation(item: any CAMutableItem, cache: inout Cache) async throws {
        let oldItem = try await db.write { db in
            let oldItem = try StoredCacheItem
                .where { $0.id == item.idString }
                .fetchOne(db)
            
            try handleBeforeUpdating(db: db, item: item)
            
            return oldItem
        }
        
        cache.oldItem = oldItem
    }
    
    public func cacheAfterMutation(item: any CAMutableItem) async throws {
        try await db.write { db in
            try handleAfterUpdating(db: db, item: item)
        }
    }
    
    public func cacheRollback(item: any CAMutableItem, cache: inout Cache) async throws {
        let cache = cache
        
        try await db.write { db in
            try handleRollbackUpdating(db: db, item: item, cache: cache)
        }
    }
}

// MARK: - Inserting Hanlders

private extension CAInsertViewAction {
    func handleBeforeInsertion(db: Database, item: any CAMutableItem) throws {
        let typeName = type(of: item).typeName
        
        try StoredCacheItem
            .insert(or: .fail) { item.toCacheItem(state: .inserting) }
            .execute(db)
        
        switch kind {
        case .prepend, .append:
            logger.info("Handling prepend action")
            
            let offset: Double = kind == .prepend ? -1 : 1
            var order: Double
            
            if kind == .prepend {
                order = try StoredCacheItemMap
                    .where { $0.view_id == viewId }
                    .join(StoredCacheItem.where { $0.type_name == typeName }) { $0.item_id.eq($1.id) }
                    .limit(1)
                    .order(by: \.order)
                    .fetchOne(db)
                    .map { $0.0 }?
                    .order ?? 0
            } else {
                order = try StoredCacheItemMap
                    .where { $0.view_id == viewId }
                    .join(StoredCacheItem.where { $0.type_name == typeName }) { $0.item_id.eq($1.id) }
                    .limit(1)
                    .order { a, _ in a.order.desc() }
                    .fetchOne(db)
                    .map { $0.0 }?
                    .order ?? 0
            }
            
            order += offset
            
            if let viewId {
                let map = StoredCacheItemMap(view_id: viewId, item_id: item.idString, order: order)
                
                try StoredCacheItemMap
                    .insert { map }
                    .execute(db)
                
                logger.info("Inserted map into StoredCacheItemMap table")
            }
        case .noAction:
            break
        default:
            logger.error("Unsupported action kind: \(kind)")
            fatalError("unimplemented!")
        }
        
    }
    
    func handleAfterInsertion(db: Database, item: any CAMutableItem) throws {
        logger.info("Handling after prepend action")
        try changeState(item, state: .normal, db: db)
    }
    
    func handleRollbackInsertion(db: Database, item: any CAMutableItem) throws {
        switch kind {
        case .prepend, .append, .insertAfter, .insertBefore:
            logger.info("Handling rollback for prepend action")
            
            try StoredCacheItem
                .where { $0.id == item.idString }
                .delete()
                .execute(db)
            
            if let viewId {
                try StoredCacheItemMap
                    .where { $0.view_id == viewId && $0.item_id == item.idString }
                    .delete()
                    .execute(db)
                
                logger.info("Deleted cache item and map for view \(viewId)")
            }
        case .noAction:
            break
        }
    }
}

private extension CAUpdateViewAction {
    func handleBeforeUpdating(db: Database, item: any CAMutableItem) throws {
        try StoredCacheItem
            .where { $0.id == item.idString }
            .update {
                $0.state = CAItemState.updating.rawValue
                $0.json_string = item.toCacheItem(state: .updating).json_string
            }
            .execute(db)
    }
    
    func handleAfterUpdating(db: Database, item: any CAMutableItem) throws {
        try changeState(item, state: .normal, db: db)
        
        switch kind {
        case .deleteCacheForView:
            try StoredCacheItemMap
                .where { $0.view_id == viewId && $0.item_id == item.idString }
                .delete()
                .execute(db)
        case .refresh:
            break
        }
    }
    
    func handleRollbackUpdating(db: Database, item: any CAMutableItem, cache: Cache) throws {
        guard let oldItem = cache.oldItem else {
            logger.error("No old item found for rollback")
            assertionFailure()
            return
        }
        
        try changeState(item, state: .normal, db: db)
        
        try StoredCacheItem
            .update(oldItem)
            .execute(db)
    }
}

extension CAMutationViewAction {
    func changeState<Item: CAItem>(_ item: Item, state: CAItemState, db: Database) throws {
        try StoredCacheItem.where {
            $0.id == item.idString
        }
        .update { $0.state = state.rawValue }
        .execute(db)
    }
}
