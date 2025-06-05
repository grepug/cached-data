//
//  DataFetcher.swift
//  ContextBackendModels
//
//  Created by Kai Shao on 2025/6/4.
//

import SwiftUI
import ErrorKit
import SharingGRDB

@MainActor
public class DataMutation<Adaptor: DataFetcherAdapter> {
    let adaptor: Adaptor
    
    @Dependency(\.defaultDatabase) var db
    
    public init(adaptor: Adaptor) {
        self.adaptor = adaptor
    }
    
    private func updateState<Item: DataFetcherItem>(_ item: Item, state: Int) async throws {
        try await db.write { db in
            try StoredCacheItem.where {
                $0.id == item.idString
            }
            .update { $0.state = state }
            .execute(db)
        }
    }
    
    public func delete<Item: DataFetcherItem>(_ item: Item) async throws {
        // first set the item in the cache that is being deleted
        try await updateState(item, state: 1)
        
        do {
            // fire the real mutation
            try await adaptor.delete(item)
            
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
            try await updateState(item, state: 0)
        }
    }
    
    public func upsert<Item: DataFetcherItem>(_ item: Item) async throws {
        try await db.write { db in
            try StoredCacheItem.where {
                $0.id == item.idString
            }
        }
    }
}


@Observable
@MainActor
public class DataFetcher<Item: DataFetcherItem, Adaptor: DataFetcherAdapter> {
    @ObservationIgnored
    var adaptor: Adaptor
    
    @ObservationIgnored
    let viewId: String
    
    @ObservationIgnored
    @Dependency(\.defaultDatabase) var database
    
    @ObservationIgnored
    @Fetch(ItemRequest<Item>()) var fetchedItems = []
    
    public var items: [Item] {
        fetchedItems
    }
    
    public var item: Item? {
        fetchedItems.first
    }
    
    public init(viewId: String, params: Adaptor.Params) {
        self.viewId = viewId
        self.adaptor = .init(params: params)
        
        Task {
            try await loadCache()
        }
    }
    
    private func loadCache() async throws {
        try await $fetchedItems.load(ItemRequest(viewId: viewId), animation: .default)
    }
    
    private func fetchFromRemote() async throws {
        adaptor.params.setEndCursor(adaptor.pageInfo?.endCursor)
        
        let (newItems, pageInfo) = try await adaptor.fetch(ofType: Item.self)

        let finalItems: [Item]
        
        if adaptor.pageInfo == nil {
            finalItems = newItems
        } else {
            finalItems = fetchedItems + newItems
        }
        
        adaptor.pageInfo = pageInfo
        
        let id = viewId
        
        try await database.write { db in
            // delete all maps
            try StoredCacheItemMap.where {
                $0.id == id
            }
            .delete()
            .execute(db)
            
            try StoredCacheItem
                .insert(or: .replace, finalItems.map { $0.toCacheItem() })
                .execute(db)
            
            let maps = finalItems.enumerated().map { index, item in
                StoredCacheItemMap(id: id, item_id: item.idString, order: index)
            }
            
            try StoredCacheItemMap
                .insert(or: .fail, maps)
                .execute(db)
        }
    }
    
    public func load(reset: Bool = false) async throws {
        if reset {
            // Reset cache and reload
            adaptor.pageInfo = nil
            let id = viewId
            
            try await database.write { db in
                try StoredCacheItemMap
                    .where { $0.id == id }
                    .delete()
                    .execute(db)
            }
        }
        
        if reset || adaptor.pageInfo?.hasNext == true {
            // fetch from network anyway
            try await fetchFromRemote()
        }
    }
}
