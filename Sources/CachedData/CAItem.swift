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

public struct CAFetchResult<Item: Sendable, PageInfo: CAItemPageInfo>: Sendable {
    public let items: [Item]
    public let pageInfo: PageInfo
    
    public var item: Item? {
        items.first
    }
    
    public init(items: [Item], pageInfo: PageInfo) {
        self.items = items
        self.pageInfo = pageInfo
    }
}

public protocol CAItem: Codable, Sendable, Identifiable, Hashable {
    associatedtype PageInfo: CAItemPageInfo
    associatedtype Params: CAItemParams
    
    var idString: String { get }
    
    var caState: CAItemState { get set }
    
    func toCacheItem(state: CAItemState) -> StoredCacheItem
    
    init(fromCacheJSONString string: String, state: CAItemState)
    
    init()
    
    static var typeName: String { get }
    
    static func fetch(params: Params) async throws -> CAFetchResult<Self, PageInfo>
}

public protocol CAMutableItem: CAItem {
    func update() async throws(CAMutationError)
    
    func insert() async throws(CAMutationError)
    
    func delete() async throws(CAMutationError)
}
