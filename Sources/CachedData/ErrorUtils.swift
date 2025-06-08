//
//  ErrorUtils.swift
//  cached-data
//
//  Created by Kai Shao on 2025/6/8.
//

import ErrorKit

extension Catching {
    static func `catch`<T: Catching, ReturnType>(_ operation: () async throws -> ReturnType, mapTo type: @Sendable (Self) -> T) async throws(T) -> ReturnType {
        do {
           return try await operation()
        } catch let error as T {
           throw error
        } catch let error as Self {
            throw type(error)
        } catch {
            throw .caught(error)
        }
    }
}
