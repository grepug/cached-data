//
//  StoredCacheItem.swift
//  cached-data
//
//  Created by Kai Shao on 2025/6/5.
//

import SQLiteData
import Foundation

public enum CAItemState: Int, Sendable {
    case normal, updating, inserting, deleting
}

@Table
public struct StoredCacheItem: Identifiable, Sendable {
    public var id: String
    var type_name: String
    var created_at: Date
    var json_string: String
    var state: Int
    
    var caState: CAItemState {
        get {
            .init(rawValue: state) ?? .normal
        }
        
        set {
            state = newValue.rawValue
        }
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
struct StoredCacheItemMap: Sendable {
    private let id: String
    let view_id: String
    let item_id: StoredCacheItem.ID
    let order: Double
    
    init(id: String = UUID().uuidString.lowercased(), view_id: String, item_id: StoredCacheItem.ID, order: Double) {
        self.id = id
        self.view_id = view_id
        self.item_id = item_id
        self.order = order
    }
}
