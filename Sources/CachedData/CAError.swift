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
    
    case noData
    case serverFailure(String)
    case noMoreNextPage
    case maxPageReached
    case lastPageIsLoading
    case caught(Error)
    
    public var userNotable: Bool {
        switch self {
        case .noData: false
        case .serverFailure: true
        case .noMoreNextPage: false
        case .maxPageReached: true
        case .caught: true
        case .lastPageIsLoading: false
        }
    }
    
    public var userFriendlyMessage: String {
        switch self {
        case .noData:
            "没有获取到数据"
        case .serverFailure(let message):
            "服务器错误: \(message)"
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
