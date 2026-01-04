//
//  Lazy.swift
//  Resolve
//
//  Created by Dzmitry Letko on 26/08/2025.
//

import os.lock

public struct LazyThrowable<Value: Sendable>: Sendable {
    private let state: OSAllocatedUnfairLock<State>
    
    public init(_ operation: @Sendable @escaping () throws -> Value) {
        state = .init(initialState: .loadable(operation))
    }
    
    public func callAsFunction() throws -> Value {
        try state.withLock { state in
            switch state {
            case .loadable(let operation):
                let value = try operation()

                state = .loaded(value)
                
                return value
                
            case .loaded(let value):
                return value
            }
        }
    }
}

// MARK: - private
private extension LazyThrowable {
    enum State {
        case loadable(@Sendable () throws -> Value)
        case loaded(Value)
    }
}

