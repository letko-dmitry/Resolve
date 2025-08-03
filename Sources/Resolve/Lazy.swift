//
//  Lazy.swift
//  Resolve
//
//  Created by Dzmitry Letko on 10/02/2025.
//

public actor Lazy<Value: Sendable>: Sendable {
    private enum State {
        case resolvable(@Sendable () async -> Value)
        case resolving(Task<Value, Never>)
        case resolved(Value)
    }

    private var state: State
    
    public var value: Value {
        get async {
            switch state {
            case .resolvable(let resolvable):
                let task = Task(operation: resolvable)
                
                state = .resolving(task)
                
                let value = await task.value
                
                state = .resolved(value)
                
                return value
                
            case .resolving(let task):
                return await task.value
                
            case .resolved(let resolved):
                return resolved
            }
        }
    }
    
    public init(_ resolve: @Sendable @escaping () async -> Value) {
        state = .resolvable(resolve)
    }
    
    @inlinable
    public func callAsFunction() async -> Value {
        await value
    }
}

public actor LazyThrowable<Value: Sendable>: Sendable {
    private enum State {
        case resolvable(@Sendable () async throws -> Value)
        case resolving(Task<Value, any Error>)
        case resolved(Value)
    }

    private var state: State
    
    public var value: Value {
        get async throws {
            switch state {
            case .resolvable(let resolvable):
                let task = Task(operation: resolvable)
                
                state = .resolving(task)
                
                let value = try await task.value
                
                state = .resolved(value)
                
                return value
                
            case .resolving(let task):
                return try await task.value
                
            case .resolved(let resolved):
                return resolved
            }
        }
    }
    
    public init(_ resolve: @Sendable @escaping () async throws -> Value) {
        state = .resolvable(resolve)
    }
    
    @inlinable
    public func callAsFunction() async throws -> Value {
        try await value
    }
}
