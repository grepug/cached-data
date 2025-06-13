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

public enum CAFetchedValue<Item: CAItem>: Sendable, Hashable {
    /// The initial state when no fetch has been performed yet.
    case initial
    /// fetched from the server but the result is empty.
    ///
    /// It is used to determine the existence of an item.
    case empty
    /// fetched with items
    case fetched([Item])
    
    /// fetched from the server but the result is empty.
    ///
    /// It is used to determine the existence of an item.
    public var isEmpty: Bool {
        if case .empty = self {
            return true
        }
        
        return false
    }
    
    public var items: [Item] {
        switch self {
        case .initial, .empty: []
        case .fetched(let items): items
        }
    }
    
    public var optionalItem: Item? {
        switch self {
        case .initial, .empty: nil
        case .fetched(let items): items.first
        }
    }
}

struct ItemRequest<Item: CAItem>: FetchKeyRequest {
    var fetchType: CAFetchType?
    var loadingAll = false
    var hasFetchedFromRemote = false
    
    typealias Value = CAFetchedValue<Item>
    
    func fetch(_ db: Database) throws -> Value {
        switch fetchType {
        case .fetchOne(let id):
            guard let item = (try StoredCacheItem
                .where { $0.type_name == Item.typeName }
                .where { $0.id == id }
                .fetchOne(db)) else {
                    return hasFetchedFromRemote ? .empty : .initial
                }

                return .fetched([
                    .init(fromCacheJSONString: item.json_string, state: item.caState)
                ])
        case .fetchAll(let viewId, _):
            let itemPerPage = 30
            let max = CAFetchError.maxPageCount * itemPerPage
            let cacheLimit = 15
            
            let items = try StoredCacheItem
                .join(StoredCacheItemMap.all) { $0.id.eq($1.item_id) }
                .where { a, _ in a.type_name == Item.typeName }
                .where { $1.view_id == viewId }
                .order { $1.order }
                .limit(loadingAll ? max : cacheLimit)
                .fetchAll(db)
            
            return .fetched(items.map { item, map in
                    .init(fromCacheJSONString: item.json_string, state: item.caState)
            })
        case nil:
            return .initial
        }
    }
}
