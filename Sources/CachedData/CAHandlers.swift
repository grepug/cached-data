//
//  CAMutation 2.swift
//  cached-data
//
//  Created by Kai Shao on 2025/6/12.
//

import Dependencies

public typealias Dep = Dependency

public protocol CAHandlers: Sendable {
    func delete<Item: CAMutableItem>(_ item: Item) async throws(CAMutationError)
    func insert<Item: CAMutableItem>(_ item: Item, action: CAInsertViewAction) async throws(CAMutationError)
    func update<Item: CAMutableItem>(_ item: Item, action: CAUpdateViewAction, updatedId: String?) async throws(CAMutationError)
    func reload<Item: CAItem>(_ type: Item.Type, viewId: String?, excludingViewIds: [String])

    func fetchCachedItem<Item: CAItem>(id: String, forType type: Item.Type) async throws -> Item?
    func fetchCachedItems<Item: CAItem>(ids: [String], forType type: Item.Type) async throws -> [Item]
    func updateCache<Item>(_ item: Item, state: CAItemState) async throws(CAMutationError) where Item : CAItem
    func insertCache<Item>(_ item: Item, state: CAItemState, viewId: String) async throws(CAMutationError) where Item : CAItem
}

public extension CAHandlers {
    func reload<Item: CAItem>(forType type: Item.Type, viewId: String? = nil, excludingViewIds: [String] = []) {
        reload(type, viewId: viewId, excludingViewIds: excludingViewIds)
    }
    
    /// Convenience method for updating without ID changes (backward compatibility)
    func update<Item: CAMutableItem>(_ item: Item, action: CAUpdateViewAction) async throws(CAMutationError) {
        try await update(item, action: action, updatedId: nil)
    }
}

private enum MutationKey: DependencyKey {
    static let liveValue: any CAHandlers = Handlers()
    static let testValue: any CAHandlers = Handlers()
    static let previewValue: any CAHandlers = Handlers()
}

public extension DependencyValues {
    var caHandlers: CAHandlers {
        get { self[MutationKey.self] }
        set { self[MutationKey.self] = newValue }
    }
}
