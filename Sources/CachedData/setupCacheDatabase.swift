//
//  a.swift
//  cached-data
//
//  Created by Kai Shao on 2025/6/5.
//

import Foundation
import SharingGRDB

extension DatabaseWriter where Self == DatabaseQueue {
    static func observableModelDatabase(path: String) -> Self {
        let databaseQueue = try! DatabaseQueue(path: path)
        
        print("CachedData database path", databaseQueue.path)
        
        var migrator = DatabaseMigrator()
        
        migrator.registerMigration("Create tables") { db in
            try #sql(
                """
                CREATE TABLE "storedCacheItems" (
                  "id" TEXT PRIMARY KEY NOT NULL,
                  "type_name" TEXT NOT NULL,
                  "created_at" TEXT NOT NULL,
                  "json_string" TEXT NOT NULL,
                  "state" INTEGER NOT NULL
                );
                """
            )
            .execute(db)
            
            try #sql(
                """
                CREATE TABLE "storedCacheItemMaps" (
                  "id" TEXT PRIMARY KEY NOT NULL,
                  "view_id" TEXT NOT NULL,
                  "item_id" TEXT NOT NULL,
                  "order" INTEGER NOT NULL
                );
                """
            )
            .execute(db)
        }
        try! migrator.migrate(databaseQueue)
        return databaseQueue
    }
}

public func setupCacheDatabase(path: String) {
    prepareDependencies { $0.defaultDatabase = .observableModelDatabase(path: path) }
}
