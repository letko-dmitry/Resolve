//
//  LazyAsyncThrowable.swift
//  Resolve
//
//  Created by Dzmitry Letko on 04/08/2025.
//

import os.lock

public final class LazyAsyncThrowable<Value: Sendable>: Sendable {
    private let state: OSAllocatedUnfairLock<State>
    private var resolution: Resolution<Value, any Error> {
        get async {
            state.withLock { current in
                switch current {
                case .resolvable(let resolvable):
                    let task = Lazy { [state] in
                        Task {
                            let value = try await resolvable()
                            
                            state.withLock { state in
                                state = .resolved(value)
                            }
                            
                            return value
                        }
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
    public var valueUnwrapped: Value {
        valueIfResolved!
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
    @discardableResult
    public func resolve() async throws -> Value {
        try await value
    }
    
    @inlinable
    public func callAsFunction() async throws -> Value {
        try await value
    }
}

// MARK: - private
private extension LazyAsyncThrowable {
    enum State {
        case resolvable(@Sendable () async throws -> Value)
        case resolving(Lazy<Task<Value, any Error>>)
        case resolved(Value)
    }
}
