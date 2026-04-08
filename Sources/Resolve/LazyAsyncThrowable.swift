//
//  LazyAsyncThrowable.swift
//  Resolve
//
//  Created by Dzmitry Letko on 04/08/2025.
//

import os.lock

/**
 A `Sendable`, single-flight, async lazy value whose factory is allowed to
 throw.

 `LazyAsyncThrowable` is the throwing twin of `LazyAsync`. It defers an
 async factory until the first `try await`, runs it inside a single shared
 `Task`, and memoises the resulting value. Concurrent callers join the same
 in-flight `Task`.

 ## Failure semantics

 If the factory throws, **the produced `Task` carries that error and is
 cached** for the lifetime of the `LazyAsyncThrowable` instance. Every later
 caller will re-throw the same error rather than retrying the factory. This
 is the right default for cases like "set up a long-lived dependency that
 either succeeds permanently or fails permanently".

 If you want retry-on-failure semantics, either build the retry logic
 *inside* the factory closure, or store the `LazyAsyncThrowable` behind a
 lock-protected `var` and replace the whole instance to reset it. The
 factory shown as `connect()` here must be a free function or a static
 method because stored-property initializers cannot reference `self`. Read
 the current instance out of the lock before awaiting it — never call
 `resolve()` under `withLock`, because that would serialise every caller
 on the unfair lock for the entire duration of the async factory.

 ```swift
 private let activation = OSAllocatedUnfairLock<LazyAsyncThrowable<Void>>(
     initialState: .init { try await connect() }
 )

 func activate() async throws {
     // Snapshot the current instance under the lock, await outside of it.
     let current = activation.withLock { $0 }
     try await current.resolve()
 }

 func reactivate() {
     activation.withLock { current in
         current = .init { try await connect() }
     }
 }
 ```

 ## Example

 ```swift
 // Top of the application graph: build the system resolver exactly once,
 // and propagate failures to whoever awaits it first.
 enum AssemblyResolver {
     static let essential = AssemblyEssential()
     static let system = LazyAsyncThrowable { @concurrent in
         try await AssemblySystem.Resolver(.init(essential: essential)).resolve()
     }
 }

 // Inside a launch task:
 do {
     try await AssemblyResolver.system.resolve()
 } catch {
     // handle bootstrap failure
 }
 ```

 - Note: The internal lock is only held briefly to enqueue the resolving
   `Task` and to publish the cached value. The factory itself runs **outside**
   the lock, inside its own `Task`, so a long-running async factory does not
   block other callers from acquiring the lock — they will simply join the
   in-flight task. If that task ultimately throws, the failure is cached
   (see Failure semantics above).
 */
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
    
    /**
     The resolved value, computing it on the first access.
     
     The first caller starts a `Task`; concurrent callers join the same
     in-flight `Task` and either receive the value or re-throw the same
     error. Once the value is cached, every later access returns it
     synchronously through the lock.
     
     - Throws: Whatever the underlying factory throws on its first call.
       The error is *cached*: subsequent accesses re-throw it without
       retrying.
     */
    public var value: Value {
        get async throws {
            try await resolution.value
        }
    }
    
    /**
     Returns the resolved value, force-unwrapping it.

     - Warning: Crashes with a fatal error if resolution has not yet
       completed *successfully*. Use this only when you can prove that
       `resolve()` has already returned without throwing — for example from
       a code path that runs strictly after a successful application
       bootstrap, or after a deliberate prior `try await` on the same
       instance. Reach for `valueIfResolved` whenever you are not certain.
     */
    @inlinable
    @inline(__always)
    public var valueUnwrapped: Value {
        valueIfResolved!
    }
    
    /**
     Returns the resolved value if it is already cached, otherwise `nil`.
     
     This is a non-blocking peek: it never starts the resolution `Task`,
     never waits, and never throws. If resolution previously failed the
     instance is still considered "not resolved", so this property keeps
     returning `nil` and the cached error remains accessible only through
     `value` / `resolve()`.
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
     Creates a `LazyAsyncThrowable` value backed by the given throwing
     async factory.
     
     - Parameter resolve: The closure that produces the value on the first
       `try await`. Captured `@Sendable`. The closure runs at most once;
       any error it throws is cached and re-thrown to subsequent callers.
     */
    public init(_ resolve: @Sendable @escaping () async throws -> Value) {
        state = .init(initialState: .resolvable(resolve))
    }
    
    /**
     Forces resolution and returns the value.
     
     Equivalent to `try await value`, but spelled as a method so it reads
     naturally as an explicit "kick off the work now" call site (for
     example inside an application launch task). The `@discardableResult`
     attribute lets callers ignore the value when they only care about
     the side effect of triggering resolution.
     
     - Returns: The resolved value.
     - Throws: The error produced by the factory on its first call. The
       same error is re-thrown on every subsequent invocation; the factory
       is *not* retried.
     */
    @inlinable
    @inline(__always)
    @discardableResult
    public func resolve() async throws -> Value {
        try await value
    }
    
    /**
     Convenience that lets a `LazyAsyncThrowable` instance be invoked like
     a function.

     ```swift
     // these two lines are equivalent
     let resolved = try await container()
     let resolved = try await container.value
     ```

     - Returns: The resolved value.
     - Throws: The error produced by the factory on its first call. The same
       error is re-thrown on every subsequent invocation; the factory is
       *not* retried.
     */
    @inlinable
    @inline(__always)
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
