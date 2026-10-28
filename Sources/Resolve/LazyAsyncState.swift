//
//  LazyAsyncState.swift
//  Resolve
//
//  Created by Dzmitry Letko on 28/10/2026.
//

// The state of a lazily computed async value, shared by `LazyAsync`, `LazyAsyncThrowable`, `Registration` and
// `RegistrationThrowable`: the factory until the first call, then the `Task` running it, then the value it produced.
@usableFromInline
enum LazyAsyncState<Factory: Sendable, Value: Sendable, Failure: Error>: Sendable {
    case resolvable(Factory)
    // Started without anyone awaiting it yet.
    case started(Task<Value, Failure>)
    // Awaited by the caller that will keep its value.
    case resolving(Task<Value, Failure>)
    case resolved(Value)
}

extension LazyAsyncState {
    // Starts the factory's task unless something has started it already.
    @inlinable
    mutating func start(_ start: (Factory) -> Task<Value, Failure>) {
        switch self {
        case .resolvable(let factory): self = .started(start(factory))
        case .started, .resolving, .resolved: break
        }
    }

    // The value, or the task to await for it. Only the first caller to await the task is told to keep its value, so
    // the state is written once – by that caller, outside the lock, never by the task itself: an executor may run a
    // new task in place, while the lock is still held, and the task taking the lock again would deadlock.
    @inlinable
    mutating func resolution(_ start: (Factory) -> Task<Value, Failure>) -> Resolution<Value, Failure> {
        switch self {
        case .resolvable(let factory):
            let task = start(factory)

            self = .resolving(task)

            return .keep(task)

        case .started(let task):
            self = .resolving(task)

            return .keep(task)

        case .resolving(let task):
            return .task(task)

        case .resolved(let value):
            return .value(value)
        }
    }

    @inlinable
    var value: Value? {
        switch self {
        case .resolvable, .started, .resolving: nil
        case .resolved(let value): value
        }
    }
}
