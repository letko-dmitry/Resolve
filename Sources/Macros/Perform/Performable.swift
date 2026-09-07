//
//  Performable.swift
//
//
//  Created by Dzmitry Letko on 16/10/2023.
//

import Foundation
import SwiftSyntax
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftSyntaxBuilder

struct Performables {
    let all: [Performable]

    init(all: [Performable], sort: Bool) {
        self.all = sort ? all.sorted(using: SortDescriptor(\.name.text)) : all
    }
}

struct Performable {
    struct Function {
        let name: TokenSyntax
        let parameter: ResolverParameter?
        let concurrent: Bool
        let throwable: Bool
    }

    let function: Function
    let attribute: PerformAttribute
    let node: FunctionDeclSyntax

    var name: TokenSyntax {
        function.name
    }
}

extension Performable {
    static func parse(function declaration: FunctionDeclSyntax, in context: some MacroExpansionContext) -> Performable? {
        guard let attribute = PerformAttribute.parse(attributes: declaration.attributes, in: context) else { return nil }
        guard let function = Function.parse(function: declaration, in: context) else { return nil }

        return .init(
            function: function,
            attribute: attribute,
            node: declaration
        )
    }
}

// MARK: - Performable.Function
extension Performable.Function {
    static func parse(function: FunctionDeclSyntax, in context: some MacroExpansionContext) -> Performable.Function? {
        let shapeOk = ValidationFunctionShape.validate(function, in: context)
        let returnOk: Bool

        if let returnClause = function.signature.returnClause, !returnClause.type.isVoid {
            returnOk = false

            let message = MacroExpansionErrorMessage("There must be no return type – use `@Register` to expose the produced value")
            let diagnostic = Diagnostic(
                node: returnClause,
                message: message
            )

            context.diagnose(diagnostic)
        } else {
            returnOk = true
        }

        let parameter = ResolverParameter.parse(parameters: function.signature.parameterClause.parameters, in: context)

        guard shapeOk, returnOk, parameter.valid else { return nil }

        return .init(
            name: function.name,
            parameter: parameter.parameter,
            concurrent: function.concurrent,
            throwable: function.throwable
        )
    }
}
