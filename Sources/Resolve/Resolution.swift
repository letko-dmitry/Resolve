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
