//
//  StoredCacheItem.swift
//  cached-data
//
//  Created by Kai Shao on 2025/6/5.
//

import SharingGRDB
import Foundation

//public enum ItemState: Sendable {
//    case normal, mutating, deleting
//}
//
//@dynamicMemberLookup
//public struct ItemWrapper<Item: DataFetcherItem>: Sendable, Identifiable {
//    let value: Item
//    public var id: Item.ID { value.id }
//    
//    var state: ItemState = .normal
//    
//    subscript<T>(dynamicMember keyPath: KeyPath<Item, T>) -> T {
//         value[keyPath: keyPath]
//     }
//}

@Table
public struct StoredCacheItem: Identifiable {
    public var id: String
    var type_name: String
    var created_at: Date
    var json_string: String
    
    // 0: normal
    // 1: being deleted
    // 2: being updating or inserting
    var state: Int
}

@Table
struct StoredCacheItemMap {
    let id: String
    let item_id: StoredCacheItem.ID
    let order: Int
}
