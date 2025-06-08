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

struct CACacheUpdateEvent {
    enum Kind {
        case reloadAfterInsertion
    }
    
    let viewId: String
    let itemTypeName: String
    let kind: Kind
}

@MainActor
let caCacheUpdatedSubject = PassthroughSubject<CACacheUpdateEvent, Never>()

@Observable
@MainActor
public class CAFetcher<Item: CAItem>  {
    typealias PageInfo = Item.PageInfo
    public typealias Params = Item.Params
    
    var params: Params
    
    var pageInfo: PageInfo?
    
    enum FirstFetchState {
        case pending, fetched, idle
    }
    
    var firstFetchState: FirstFetchState = .idle
    
    public var initialFetched: Bool {
        firstFetchState == .fetched
    }
    
    @ObservationIgnored
    let viewId: String
    
    @ObservationIgnored
    @Dependency(\.defaultDatabase) var database
    
    @ObservationIgnored
    @Dependency(\.caLogger) var logger
    
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
        
        // ⚠️ FIXME: it possibly cause a self retain cycle
        caCacheUpdatedSubject
            .filter { $0.itemTypeName == Item.typeName }
            .sink { [weak self] event in
                self?.handleEvent(event)
            }
            .store(in: &cancellables)
    }
    
    public func setup() async throws(CAError) {
        do {
            try await setupImpl()
        } catch {
            logger.error(ErrorKit.userFriendlyMessage(for: error), [
                "trace": "\(ErrorKit.errorChainDescription(for: error))"
            ])
        }
    }
    
    public func reload() async throws(CAError) {
        do {
            try await load(reset: true)
        } catch {
            logger.error(error)
            throw error
        }
    }
    
    public func loadNextIfAny() async throws(CAError) {
        do {
            try await loadNextIfAnyImpl()
        } catch {
            logger.error(error)
            throw error
        }
    }
}

private extension CAFetcher {
    private func setupImpl() async throws(CAError) {
        guard firstFetchState == .idle else {
            assertionFailure("setup should only be called once")
            return
        }
        
        firstFetchState = .pending
        
        try await CAError.catch { @Sendable in
            try await $fetchedItems.load(ItemRequest(viewId: viewId), animation: .default)
        }
        
        // ensure the items are loaded
        if !fetchedItems.isEmpty {
            firstFetchState = .fetched
        }
        
        try await load(reset: true)
        
        if firstFetchState != .fetched {
            firstFetchState = .fetched
        }
    }
    
    private func loadNextIfAnyImpl() async throws(CAError) {
        guard hasNext else {
            assertionFailure("loadNextIfAny should not be called when there is no next page")
            throw .fetchFailed(.noMoreNextPage)
        }
        
        try await load(reset: false)
    }
    
    private func load(reset: Bool) async throws(CAError) {
        guard reset || hasNext else {
            return
        }
        
        if reset {
            pageInfo = nil
        }
        
        params = params.setEndCursor(pageInfo?.endCursor)
        
        let viewId = viewId
        
        let (newItems, newPageInfo) = try await CAFetchError.catch { @Sendable in
            try await Item.fetch(params: params)
        } mapTo: {
            CAError.fetchFailed($0)
        }
        
        let finalItems: [Item] = if pageInfo == nil {
            newItems
        } else {
            fetchedItems + newItems
        }
        
        pageInfo = newPageInfo
            
        try await CAError.catch { @Sendable in
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
    
    func handleEvent(_ event: CACacheUpdateEvent) {
        switch event.kind {
        case .reloadAfterInsertion:
            Task {
                try await load(reset: true)
            }
        }
    }
}
