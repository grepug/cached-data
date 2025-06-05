//
//  ItemRequest.swift
//  cached-data
//
//  Created by Kai Shao on 2025/6/5.
//

import SharingGRDB

struct ItemRequest<Item: DataFetcherItem>: FetchKeyRequest {
    var viewId: String?
    
    public typealias Value = [Item]
    
    public func fetch(_ db: Database) throws -> Value {
        guard let viewId else {
            return []
        }
        
        return try StoredCacheItem
            .join(StoredCacheItemMap.all) { $0.id.eq($1.item_id) }
            .where { $1.id == viewId }
            .order { $1.order }
            .fetchAll(db)
            .map { $0.0 }
            .map { .init(fromCache: $0) }
    }
}
