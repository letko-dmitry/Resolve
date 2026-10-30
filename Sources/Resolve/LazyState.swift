//
//  LazyState.swift
//  Resolve
//
//  Created by Dzmitry Letko on 30/10/2026.
//

// The state of a lazily computed synchronous value: the operation until it first returns, then the value it returned.
// Shared by `Lazy` and `LazyThrowable`, so that every app carries the value witnesses of one generic enum, not two.
@usableFromInline
enum LazyState<Operation: Sendable, Value: Sendable>: Sendable {
    case loadable(Operation)
    case loaded(Value)
}
