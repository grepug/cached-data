# CachedData

A modern Swift package for building robust offline-first applications with automatic SQLite persistence, reactive data synchronization, and optimistic UI updates.

## Overview

CachedData is a comprehensive framework that bridges the gap between remote APIs and local storage, providing a seamless offline-first experience for iOS and macOS applications. It manages the complete lifecycle of data fetching, caching, mutations, and UI synchronization with minimal boilerplate.

### Key Capabilities

**Offline-First Architecture**: All data is automatically cached in SQLite, allowing your app to function without network connectivity. The framework handles data synchronization between local cache and remote sources intelligently.

**Reactive Data Binding**: Built on Swift's Observation framework and SQLiteData's `@Fetch` macro, changes to your data automatically propagate to SwiftUI views without manual state management.

**Optimistic Updates**: Perform CRUD operations with instant UI feedback while mutations are processed in the background. Automatic rollback on failure ensures data consistency.

**View-Based Organization**: Group cached items into logical "views" (like feeds, lists, or collections) that can be independently managed and refreshed without affecting other parts of your app.

**Type-Safe & Protocol-Driven**: Define your models once, and the framework handles serialization, caching, fetching, and synchronization automatically.

## Features

- **Automatic SQLite Persistence**: All fetched data is transparently cached using SQLiteData with zero configuration
- **Cursor-Based Pagination**: Built-in support for infinite scrolling and load-more patterns
- **View Management**: Organize items into logical views with independent caching and refresh strategies
- **Optimistic Mutations**: Insert, update, and delete operations with automatic rollback on failure
- **State Management**: Track item states (normal, inserting, updating, deleting) for UI feedback
- **Error Handling**: Comprehensive error types with user-friendly messages (NotifiableError protocol)
- **Reactive Synchronization**: Cross-view updates propagate automatically via Combine publishers
- **SwiftUI Integration**: `@Observable` fetchers that work seamlessly with SwiftUI's data flow
- **Fetch Strategies**: Support for both single-item and collection fetching patterns
- **Background Refresh**: Reload data while maintaining user context and scroll position

## Requirements

- iOS 17.0+ / macOS 14.0+
- Swift 6.1+
- Xcode 15.0+

## Installation

### Swift Package Manager

Add CachedData to your project in Xcode:

1. Go to **File → Add Package Dependencies**
2. Enter the package URL: `https://github.com/grepug/cached-data.git`
3. Select version `1.0.0` or later

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/grepug/cached-data.git", from: "1.0.0")
]
```

## Core Concepts

### CAItem Protocol

The foundation of CachedData is the `CAItem` protocol. Your data models conform to this protocol to gain automatic caching and fetching capabilities:

```swift
public protocol CAItem: Codable, Sendable, Identifiable, Hashable {
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
```

For mutable data, implement `CAMutableItem`:

```swift
public protocol CAMutableItem: CAItem {
    func update() async throws(CAMutationError)
    func insert() async throws(CAMutationError)
    func delete() async throws(CAMutationError)
}
```

### CAFetcher

`CAFetcher` is an observable class that manages the complete lifecycle of your data:

- **Loading**: Fetches from network and caches to SQLite
- **Caching**: Automatic persistence using SQLiteData
- **Observing**: Reactive updates via Swift's Observation framework
- **Pagination**: Handles cursor-based pagination automatically
- **Synchronization**: Propagates changes across views

### View-Based Caching

Items can be organized into "views" - logical collections that can be independently refreshed:

```swift
// Different views for the same item type
let feedView = CAFetcher(.fetchAll(viewId: "user-feed", allPages: false), ...)
let searchView = CAFetcher(.fetchAll(viewId: "search-results", allPages: false), ...)
```

### State Management

Items track their mutation state for UI feedback:

- `.normal`: Regular state
- `.inserting`: Currently being created
- `.updating`: Currently being modified
- `.deleting`: Currently being removed

## Usage

### 1. Define Your Data Model

Implement the `CAItem` protocol for your model:

```swift
struct Post: CAItem {
    // MARK: - Properties
    let id: UUID
    var title: String
    var content: String
    var createdAt: Date
    var caState: CAItemState = .normal

    var idString: String { id.uuidString }

    // MARK: - Associated Types
    struct PageInfo: CAItemPageInfo {
        let hasNext: Bool
        let endCursor: String?
    }

    struct Params: CAItemParams {
        var userId: String?
        var cursor: String?

