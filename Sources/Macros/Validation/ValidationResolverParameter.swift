//
//  ValidationResolverParameter.swift
//
//
//  Created by Dzmitry Letko on 09/08/2026.
//

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

struct ResolverParameter {
    let label: TokenSyntax?
}

extension ResolverParameter {
    struct Parsed {
        let parameter: ResolverParameter?
        let valid: Bool

        // Only the factories below may build this – a parameter paired with `valid: false` is not a state we produce.
        private init(parameter: ResolverParameter?, valid: Bool) {
            self.parameter = parameter
            self.valid = valid
        }
    }

    static func parse(parameters: FunctionParameterListSyntax, of enclosing: TokenSyntax, in context: some MacroExpansionContext) -> Parsed {
        guard let first = parameters.first else { return .absent }
        guard parameters.count == 1 else { return .invalid(.count, node: parameters, in: context) }
        guard first.type.isResolver(of: enclosing) else { return .invalid(.type, node: first, in: context) }

        switch first.firstName.tokenKind {
        case .wildcard:
            return .present(.init(label: nil))

        case let .identifier(identifier):
            return .present(.init(label: .init(stringLiteral: identifier)))

        default:
            return .invalid(.syntax, node: first.firstName, in: context)
        }
    }
}

// MARK: - ResolverParameter.Invalid
extension ResolverParameter {
    enum Invalid {
        case count
        case type
        case syntax
    }
}

extension ResolverParameter.Invalid {
    var message: String {
        switch self {
        case .count: "We do not expect any parameters except a single one of type `Resolver`"
        case .type: "The only parameter allowed here is of type `Resolver`"
        case .syntax: "The `Resolver` parameter must be declared with a plain name or `_` as its label"
        }
    }
}

// MARK: - private
private extension ResolverParameter.Parsed {
    static let absent = Self(parameter: nil, valid: true)

    static func present(_ parameter: ResolverParameter) -> Self {
        .init(parameter: parameter, valid: true)
    }

    static func invalid(_ invalid: ResolverParameter.Invalid, node: some SyntaxProtocol, in context: some MacroExpansionContext) -> Self {
        let message = MacroExpansionErrorMessage(invalid.message)
        let diagnostic = Diagnostic(
            node: node,
            message: message
        )

        context.diagnose(diagnostic)

        return .init(parameter: nil, valid: false)
    }
}
