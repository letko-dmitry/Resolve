//
//  Registration.swift
//
//
//  Created by Dzmitry Letko on 28/10/2026.
//

public import os.lock

/**
 A non-throwing registration of a generated `Resolver`: a lazy async value
 whose factory is handed the resolver.

 Like `LazyAsync`, it runs its factory at most once, in a `Task` that callers
 share, and keeps the value once the task has produced it, so the task itself
 can be freed. Each registration has a lock of its own, so registrations never
 wait for one another.

 Generated code declares one per `Register`, `RegisterTransient`, `Keep` and
 `Perform` whose function does not throw, as a stored property of the
 resolver's `Registrations`. You should not create one from hand-written code.
 */
public struct Registration<R: Sendable, V: Sendable>: Sendable {
    @usableFromInline typealias Factory = @Sendable (R) async -> V
    @usableFromInline typealias State = LazyAsyncState<Factory, V, Never>

    @usableFromInline let once: Bool
    @usableFromInline let state: OSAllocatedUnfairLock<State>

    /**
     Creates a registration that has not started yet.

     - Parameters:
        - options: Cache scope. `Options.once` makes every `Resolver` of the
          container share the process-wide copy of the registration.
        - make: The factory. It is handed the resolver when its task starts.
     */
    @export(implementation)
    public init(options: Registrar.Options = .default, _ make: @escaping @Sendable (R) async -> V) {
        self.once = options.once
        self.state = OSAllocatedUnfairLock(initialState: .resolvable(make))
    }

    /**
     Starts the factory unless it has started already, without waiting for it.

     The generated `resolve()` starts every registration before it awaits any
     of them, so the whole graph is in flight at once.

     - Parameter resolver: The generated `Resolver`, handed to the factory.
     */
    @export(implementation)
    public func start(_ resolver: R) {
        state.withLock { state in
            state.start { make in
                Self.task(make, resolver)
            }
        }
    }

    /**
     Returns the value, starting the factory on the first call. Concurrent
     callers share a single in-flight task.

     - Parameter resolver: The generated `Resolver`, handed to the factory.
       Passing it instead of capturing it keeps the factories free of captures,
       so creating the registrations allocates no closure.
     - Returns: The value the factory produced.
     */
    @export(implementation)
    public func value(_ resolver: R) async -> V {
        switch resolution(resolver) {
        case .value(let value):
            return value

        case .task(let task):
            return await task.value

        case .keep(let task):
            let value = await task.value

            state.withLock { state in
                state = .resolved(value)
            }

            return value
        }
    }

    @inlinable
    func resolution(_ resolver: R) -> Resolution<V, Never> {
        state.withLock { state in
            state.resolution { make in
                Self.task(make, resolver)
            }
        }
    }
}

// Deliberately not inlinable: the inlined lookup only calls in here on the first access, so the generic `Task`
// creation – with its reabstraction thunks – is emitted once in this module instead of in every registration.
extension Registration {
    @usableFromInline
    static func task(_ make: @escaping Factory, _ resolver: R) -> Task<V, Never> {
        Task {
            await make(resolver)
        }
    }
}
