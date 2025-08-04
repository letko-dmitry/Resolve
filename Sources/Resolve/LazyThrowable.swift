//
//  LazyThrowable.swift
//  Resolve
//
//  Created by Dzmitry Letko on 04/08/2025.
//

import os.lock

public final class LazyThrowable<Value: Sendable>: Sendable {
    private let state: OSAllocatedUnfairLock<State>
    private var resolution: Resolution {
        get async {
            state.withLock { current in
                switch current {
                case .resolvable(let resolvable):
                    let task = Task {
                        let value = try await resolvable()
                        
                        state.withLock { state in
                            state = .resolved(value)
                        }
                        
                        return value
                    }
                    
                    current = .resolving(task)
                    
                    return .task(task)
                    
                case .resolving(let task):
                    return .task(task)
                    
                case .resolved(let value):
                    return .value(value)
                }
            }
        }
    }
    
    public var value: Value {
        get async throws {
            try await resolution.value
        }
    }
    
    @inlinable
    public var valueUnwrapped: Value! {
        valueIfResolved
    }
    
    public var valueIfResolved: Value? {
        state.withLock { state in
            switch state {
            case .resolvable, .resolving: return nil
            case .resolved(let value): return value
            }
        }
    }
    
    public init(_ resolve: @Sendable @escaping () async throws -> Value) {
        state = .init(initialState: .resolvable(resolve))
    }
    
    @inlinable
    public func resolve() async throws -> Value {
        try await value
    }
    
    @inlinable
    public func callAsFunction() async throws -> Value {
        try await value
    }
}

// MARK: - private
private extension LazyThrowable {
    enum State {
        case resolvable(@Sendable () async throws -> Value)
        case resolving(Task<Value, any Error>)
        case resolved(Value)
    }
    
    enum Resolution {
        case value(Value)
        case task(Task<Value, any Error>)
        
        var value: Value {
            get async throws {
                switch self {
                case .task(let task): return try await task.value
                case .value(let value): return value
                }
            }
        }
    }
}
