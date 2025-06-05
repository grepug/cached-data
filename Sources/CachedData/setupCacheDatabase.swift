//
//  a.swift
//  cached-data
//
//  Created by Kai Shao on 2025/6/5.
//

import Foundation
import SharingGRDB

extension DatabaseWriter where Self == DatabaseQueue {
    static var observableModelDatabase: Self {
        let path = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.visionapp.context")!
            .appending(path: "contextModel.sqlite")
            .path()
        
        let databaseQueue = try! DatabaseQueue(path: path)
        
        print("path!!!", databaseQueue.path)
        
        var migrator = DatabaseMigrator()
        
        migrator.registerMigration("Create tables") { db in
            try #sql(
                """
                CREATE TABLE "storedCacheItems" (
                  "id" TEXT PRIMARY KEY NOT NULL,
                  "type_name" TEXT NOT NULL,
                  "created_at" TEXT NOT NULL,
                  "json_string" TEXT NOT NULL
                );
                """
            )
            .execute(db)
            
            try #sql(
                """
                CREATE TABLE "storedCacheViewItems" (
                  "id" TEXT PRIMARY KEY NOT NULL,
                  "item_ids_json" TEXT NOT NULL
                );
                """
            )
            .execute(db)
        }
        try! migrator.migrate(databaseQueue)
        return databaseQueue
    }
}

public func setupCacheDatabase() {
    prepareDependencies { $0.defaultDatabase = .observableModelDatabase }
}