        func setEndCursor(_ cursor: String?) -> Self {
            var copy = self
            copy.cursor = cursor
            return copy
        }
    }

    // MARK: - CAItem Requirements
    static var typeName: String { "Post" }

    init() {
        self.id = UUID()
        self.title = ""
        self.content = ""
        self.createdAt = Date()
    }

    // Convert to cache storage format
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

    // Restore from cache
    init(fromCacheJSONString string: String, state: CAItemState) {
        let decoder = JSONDecoder()
        let data = string.data(using: .utf8)!
        var decoded = try! decoder.decode(Self.self, from: data)
        decoded.caState = state
        self = decoded
    }

    // Fetch from remote API
    static func fetch(params: Params) async throws -> CAFetchResult<Post, PageInfo> {
        // Your network request implementation
        let response = try await APIClient.fetchPosts(userId: params.userId, cursor: params.cursor)

        return CAFetchResult(
            items: response.posts,
            pageInfo: PageInfo(hasNext: response.hasNext, endCursor: response.endCursor)
        )
    }
}
```

### 2. Create a Fetcher

```swift
import SwiftUI
import CachedData

@Observable
class FeedViewModel {
    let fetcher: CAFetcher<Post>

    init(userId: String) {
        // Fetch all posts for a user's feed
        self.fetcher = CAFetcher(
            .fetchAll(viewId: "feed-\(userId)", allPages: false),
            itemType: Post.self,
            params: Post.Params(userId: userId)
        )
    }

    func loadFeed() async {
        do {
            try await fetcher.setup()
        } catch {
            print("Failed to load feed: \(error)")
        }
    }

    func loadMore() async {
        guard fetcher.hasNext else { return }

        do {
            try await fetcher.load()
        } catch {
            print("Failed to load more: \(error)")
        }
    }

    func refresh() async {
        do {
            try await fetcher.reload()
        } catch {
            print("Failed to refresh: \(error)")
        }
    }
}
```

### 3. Use in SwiftUI

```swift
struct FeedView: View {
    @State var viewModel: FeedViewModel

    var body: some View {
        ScrollView {
            LazyVStack {
                ForEach(viewModel.fetcher.items) { post in
                    PostRow(post: post)
                        .opacity(post.caState == .deleting ? 0.5 : 1.0)
                }

                if viewModel.fetcher.hasNext {
                    ProgressView()
                        .onAppear {
                            Task { await viewModel.loadMore() }
                        }
                }
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            await viewModel.loadFeed()
        }
    }
}
```

### 4. Implementing Mutations

For data that can be modified, implement `CAMutableItem`:

```swift
extension Post: CAMutableItem {
    func update() async throws(CAMutationError) {
        guard let response = try? await APIClient.updatePost(
            id: idString,
            title: title,
            content: content
        ) else {
            throw .failed
        }

        guard response.success else {
            throw .failed
        }
    }

    func insert() async throws(CAMutationError) {
        guard let response = try? await APIClient.createPost(
            title: title,
            content: content
        ) else {
            throw .failed
        }

        guard response.success else {
            throw .failed
        }
    }

    func delete() async throws(CAMutationError) {
        guard let response = try? await APIClient.deletePost(id: idString) else {
            throw .failed
        }

        guard response.success else {
            throw .failed
        }
    }
}
```

### 5. Performing Mutations with Optimistic Updates

```swift
@Dependency(\.caHandlers) var handlers

// Update a post
func updatePost(_ post: inout Post, newTitle: String) async {
    post.title = newTitle

    do {
        try await handlers.update(
            post,
            action: .action(.refresh, viewId: "feed-\(userId)")
        )
    } catch {
        print("Update failed: \(error.userFriendlyMessage)")
    }
}

// Insert a new post
func createPost(title: String, content: String) async {
    var newPost = Post()
    newPost.title = title
    newPost.content = content

    do {
        try await handlers.insert(
            newPost,
            action: .action(.prepend, viewId: "feed-\(userId)")
        )
    } catch {
        print("Insert failed: \(error.userFriendlyMessage)")
    }
}

// Delete a post
func deletePost(_ post: Post) async {
    do {
        try await handlers.delete(post)
    } catch {
        print("Delete failed: \(error.userFriendlyMessage)")
    }
}
```

### 6. Fetching Single Items

For detail views, use the single-item fetch strategy:

```swift
class PostDetailViewModel {
    let fetcher: CAFetcher<Post>

