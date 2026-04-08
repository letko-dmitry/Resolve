//
//  Lazy.swift
//  Resolve
//
//  Created by Dzmitry Letko on 26/08/2025.
//

import os.lock

/**
 A `Sendable`, thread-safe wrapper that defers a synchronous computation until
 the value is first requested and then memoises it.

 Think of `Lazy` as the value-type counterpart to Swift's `lazy var`, with two
 important upgrades:

 1. It is `Sendable`, so it can be stored on actors, captured by `@Sendable`
    closures, and shared between tasks.
 2. The first call is serialised by an `OSAllocatedUnfairLock`, so concurrent
    callers either run the operation exactly once or wait for the in-flight
    call to finish — whichever happens first.

 `Lazy` is intentionally limited to **synchronous, non-throwing** factories.
 If you need throwing or async semantics, reach for `LazyThrowable`,
 `LazyAsync` or `LazyAsyncThrowable`.

 ## Example

 ```swift
 // Storage handles that are cheap to declare but expensive to construct;
 // build each one on demand and only once.
 private let promptUsage = Lazy {
     WorkoutInsightsStorage<PromptUsage?>(fileName: "prompts-usage")
 }

 // Either form works — `callAsFunction` lets the call site read like a
 // computed property.
 let usage = promptUsage()
 ```

 - Note: Because the operation is invoked under a lock, it should be cheap and
   non-blocking. Performing long synchronous work inside the closure will
   stall every concurrent reader.
 */
public struct Lazy<Value: Sendable>: Sendable {
    private let state: OSAllocatedUnfairLock<State>
    
    /**
     Creates a `Lazy` value backed by the given factory.
     
     - Parameter operation: The closure that produces the value on the first
       call. It is captured `@Sendable` and stored until the first invocation,
       at which point it is replaced by the produced value and released.
     */
    public init(_ operation: @Sendable @escaping () -> Value) {
        state = .init(initialState: .loadable(operation))
    }
    
    /**
     Returns the cached value, computing it on the first call.
     
     This method is exposed via `callAsFunction`, so a `Lazy` instance can be
     read with bare parentheses (`promptUsage()`). Subsequent calls return
     the memoised value without re-running the factory.
     
     - Returns: The memoised value.
     */
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

