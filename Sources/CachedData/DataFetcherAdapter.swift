//
//  DataFetcherAdapter.swift
//  cached-data
//
//  Created by Kai Shao on 2025/6/5.
//

@MainActor
public protocol DataFetcherAdapter {
    associatedtype Item: DataFetcherItem
    associatedtype Params: DataFetcherParams
    associatedtype PageInfo: DataFetcherPageInfo
    
    var params: Params { get set }
    var pageInfo: PageInfo? { get set }
    
    func fetch() async throws -> ([Item], PageInfo)
    
    init(params: Params)
}

public protocol DataFetcherPageInfo: Sendable {
    var hasNext: Bool? { get }
    var endCursor: String? { get }
}

public protocol DataFetcherParams: Sendable {
    func setEndCursor(_ cursor: String?)
}

public protocol DataFetcherItem: Codable, Sendable {
    var stringId: String { get }
    
    func toCacheItem() -> StoredCacheItem
    
    init(fromCache: StoredCacheItem)
}
