//
//  reloadCache.swift
//  cached-data
//
//  Created by Kai Shao on 2025/6/12.
//

import Combine
import Dependencies

// MARK: - Cache Update Event Definition

/// Structure representing a cache update event that can be published to notify subscribers.
struct CACacheReloadEvent {
    /// The view identifier associated with this event
    let viewId: String?
    
    let excludingViewIds: [String]
    
    /// The type name of the item that was updated
    let itemTypeName: String
}

/// Global subject for broadcasting cache update events throughout the app
@MainActor
let caCacheReloadSubject = PassthroughSubject<CACacheReloadEvent, Never>()
