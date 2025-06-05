//
//  DataFetcher.swift
//  ContextBackendModels
//
//  Created by Kai Shao on 2025/6/4.
//

import SwiftUI
import ErrorKit
import SharingGRDB

@Observable
@MainActor
public class DataFetcher<Adaptor: DataFetcherAdapter> {
    public typealias Item = Adaptor.Item
    
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
        
        let (newItems, pageInfo) = try await adaptor.fetch()

        let finalItems: [Item]
        
        if adaptor.pageInfo == nil {
            finalItems = newItems
        } else {
            finalItems = fetchedItems + newItems
        }
        
        adaptor.pageInfo = pageInfo
        
        let id = viewId
        
        try await database.write { db in
            let itemIds = finalItems.map { $0.stringId }
            
            try StoredCacheViewItem
                .insert(or: .replace, StoredCacheViewItem(id: id, item_ids: itemIds))
                .execute(db)
            
            try StoredCacheItem
                .insert(or: .replace, finalItems.map { $0.toCacheItem() })
                .execute(db)
        }
    }
    
    public func load(reset: Bool = false) async throws {
        if reset {
            // Reset cache and reload
            adaptor.pageInfo = nil
            let id = viewId
            
            try await database.write { db in
                try StoredCacheViewItem
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
