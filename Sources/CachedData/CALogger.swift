//
//  CALogger.swift
//  cached-data
//
//  Created by Kai Shao on 2025/6/8.
//

import Dependencies
import ErrorKit

public protocol CALogger: Sendable {
    func info(_ message: String, _ info: [String: String])
    func error(_ message: String, _ info: [String: String])
}

extension CALogger {
    func info(_ message: String) {
        info(message, [:])
    }
    
    func error(_ message: String) {
        error(message, [:])
    }
    
    func error(_ err: Error) {
        error(ErrorKit.userFriendlyMessage(for: err), [
            "trace": "\(ErrorKit.errorChainDescription(for: err))"
        ])
    }
}

public struct CALoggerPlaceholder: CALogger {
    public func info(_ message: String, _ info: [String: String]) {
//        fatalError("unimplemented")
    }
    
    public func error(_ message: String, _ info: [String: String]) {
//        fatalError("unimplemented")
    }
}

private enum LoggerKey: DependencyKey {
    static let liveValue: any CALogger = CALoggerPlaceholder()
}

public extension DependencyValues {
    var caLogger: CALogger {
        get { self[LoggerKey.self] }
        set { self[LoggerKey.self] = newValue }
    }
}
