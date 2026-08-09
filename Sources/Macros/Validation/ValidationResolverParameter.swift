//
//  ValidationResolverParameter.swift
//
//
//  Created by Dzmitry Letko on 09/08/2026.
//

enum ValidationResolverParameter {
    case count
    case type
    case syntax
}

extension ValidationResolverParameter {
    var message: String {
        switch self {
        case .count: "We do not expect any parameters except a single one of type `Resolver`"
        case .type: "The only parameter allowed here is of type `Resolver`"
        case .syntax: "The `Resolver` parameter must be declared with a plain name or `_` as its label"
        }
    }
}
