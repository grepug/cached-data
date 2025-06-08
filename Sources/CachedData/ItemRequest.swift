//
//  ItemRequest.swift
//  cached-data
//
//  Created by Kai Shao on 2025/6/5.
//

import SharingGRDB

struct ItemRequest<Item: CAItem>: FetchKeyRequest {
    var viewId: String?
    
    public typealias Value = [Item]
    
    public func fetch(_ db: Database) throws -> Value {
        guard let viewId else {
            return []
        }
        
        let items = try StoredCacheItem
            .join(StoredCacheItemMap.all) { $0.id.eq($1.item_id) }
            .where { a, _ in a.type_name == Item.typeName }
            .where { $1.view_id == viewId }
            .order { $1.order }
            .fetchAll(db)
     
        return items.map { item, map in
                .init(fromCacheJSONString: item.json_string, state: item.caState)
        }
    }
}
