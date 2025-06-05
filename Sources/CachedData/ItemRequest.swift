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
        
        let ids = try StoredCacheViewItem.where {
            $0.id == viewId
        }.fetchAll(db).flatMap { $0.item_ids }
        
        let items = try StoredCacheItem.where {
            $0.id.in(ids)
        }.fetchAll(db)
        
        return items.compactMap { .init(fromCache: $0) }
    }
}
