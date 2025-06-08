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
    case noData
    case graphQLError([String])
    case noMoreNextPage
    case caught(Error)
    
    public var userNotable: Bool {
        switch self {
        case .noData: false
        case .graphQLError: true
        case .noMoreNextPage: false
        case .caught: true
        }
    }
    
    public var userFriendlyMessage: String {
        switch self {
        case .noData:
            "没有获取到数据"
        case .graphQLError(let messages):
            "GraphQL 错误: \(messages.joined(separator: ", "))"
        case .noMoreNextPage:
            "没有更多数据可加载"
        case .caught(let error):
            ErrorKit.userFriendlyMessage(for: error)
        }
    }
}

public enum CAMutationError: NotifiableError {
    case failed
    case noAffectedRows
    case caught(Error)
    
    public var userFriendlyMessage: String {
        switch self {
        case .failed:
            "操作失败，请稍后再试"
        case .noAffectedRows:
            "没有影响到任何数据，请检查操作是否正确"
        case .caught(let error):
            ErrorKit.userFriendlyMessage(for: error)
        }
    }
}

public enum CAError: NotifiableError {
    case fetchFailed(CAFetchError)
    case mutationFailed(CAMutationError)
    case caught(Error)
    
    public var userFriendlyMessage: String {
        switch self {
        case .mutationFailed(let error):
            ErrorKit.userFriendlyMessage(for: error)
        case .fetchFailed(let error):
            ErrorKit.userFriendlyMessage(for: error)
        case .caught(let error):
            ErrorKit.userFriendlyMessage(for: error)
        }
    }
}
