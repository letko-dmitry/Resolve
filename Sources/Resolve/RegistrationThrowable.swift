//
//  RegistrationThrowable.swift
//
//
//  Created by Dzmitry Letko on 28/10/2026.
//

public import os.lock

/**
 A throwing registration of a generated `Resolver`: a lazy async value whose
 factory is handed the resolver.

 The throwing twin of `Registration`. A failure is cached like a value: the
 failed task stays, and every later access rethrows its error rather than
 running the factory again.
 */
public struct RegistrationThrowable<R: Sendable, V: Sendable>: Sendable {
    // `@concurrent` for the same reason as `Registration.Factory`.
    @usableFromInline typealias Factory = @concurrent @Sendable (R) async throws -> V
    @usableFromInline typealias State = LazyAsyncState<Factory, V, any Error>

    @usableFromInline let once: Bool
    @usableFromInline let state: OSAllocatedUnfairLock<State>

    /**
     Creates a registration that has not started yet.

     - Parameters:
        - options: Cache scope. `Options.once` makes every `Resolver` of the
          container share the process-wide registration.
        - make: The factory. It is handed the resolver when its task starts.
     */
    @export(implementation)
    public init(options: Registrar.Options = .default, _ make: @escaping @concurrent @Sendable (R) async throws -> V) {
        self.once = options.once
        self.state = OSAllocatedUnfairLock(initialState: .resolvable(make))
    }

    /**
     Starts the factory unless it has started already, without waiting for it.

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
     - Returns: The value the factory produced.
     - Throws: The error the factory threw. It is cached: later calls rethrow it
       without running the factory again.
     */
    @export(implementation)
    public func value(_ resolver: R) async throws -> V {
        switch resolution(resolver) {
        case .value(let value):
            return value

        case .task(let task, let keep):
            let value = try await task.value

            if keep {
                state.withLock { state in
                    state = .resolved(value)
                }
            }

            return value
        }
    }

    @inlinable
    func resolution(_ resolver: R) -> Resolution<V, any Error> {
        state.withLock { state in
            state.resolution { make in
                Self.task(make, resolver)
            }
        }
    }
}

// Deliberately not inlinable: the inlined lookup only calls in here on the first access, so the generic `Task`
// creation – with its reabstraction thunks – is emitted once in this module instead of in every registration.
extension RegistrationThrowable {
    @usableFromInline
    static func task(_ make: @escaping Factory, _ resolver: R) -> Task<V, any Error> {
        Task {
            try await make(resolver)
        }
    }
}
