//
//  ItemRequest.swift
//  cached-data
//
//  Created by Kai Shao on 2025/6/5.
//

import SharingGRDB

public enum CAFetchType: Hashable, Sendable {
    case fetchOne(itemId: String)
    case fetchAll(viewId: String, allPages: Bool)
}

struct ItemRequest<Item: CAItem>: FetchKeyRequest {
    var fetchType: CAFetchType?
    var loadingAll = false
    
    public typealias Value = [Item]
    
    public func fetch(_ db: Database) throws -> Value {
        switch fetchType {
        case .fetchOne(let id):
            guard let item = (try StoredCacheItem
                .where { $0.type_name == Item.typeName }
                .where { $0.id == id }
                .fetchOne(db)) else {
                    return []
                }

            return [
                .init(fromCacheJSONString: item.json_string, state: item.caState)
            ]
        case .fetchAll(let viewId, _):
            let itemPerPage = 30
            let limit = CAFetchError.maxPageCount * itemPerPage
            let cacheLimit = 15
            
            let items = try StoredCacheItem
                .join(StoredCacheItemMap.all) { $0.id.eq($1.item_id) }
                .where { a, _ in a.type_name == Item.typeName }
                .where { $1.view_id == viewId }
                .order { $1.order }
                .limit(loadingAll ? limit : cacheLimit)
                .fetchAll(db)
            
            return items.map { item, map in
                    .init(fromCacheJSONString: item.json_string, state: item.caState)
            }
        case nil:
            return []
        }
    }
}
