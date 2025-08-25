//
//  Resolution.swift
//  Resolve
//
//  Created by Dzmitry Letko on 26/08/2025.
//

enum Resolution<Value: Sendable, Failure: Error> {
    case value(Value)
    case task(OnDemand<Task<Value, Failure>>)
}

extension Resolution {
    var value: Value {
        get async throws {
            switch self {
            case .task(let task): return try await task().value
            case .value(let value): return value
            }
        }
    }
}

extension Resolution where Failure == Never {
    var value: Value {
        get async {
            switch self {
            case .task(let task): return await task().value
            case .value(let value): return value
            }
        }
    }
}
