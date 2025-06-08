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
    
    enum State: Int {
        case initializing, loadingFirst, idle, loading
    }
    
    var state = State.initializing
    
//    enum FirstFetchState {
//        case pending, fetched, idle
//    }
//
//    var firstFetchState: FirstFetchState = .idle
    
    public var initialFetched: Bool {
        state.rawValue >= State.idle.rawValue
    }
    
    @ObservationIgnored
    let fetchType: CAFetchType
    
    @ObservationIgnored
    @Dependency(\.defaultDatabase) var database
    
    @ObservationIgnored
    @Dependency(\.caLogger) var logger
    
    @ObservationIgnored
    @Fetch(ItemRequest<Item>()) var fetchedItems = []
    
    public var itemPublisher: AnyPublisher<Item, Never> {
        $fetchedItems
            .publisher
            .map { $0.first ?? .init() }
            .eraseToAnyPublisher()
    }
    
    public var itemsPublisher: AnyPublisher<[Item], Never> {
        $fetchedItems
            .publisher
            .eraseToAnyPublisher()
    }
    
    public var asyncItem: AsyncPublisher<some Publisher<Item, Never>> {
        itemPublisher.values
    }
    
    public var asyncItems: AsyncPublisher<some Publisher<Array<Item>, Never>> {
        itemsPublisher.values
    }
    
    @ObservationIgnored
    var cancellables = Set<AnyCancellable>()
    
    public var items: [Item] {
        fetchedItems
    }
    
    public var item: Item {
        fetchedItems.first ?? .init()
    }
    
    public var optionalItem: Item? {
        fetchedItems.first
    }
    
    public var hasNext: Bool {
        pageInfo?.hasNext == true
    }
    
    public init(_ fetchType: CAFetchType, itemType: Item.Type, params: Params) {
        self.fetchType = fetchType
        self.params = params
        
        // ⚠️ FIXME: it possibly cause a self retain cycle
        caCacheUpdatedSubject
            .filter { $0.itemTypeName == Item.typeName }
            .sink { [weak self] event in
                self?.handleEvent(event)
            }
            .store(in: &cancellables)
    }
    
    public func loadItemWithoutCache() async throws -> Item? {
        try await loadItemsWithoutCache().first
    }
    
    public func loadItemsWithoutCache() async throws -> [Item] {
        try await Item.fetch(params: params).0
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
        guard state == .initializing else {
            return
        }
        
        state = .loadingFirst
        
        try await loadRequest(all: false)
        
        // ensure the items are loaded
        if !fetchedItems.isEmpty {
            state = .idle
        }
        
        try await load(reset: true)
        
        try await loadRequest(all: true)
        
        if state != .idle {
            state = .idle
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
        
        if case .fetchAll(_, allPages: let allPages) = fetchType, allPages {
            assertionFailure()
            return
        }
        
        // if we are not in idle state, we should not load again
        guard state == .idle else {
            assertionFailure()
            return
        }
        
        state = .loading
        
        do {
            switch fetchType {
            case .fetchAll(viewId: let viewId, let allPages):
                if reset {
                    pageInfo = nil
                }
                try await fetch(viewId: viewId, allPages: allPages)
            case .fetchOne:
                try await fetch(viewId: nil)
            }
            
            state = .idle
        } catch {
            state = .idle
            
            throw error
        }
    }
    
    private func fetch(viewId: String?, allPages: Bool = false) async throws(CAError) {
        let isFetchOne = viewId == nil
        let isFirstFetch = pageInfo == nil
         
        let newItems = try await CAFetchError.catch { @Sendable in
            try await fetchItems(fetchAll: allPages)
        } mapTo: {
            CAError.fetchFailed($0)
        }
        
        let finalItems: [Item] = if isFirstFetch || isFetchOne {
            newItems
        } else {
            fetchedItems + newItems
        }
        
        if isFetchOne {
            assert(finalItems.count == 1)
        }
        
        try await CAError.catch { @Sendable in
            try await database.write { db in
                // delete all maps
                
                if let viewId {
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
                }
                
                let items = finalItems.map { $0.toCacheItem(state: .normal) }
                
                assert(
                    items.count == Set(items.map(\.id)).count,
                    "There are duplicate items in the fetched items",
                )
                
                try StoredCacheItem
                    .insert(or: .replace, items)
                    .execute(db)
                
                if let viewId {
                    let maps = finalItems.enumerated().map { index, item in
                        StoredCacheItemMap(view_id: viewId, item_id: item.idString, order: index)
                    }
                    
                    try StoredCacheItemMap
                        .insert(or: .fail, maps)
                        .execute(db)
                }
            }
        }
    }
    
    private func loadRequest(all: Bool) async throws(CAError) {
        try await CAError.catch { @Sendable in
            try await $fetchedItems.load(
                ItemRequest(
                    fetchType: fetchType,
                    loadingAll: all,
                ),
                animation: .default,
            )
        }
    }
    
    private func fetchItems(fetchAll: Bool) async throws -> [Item] {
        var finalItems: [Item] = []
        var fetched = false
        var maxPage = CAFetchError.maxPageCount
        
        while (hasNext && fetchAll) || !fetched {
            fetched = true
            
            let (newItems, newPageInfo) = try await Item.fetch(params: params)
            
            finalItems.append(contentsOf: newItems)
            
            pageInfo = newPageInfo
            params = params.setEndCursor(pageInfo?.endCursor)
            
            maxPage -= 1
            
            if maxPage == 0 {
                throw CAFetchError.maxPageReached
            }
        }
        
        assert(
            finalItems.count == Set(finalItems.map(\.idString)).count,
            "There are duplicate items in the fetched items",
        )
        
        return finalItems
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
