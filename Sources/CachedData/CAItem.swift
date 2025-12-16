//
//  DataFetcherAdapter.swift
//  cached-data
//
//  Created by Kai Shao on 2025/6/5.
//

import Foundation

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

public protocol CAItem: Sendable, Identifiable, Hashable {
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

// MARK: - Default Codable Implementation

public extension CAItem where Self: Codable {
    func toCacheItem(state: CAItemState) -> StoredCacheItem {
        let encoder = JSONEncoder()
        let jsonData = try! encoder.encode(self)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        
        return StoredCacheItem(
            id: idString,
            type_name: Self.typeName,
            created_at: Date(),
            json_string: jsonString,
            state: state
        )
    }
    
    init(fromCacheJSONString string: String, state: CAItemState) {
        let decoder = JSONDecoder()
        let data = string.data(using: .utf8)!
        var decoded = try! decoder.decode(Self.self, from: data)
        decoded.caState = state
        self = decoded
    }
}

// MARK: - Mutable Item Protocol

public protocol CAMutableItem: CAItem {
    func update() async throws(CAMutationError)
    func insert() async throws(CAMutationError)
    func delete() async throws(CAMutationError)
    
    /// uncomment to implement batch operations
//    static func update(items: [Self]) async throws(CAMutationError)
//    static func insert(items: [Self]) async throws(CAMutationError)
//    static func delete(items: [Self]) async throws(CAMutationError)
}

//public extension CAMutableItem {
//    func update() async throws(CAMutationError) {
//        try await Self.update(items: [self])
//    }
//    
//    func insert() async throws(CAMutationError) {
//        try await Self.insert(items: [self])
//    }
//    
//    func delete() async throws(CAMutationError) {
//        try await Self.delete(items: [self])
//    }
//}