    init(postId: String) {
        self.fetcher = CAFetcher(
            .fetchOne(itemId: postId),
            itemType: Post.self,
            params: Post.Params()
        )
    }

    var post: Post {
        fetcher.item  // Returns the post or an empty initialized instance
    }

    var optionalPost: Post? {
        fetcher.optionalItem  // Returns nil if not found
    }

    func load() async {
        try? await fetcher.setup()
    }
}
```

## Advanced Features

### Cross-View Synchronization

When data changes in one view, other views can be automatically notified:

```swift
// Update will reload all other views with matching item type
try await handlers.update(post, action: .action(.refresh))

// Update specific view only
try await handlers.update(post, action: .action(.refresh, viewId: "feed-123"))

// Reload programmatically
handlers.reload(forType: Post.self, viewId: "feed-123")
```

### Cache-Only Mode

Load from cache without network requests:

```swift
try await fetcher.setup(cacheOnly: true)
```

### Custom Item Filtering

Filter items displayed in the fetcher:

```swift
let fetcher = CAFetcher(
    .fetchAll(viewId: "posts", allPages: false),
    itemType: Post.self,
    params: Post.Params(),
    itemFilter: { post in
        // Only show posts from last 7 days
        post.createdAt > Date().addingTimeInterval(-7 * 24 * 60 * 60)
    }
)
```

### Reactive Value Streams

Subscribe to data changes using Combine or async sequences:

```swift
// Using Combine
fetcher.fetchedValuePublisher
    .sink { value in
        switch value {
        case .initial:
            print("Not loaded yet")
        case .empty:
            print("No items found")
        case .fetched(let items):
            print("Loaded \(items.count) items")
        }
    }

// Using async/await
for await value in fetcher.asyncFetchedValue {
    // Handle value changes
}
```

### Insert Position Strategies

Control where new items appear in a list:

```swift
// Add to beginning of list
.action(.prepend, viewId: "feed")

// Add to end of list
.action(.append, viewId: "feed")

// Insert before a specific item
.action(.insertBefore(id: existingPostId), viewId: "feed")

// Insert after a specific item
.action(.insertAfter(id: existingPostId), viewId: "feed")

// No view update
.action(.noAction)
```

### Error Handling

CachedData provides user-friendly error messages:

```swift
do {
    try await fetcher.reload()
} catch let error as CAFetchError {
    if error.isCancellationError {
        // Handle cancellation
    } else {
        // Show error.userFriendlyMessage to user
        showAlert(error.userFriendlyMessage)
    }
}
```

### Fetcher State Management

Monitor the fetcher's current state:

```swift
switch fetcher.state {
case .initializing:
    // Show loading placeholder
    ProgressView()
case .loadingFirst:
    // Show initial load spinner
    ProgressView("Loading...")
case .idle:
    // Ready for interaction
    ContentView()
case .loading:
    // Show loading indicator for pagination
    LoadingFooter()
}
```

## Architecture

### Data Flow

```
Network API → CAItem.fetch() → CAFetcher → SQLite (StoredCacheItem)
                    ↓
              SwiftUI View (reactive updates via @Observable)
                    ↓
         User Action → CAHandlers → Optimistic Update → Network
                    ↓
         Success → Cache Update → Propagate to Other Views
         Failure → Rollback Cache → Restore Previous State
```

### Database Schema

CachedData uses two main tables:

**storedCacheItems**: Stores all cached items

- `id`: Item identifier
- `type_name`: Item type (for polymorphic queries)
- `created_at`: Cache timestamp
- `json_string`: Serialized item data
- `state`: Current mutation state

**storedCacheItemMaps**: Maps items to views

- `view_id`: View identifier
- `item_id`: Reference to cached item
- `order`: Position in the view

## Dependencies

- [SQLiteData](https://github.com/pointfreeco/sqlite-data.git) - Type-safe SQLite wrapper with reactive queries
- [ErrorKit](https://github.com/FlineDev/ErrorKit.git) - User-friendly error handling

## Best Practices

1. **Use descriptive view IDs**: Makes debugging and cache management easier
2. **Implement proper error handling**: Always handle `CAFetchError` and `CAMutationError`
3. **Set appropriate fetch strategies**: Use `.fetchOne` for details, `.fetchAll` for lists
4. **Handle state transitions**: Show loading states and disable actions during mutations
5. **Test offline scenarios**: Verify your app works without network connectivity
6. **Cache expiration**: Implement your own cache invalidation strategy based on timestamps

## License

This project is available under the MIT license.
