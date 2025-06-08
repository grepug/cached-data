//
//  StoredCacheItem.swift
//  cached-data
//
//  Created by Kai Shao on 2025/6/5.
//

import SharingGRDB
import Foundation

public enum CAItemState: Int, Sendable {
    case normal, updating, inserting, deleting
}

@Table
public struct StoredCacheItem: Identifiable {
    public var id: String
    var type_name: String
    var created_at: Date
    var json_string: String
    var state: Int
    
    var caState: CAItemState {
        .init(rawValue: state) ?? .normal
    }
    
    public init(id: String, type_name: String, created_at: Date, json_string: String, state: CAItemState = .normal) {
        self.id = id
        self.type_name = type_name
        self.created_at = created_at
        self.json_string = json_string
        self.state = state.rawValue
    }
}

@Table
struct StoredCacheItemMap {
    private let id: String
    let view_id: String
    let item_id: StoredCacheItem.ID
    let order: Int
    
    init(id: String = UUID().uuidString.lowercased(), view_id: String, item_id: StoredCacheItem.ID, order: Int) {
        self.id = id
        self.view_id = view_id
        self.item_id = item_id
        self.order = order
    }
}
