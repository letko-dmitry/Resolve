//
//  LazyThrowable.swift
//  Resolve
//
//  Created by Dzmitry Letko on 26/08/2025.
//

import os.lock

/**
 A `Sendable`, thread-safe wrapper that defers a throwing synchronous
 computation until the value is first requested and then memoises it.

 `LazyThrowable` is the throwing twin of `Lazy`. The factory is allowed to
 throw, and the error is propagated to the caller. **Failures are not
 cached** — if the closure throws, the next call retries from scratch. This
 is intentional: throwing usually indicates a recoverable I/O or parsing
 problem, and forcing every subsequent caller to inherit the same error
 would be both surprising and useless.

 Use `LazyThrowable` when:

 - the value is built from disk / decoder / parser output that may fail, and
 - you want subsequent calls to *retry* until the resource becomes available.

 If you need async semantics on top of throwing, use `LazyAsyncThrowable`.

 ## Example

 ```swift
 private let exerciseBundle = LazyThrowable {
     try ExerciseImportableBundleReader().read()
 }

 // First call may throw; later calls return the cached bundle.
 let bundle = try exerciseBundle()
 ```

 - Note: The factory runs under an unfair lock. Keep it cheap.
 */
public struct LazyThrowable<Value: Sendable>: Sendable {
    private let state: OSAllocatedUnfairLock<State>
    
    /**
     Creates a `LazyThrowable` value backed by the given throwing factory.
     
     - Parameter operation: The closure that produces the value on the first
       successful call. Captured `@Sendable`. The closure is *not* discarded
       on failure, so subsequent calls retry the same operation.
     */
    public init(_ operation: @Sendable @escaping () throws -> Value) {
        state = .init(initialState: .loadable(operation))
    }
    
    /**
     Returns the cached value, computing it on the first successful call.
     
     If the factory throws, the cache is left untouched and the error is
     re-thrown to the caller. Subsequent calls retry until the factory
     succeeds.
     
     - Returns: The memoised value.
     - Throws: Whatever the underlying factory throws.
     */
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
