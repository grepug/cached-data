//
//  DataFetcherError.swift
//  cached-data
//
//  Created by Kai Shao on 2025/6/5.
//

import ErrorKit

public protocol NotifiableError: Catching, Throwable {
    var userNotable: Bool { get }
}

public extension NotifiableError {
    var userNotable: Bool {
        true
    }
}

public enum CAFetchError: NotifiableError {
    static let maxPageCount = 100
    
    case noMoreNextPage
    case maxPageReached
    case lastPageIsLoading
    case caught(Error)

    public var isCancellationError: Bool {
        if case .caught(let error) = self {
            if error is CancellationError {
                return true
            }
        }

        return false
    }
    
    public var userNotable: Bool {
        switch self {
        case .noMoreNextPage: false
        case .lastPageIsLoading: false
        case .maxPageReached: true
        case .caught: true
        }
    }
    
    public var userFriendlyMessage: String {
        switch self {
        case .noMoreNextPage:
            "没有更多数据可加载"
        case .maxPageReached:
            "已达到最大页数限制"
        case .lastPageIsLoading:
            "最后一页正在加载中，请稍后再试"
        case .caught(let error):
            ErrorKit.userFriendlyMessage(for: error)
        }
    }
}

public enum CAMutationError: NotifiableError {
    case failed
    case noAffectedRows
    case unauthorized
    case caught(Error)

    public var isCancellationError: Bool {
        if case .caught(let error) = self {
            if error is CancellationError {
                return true
            }
        }

        return false
    }
    
    public var userFriendlyMessage: String {
        switch self {
        case .failed:
            "操作失败，请稍后再试"
        case .unauthorized:
            "未登录"
        case .noAffectedRows:
            "没有影响到任何数据，请检查操作是否正确"
        case .caught(let error):
            ErrorKit.userFriendlyMessage(for: error)
        }
    }
}
