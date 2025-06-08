//
//  DataFetcher.swift
//  ContextBackendModels
//
//  Created by Kai Shao on 2025/6/4.
//

import SwiftUI
import ErrorKit
import SharingGRDB
import Combine


struct CaCacheUpdateEvent {
    enum Kind {
        case reloadAfterInsertion
    }
    
    let viewId: String
    let itemTypeName: String
    let kind: Kind
}

@MainActor
let caCacheUpdatedSubject = PassthroughSubject<CaCacheUpdateEvent, Never>()

@Observable
@MainActor
public class CAFetcher<Item: CAItem>  {
    typealias PageInfo = Item.PageInfo
    public typealias Params = Item.Params
    
    var params: Params
    
    var pageInfo: PageInfo?
    
    @ObservationIgnored
    let viewId: String
    
    @ObservationIgnored
    @Dependency(\.defaultDatabase) var database
    
    @ObservationIgnored
    @Fetch(ItemRequest<Item>()) var fetchedItems = []
    
    @ObservationIgnored
    var cancellables = Set<AnyCancellable>()
    
    public var items: [Item] {
        fetchedItems
    }
    
    public var item: Item? {
        fetchedItems.first
    }
    
    public var hasNext: Bool {
        pageInfo?.hasNext == true
    }
    
    public init(viewId: String, itemType: Item.Type, params: Params) {
        self.viewId = viewId
        self.params = params
        
        Task {
            try await loadCache()
        }
        
        caCacheUpdatedSubject
            .filter { $0.itemTypeName == Item.typeName }
            .sink { [weak self] event in
                self?.handleEvent(event)
            }
            .store(in: &cancellables)
    }
    
    private func handleEvent(_ event: CaCacheUpdateEvent) {
        switch event.kind {
        case .reloadAfterInsertion:
            Task {
                try await load(reset: true)
            }
        }
    }
    
    private func loadCache() async throws {
        try await $fetchedItems.load(ItemRequest(viewId: viewId), animation: .default)
    }
    
    public func load(reset: Bool = false) async throws {
        try await loadImpl(reset: reset)
    }
    
    func loadImpl(reset: Bool) async throws {
        guard reset || hasNext else {
            return
        }
        
        if reset {
            pageInfo = nil
        }
        
        let viewId = viewId
        
        params = params.setEndCursor(pageInfo?.endCursor)
        
        let (newItems, newPageInfo) = try await Item.fetch(params: params)
        
        let finalItems: [Item]
        
        if pageInfo == nil {
            finalItems = newItems
        } else {
            finalItems = fetchedItems + newItems
        }
        
        pageInfo = newPageInfo
        
        try await database.write { db in
            // delete all maps
            
            try db.execute(sql:
                """
                DELETE FROM "storedCacheItemMaps"
                WHERE "view_id" = '\(viewId)'
                  AND "item_id" IN (
                    SELECT "id" FROM "storedCacheItems"
                    WHERE "type_name" = '\(Item.typeName)'
                  );                
                """
            )
            
            try StoredCacheItem
                .insert(or: .replace, finalItems.map { $0.toCacheItem(state: .normal) })
                .execute(db)
            
            let maps = finalItems.enumerated().map { index, item in
                StoredCacheItemMap(view_id: viewId, item_id: item.idString, order: index)
            }
            
            try StoredCacheItemMap
                .insert(or: .fail, maps)
                .execute(db)
        }
    }
}
