//
//  LazyAsync.swift
//  Resolve
//
//  Created by Dzmitry Letko on 10/02/2025.
//

import os.lock

/**
 A `Sendable`, single-flight, async lazy value.

 `LazyAsync` defers a non-throwing async computation until the first
 `await`, runs it inside a single shared `Task`, then memoises the resulting
 value. Concurrent callers that hit the `LazyAsync` while the computation is
 still in flight all `await` the same `Task` rather than starting a new one.
 Once the value lands, every later access returns it synchronously through
 the lock.

 Internally there are three states:

 - **resolvable** — the factory has not been called yet.
 - **resolving** — a `Task` is in flight; new callers join it.
 - **resolved** — the value has been computed and is cached forever.

 Use `LazyAsync` when:

 - resolution is asynchronous and **cannot** fail (or you have already
   neutralised the failures inside the closure), and
 - you need many callers to share a single in-flight computation.

 If you need throwing semantics, use `LazyAsyncThrowable`. For synchronous
 lazy values, see `Lazy` / `LazyThrowable`.

 ## Example

 ```swift
 // Top-level application graph: build the resolver exactly once on first use.
 enum AssemblyResolver {
     static let essential = AssemblyEssential()
     static let application = LazyAsync { @concurrent in
         await AssemblyApplication.Resolver(.init(essential: essential)).resolve()
     }
 }

 // Inside a presenter / coordinator:
 let resolved = await AssemblyResolver.application.value
 // …or, equivalently:
 let resolved = await AssemblyResolver.application()
 ```

 - Note: The internal lock is only held briefly to enqueue the resolving
   `Task` and to publish the cached value. The factory itself runs **outside**
   the lock, inside its own `Task`, so a long-running async factory does not
   block other callers from acquiring the lock — they will simply join the
   in-flight task.
 */
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
    
    /**
     The resolved value, computing it on the first access.
     
     The first caller starts a `Task`; concurrent callers join the same
     in-flight `Task` and return as soon as it produces a value. Subsequent
     accesses skip the `Task` entirely and return the cached value.
     */
    public var value: Value {
        get async {
            await resolution.value
        }
    }
    
    /**
     Returns the resolved value, force-unwrapping it.

     - Warning: Crashes with a fatal error if resolution has not yet
       completed. Use this only when you can prove that `resolve()` has
       already returned — for example, after a deliberate prior `await` on
       the same instance, or from a code path that runs strictly after a
       successful application bootstrap. Reach for `valueIfResolved` whenever
       you are not certain.
     */
    @inlinable
    @inline(__always)
    public var valueUnwrapped: Value {
        valueIfResolved!
    }
    
    /**
     Returns the resolved value if it is already cached, otherwise `nil`.
     
     This is a non-blocking peek: it never starts the resolution `Task` and
     never waits. Useful when you want to read the value if it is ready
     without forcing resolution from a synchronous context.
     */
    public var valueIfResolved: Value? {
        state.withLock { state in
            switch state {
            case .resolvable, .resolving: return nil
            case .resolved(let value): return value
            }
        }
    }
    
    /**
     Creates a `LazyAsync` value backed by the given async factory.
     
     - Parameter resolve: The closure that produces the value on the first
       `await`. Captured `@Sendable`. The closure runs at most once.
     */
    public init(_ resolve: @Sendable @escaping () async -> Value) {
        state = .init(initialState: .resolvable(resolve))
    }
    
    /**
     Forces resolution and returns the value.
     
     Equivalent to `await value`, but spelled as a method so it reads
     naturally as an explicit "kick off the work now" call site (for
     example inside an application launch task). The `@discardableResult`
     attribute lets callers ignore the value when they only care about the
     side effect of triggering resolution.
     
     - Returns: The resolved value.
     */
    @inlinable
    @inline(__always)
    @discardableResult
    public func resolve() async -> Value {
        await value
    }
    
    /**
     Convenience that lets a `LazyAsync` instance be invoked like a function.

     ```swift
     // these two lines are equivalent
     let resolved = await container()
     let resolved = await container.value
     ```

     - Returns: The resolved value.
     */
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
