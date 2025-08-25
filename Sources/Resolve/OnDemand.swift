//
//  OnDemand.swift
//  Resolve
//
//  Created by Dzmitry Letko on 26/08/2025.
//

import os.lock

struct OnDemand<Value: Sendable> {
    private let state: OSAllocatedUnfairLock<State>
    
    init(_ operation: @Sendable @escaping () -> Value) {
        state = .init(initialState: .loadable(operation))
    }
    
    func callAsFunction() -> Value {
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
private extension OnDemand {
    enum State {
        case loadable(@Sendable () -> Value)
        case loaded(Value)
    }
}

