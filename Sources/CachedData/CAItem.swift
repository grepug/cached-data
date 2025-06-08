//
//  DataFetcherAdapter.swift
//  cached-data
//
//  Created by Kai Shao on 2025/6/5.
//

public protocol CAItemPageInfo: Sendable {
    var hasNext: Bool { get }
    var endCursor: String? { get }
}

public protocol CAItemParams: Sendable {
    func setEndCursor(_ cursor: String?) -> Self
}

public protocol CAItem: Codable, Sendable, Identifiable {
    associatedtype PageInfo: CAItemPageInfo
    associatedtype Params: CAItemParams
    
    var idString: String { get }
    
    var caState: CAItemState { get set }
    
    func toCacheItem(state: CAItemState) -> StoredCacheItem
    
    init(fromCacheJSONString string: String, state: CAItemState)
    
    static var typeName: String { get }
    
    static func fetch(params: Params) async throws -> ([Self], PageInfo)
}

public protocol CAMutableItem: CAItem {
    func update() async throws
    
    func insert() async throws
    
    func delete() async throws
}
