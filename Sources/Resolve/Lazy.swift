//
//  Lazy.swift
//  Resolve
//
//  Created by Dzmitry Letko on 10/02/2025.
//

import os.lock

public final class Lazy<Value: Sendable>: Sendable {
    private let state: OSAllocatedUnfairLock<State>
    private var resolution: Resolution<Value, Never> {
        get async {
            state.withLock { current in
                switch current {
                case .resolvable(let resolvable):
                    let task = OnDemand { [state] in
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
    @discardableResult
    public func resolve() async -> Value {
        await value
    }
    
    @inlinable
    public func callAsFunction() async -> Value {
        await value
    }
}

// MARK: - private
private extension Lazy {
    enum State {
        case resolvable(@Sendable () async -> Value)
        case resolving(OnDemand<Task<Value, Never>>)
        case resolved(Value)
    }
}
