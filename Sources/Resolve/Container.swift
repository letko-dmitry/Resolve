//
//  Container.swift
//
//
//  Created by Dzmitry Letko on 01/10/2023.
//

import Foundation

public actor Container {
    private var tasks: [String: Any] = [:]
    
    public init() { }
    
    public func register<V: Sendable>(for name: String, _ dependency: @escaping @Sendable () async throws -> V) async throws -> V {
        return try await findOrCreate(name: name) {
            Task(operation: dependency)
        }.value
    }
    
    public func register<V: Sendable>(for name: String, _ dependency: @escaping @Sendable () throws -> V) async throws -> V {
        return try await findOrCreate(name: name) {
            Task(operation: dependency)
        }.value
    }
    
    public func register<V: Sendable>(for name: String, _ dependency: @escaping @Sendable () async -> V) async -> V {
        return await findOrCreate(name: name) {
            Task(operation: dependency)
        }.value
    }
    
    public func register<V: Sendable>(for name: String, _ dependency: @escaping @Sendable () -> V) async -> V {
        return await findOrCreate(name: name) {
            Task(operation: dependency)
        }.value
    }
}

// MARK: - private
private extension Container {
    func findOrCreate<T>(name: String, task: () -> T) -> T {
        if let task = tasks[name] as? T {
            return task
        }
        
        let task = task()
        
        tasks[name] = task
        
        return task
    }
}
