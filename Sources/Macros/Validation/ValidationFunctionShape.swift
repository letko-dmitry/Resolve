//
//  ValidationFunctionShape.swift
//
//
//  Created by Dzmitry Letko on 09/08/2026.
//

import SwiftSyntax
import SwiftSyntaxMacros
import SwiftDiagnostics

enum ValidationFunctionShape {
    static func validate(_ function: FunctionDeclSyntax, in context: some MacroExpansionContext) -> Bool {
        var valid = true

        if let modifier = function.unsupportedModifier {
            let message = MacroExpansionErrorMessage("A dependency function must be an instance method – `\(modifier.name.trimmed)` is not supported")
            let diagnostic = Diagnostic(
                node: modifier,
                message: message
            )

            context.diagnose(diagnostic)

            valid = false
        }

        if function.generic {
            let node = function.genericParameterClause.map(Syntax.init) ?? function.genericWhereClause.map(Syntax.init) ?? Syntax(function.name)
            let message = MacroExpansionErrorMessage("A dependency function must not be generic – its return type becomes a stored property of `Resolved`")
            let diagnostic = Diagnostic(
                node: node,
                message: message
            )

            context.diagnose(diagnostic)

            valid = false
        }

        return valid
    }
}
