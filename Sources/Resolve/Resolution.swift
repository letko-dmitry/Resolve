//
//  Resolution.swift
//  Resolve
//
//  Created by Dzmitry Letko on 26/08/2025.
//

@usableFromInline
enum Resolution<Value: Sendable, Failure: Error>: Sendable {
    // Resolved already.
    case value(Value)
    // To await, then – if `keep` is set – to keep the value in place of the task; otherwise another caller keeps it.
    // One case for both, so readers await once: every await costs each specialization a resume funclet.
    case task(Task<Value, Failure>, keep: Bool)
}

// Every `value` awaits its task through these. They are caller-isolated like it, so the hop back to the caller's
// executor after the `@concurrent` `Task.value` is emitted once here instead of in every specialization – and kept out
// of cross-module optimization, which would inline that hop back into each of them.
extension Resolution where Failure == Never {
    @_semantics("optimize.no.crossmodule")
    @usableFromInline
    static func value(of task: Task<Value, Never>) async -> Value {
        await task.value
    }
}

extension Resolution where Failure == any Error {
    @_semantics("optimize.no.crossmodule")
    @usableFromInline
    static func value(of task: Task<Value, any Error>) async throws -> Value {
        try await task.value
    }
}
