//
//  Resolution.swift
//  Resolve
//
//  Created by Dzmitry Letko on 26/08/2025.
//

enum Resolution<Value: Sendable, Failure: Error> {
    case value(Value)
    case task(Lazy<Task<Value, Failure>>)
}

// A `consuming` method rather than a `consuming get`: callers invoke it on the temporary `resolution`
// returns, and only a method call hands that temporary over as-is – a consuming getter copies it first.
extension Resolution {
    consuming func value() async throws -> Value {
        switch consume self {
        case .task(let task): return try await task().value
        case .value(let value): return value
        }
    }
}

extension Resolution where Failure == Never {
    consuming func value() async -> Value {
        switch consume self {
        case .task(let task): return await task().value
        case .value(let value): return value
        }
    }
}
