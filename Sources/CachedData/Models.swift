//
//  StoredCacheItem.swift
//  cached-data
//
//  Created by Kai Shao on 2025/6/5.
//

import SharingGRDB
import Foundation

@Table
public struct StoredCacheItem {
    var id: String
    var type_name: String
    var created_at: Date
    var json_string: String
}

@Table
struct StoredCacheViewItem {
    var id: String
    var item_ids_json: String
    
    init(id: String, item_ids: [String]) {
        self.id = id
        
        let encoder = JSONEncoder()
        let data = try! encoder.encode(item_ids)
        let string = String(data: data, encoding: .utf8)!
        
        self.item_ids_json = string
    }
    
    var item_ids: [String] {
        let decoder = JSONDecoder()
        let data = item_ids_json.data(using: .utf8)!
        return try! decoder.decode([String].self, from: data)
    }
}
