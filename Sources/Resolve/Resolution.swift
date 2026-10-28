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
    // To await; another caller keeps the value.
    case task(Task<Value, Failure>)
    // To await, then to keep the value in place of the task.
    case keep(Task<Value, Failure>)
}
