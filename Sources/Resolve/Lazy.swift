//
//  Lazy.swift
//  Resolve
//
//  Created by Dzmitry Letko on 26/08/2025.
//

import os.lock

public struct Lazy<Value: Sendable>: Sendable {
    private let state: OSAllocatedUnfairLock<State>
    
    public init(_ operation: @Sendable @escaping () -> Value) {
        state = .init(initialState: .loadable(operation))
    }
    
    public func callAsFunction() -> Value {
        state.withLock { state in
            switch state {
            case .loadable(let operation):
                let value = operation()
                
                state = .loaded(value)
                
                return value
                
            case .loaded(let value):
                return value
            }
        }
    }
}

// MARK: - private
private extension Lazy {
    enum State {
        case loadable(@Sendable () -> Value)
        case loaded(Value)
    }
}

