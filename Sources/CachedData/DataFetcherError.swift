//
//  DataFetcherError.swift
//  cached-data
//
//  Created by Kai Shao on 2025/6/5.
//

import ErrorKit

public enum DataFetcherError: Catching, Throwable {
    case noData, graphQLError([String]), caught(Error)
    
    public var userFriendlyMessage: String {
        switch self {
        case .noData:
            "没有获取到数据"
        case .graphQLError(let message):
            "GraphQL 错误: \(message)"
        case .caught(let error):
            error.localizedDescription
        }
    }
}
