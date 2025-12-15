//
//  setupCacheDatabase.swift
//  cached-data
//
//  Created by Kai Shao on 2025/6/5.
//

import Foundation
import SQLiteData

extension DatabaseWriter where Self == DatabaseQueue {
    static func observableModelDatabase(path: DatabasePath) -> Self {
        let databaseQueue: DatabaseQueue

        switch path {
        case .stored(let path):
            databaseQueue = try! DatabaseQueue(path: path)
        case .inMemory:
            databaseQueue = try! DatabaseQueue()
        }
        
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
                  "order" REAL NOT NULL
                );
                """
            )
            .execute(db)

            try #sql(
                """
                CREATE UNIQUE INDEX unique_view_item ON "storedCacheItemMaps" ("view_id", "item_id");
                """
            ).execute(db)

            try #sql(
                """
                CREATE INDEX index_storedCacheItems_type_name ON storedCacheItems (type_name);
                """
            ).execute(db)
            
            try #sql(
                """
                CREATE INDEX index_storedCacheItemMaps_view_id ON storedCacheItemMaps (view_id);
                """
            ).execute(db)
        }
        
        try! migrator.migrate(databaseQueue)
        
        return databaseQueue
    }
}

public enum DatabasePath {
    case stored(path: String), inMemory
}

public func setupCacheDatabase(path: DatabasePath = .inMemory) {
    prepareDependencies { $0.defaultDatabase = .observableModelDatabase(path: path) }
}
