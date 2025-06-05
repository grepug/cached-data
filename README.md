# CachedData

A Swift package for efficient data fetching and caching with built-in support for pagination and SQLite persistence.

## Overview

CachedData is a lightweight, type-safe framework designed to simplify data fetching, caching, and retrieval in iOS and macOS applications. It provides a robust solution for managing remote data with local persistence, handling pagination, and managing data views.

## Features

- **Type-safe data fetching**: Generic adapters for different data sources
- **Automatic caching**: Persistent storage of fetched data in SQLite database
- **Pagination support**: Built-in handling for cursor-based pagination
- **Data views**: Group and access related cached items efficiently
- **Error handling**: Comprehensive error types and user-friendly messages
- **SwiftUI integration**: Observable objects for seamless UI updates

## Requirements

- iOS 17.0+ / macOS 14.0+
- Swift 6.1+
- Xcode 15.0+

## Installation

### Swift Package Manager

Add CachedData to your project by adding it as a dependency in your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/cached-data.git", from: "1.0.0")
]
```

## Usage

### Basic Setup

First, ensure the cache database is properly initialized:

```swift
// Access the shared database
let database = DatabaseQueue.observableModelDatabase
```

### Creating a Data Fetcher

1. Define your data model conforming to `DataFetcherItem`:

```swift
struct MyItem: DataFetcherItem {
    let id: UUID
    let name: String

    var stringId: String { id.uuidString }

    func toCacheItem() -> StoredCacheItem {
        let encoder = JSONEncoder()
        let data = try! encoder.encode(self)
        return StoredCacheItem(
            id: stringId,
            type_name: String(describing: Self.self),
            created_at: Date(),
            json_string: String(data: data, encoding: .utf8)!
        )
    }

    init(fromCache item: StoredCacheItem) {
        let decoder = JSONDecoder()
        let data = item.json_string.data(using: .utf8)!
        self = try! decoder.decode(Self.self, from: data)
    }
}
```

2. Create your fetcher adapter:

```swift
struct MyAdapter: DataFetcherAdapter {
    typealias Item = MyItem

    var params: MyParams
    var pageInfo: MyPageInfo?

    init(params: MyParams) {
        self.params = params
    }

    func fetch() async throws -> ([MyItem], MyPageInfo) {
        // Implement your network request logic here
    }
}
```

3. Instantiate and use the fetcher:

```swift
let fetcher = DataFetcher(adapter: MyAdapter(params: MyParams()))

// Load data
await fetcher.load()

// Access items
let items = fetcher.items
```

## Dependencies

- [SharingGRDB](https://github.com/pointfreeco/sharing-grdb.git) - SQLite database management
- [ErrorKit](https://github.com/FlineDev/ErrorKit.git) - Error handling utilities

## License

This project is available under the MIT license.
