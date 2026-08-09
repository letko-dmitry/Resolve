//
//  ValidationMacroPlacement.swift
//
//
//  Created by Dzmitry Letko on 09/08/2026.
//

import SwiftSyntax
import SwiftSyntaxMacros
import SwiftDiagnostics

enum ValidationMacroPlacement {
    static func validate(attribute node: AttributeSyntax, declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) {
        guard declaration.is(FunctionDeclSyntax.self) else {
            let message = MacroExpansionErrorMessage("Only functions can be annotated with `\(node.attributeName.identifier)`")
            let diagnostic = Diagnostic(
                node: node,
                message: message
            )

            context.diagnose(diagnostic)

            return
        }

        guard let reason = misplacement(in: context.lexicalContext) else { return }

        let message = MacroExpansionWarningMessage("`\(node.attributeName.identifier)` has no effect here – \(reason)")
        let diagnostic = Diagnostic(
            node: node,
            message: message
        )

        context.diagnose(diagnostic)
    }
}

// MARK: - private
private extension ValidationMacroPlacement {
    static func misplacement(in lexicalContext: [Syntax]) -> String? {
        guard let enclosing = lexicalContext.first else {
            return "`@Resolvable` only inspects functions declared in the body of a class or a struct"
        }

        if enclosing.is(ExtensionDeclSyntax.self) {
            return "`@Resolvable` never sees members declared in an extension"
        }

        guard let group = enclosing.asProtocol((any DeclGroupSyntax).self) else {
            return "`@Resolvable` only inspects functions declared directly in the body of a class or a struct"
        }

        guard group.is(StructDeclSyntax.self) || group.is(ClassDeclSyntax.self) else {
            return "`@Resolvable` can only be attached to a class or a struct"
        }

        guard !group.resolvable else { return nil }

        return "the enclosing type is not annotated with `@Resolvable`"
    }
}

// MARK: - private
private extension DeclGroupSyntax {
    var resolvable: Bool {
        attributes.contains { element in
            element.as(AttributeSyntax.self)?.attributeName.identifier == "Resolvable"
        }
    }
}
