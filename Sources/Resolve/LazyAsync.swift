//
//  LazyAsync.swift
//  Resolve
//
//  Created by Dzmitry Letko on 10/02/2025.
//

import os.lock

public final class LazyAsync<Value: Sendable>: Sendable {
    private let state: OSAllocatedUnfairLock<State>
    private var resolution: Resolution<Value, Never> {
        get async {
            state.withLock { current in
                switch current {
                case .resolvable(let resolvable):
                    let task = Lazy { [state] in
                        Task {
                            let value = await resolvable()
                            
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
        get async {
            await resolution.value
        }
    }
    
    @inlinable
    @inline(__always)
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
    
    public init(_ resolve: @Sendable @escaping () async -> Value) {
        state = .init(initialState: .resolvable(resolve))
    }
    
    @inlinable
    @inline(__always)
    @discardableResult
    public func resolve() async -> Value {
        await value
    }
    
    @inlinable
    @inline(__always)
    public func callAsFunction() async -> Value {
        await value
    }
}

// MARK: - private
private extension LazyAsync {
    enum State {
        case resolvable(@Sendable () async -> Value)
        case resolving(Lazy<Task<Value, Never>>)
        case resolved(Value)
    }
}
