//
//  LabeledExprListSyntax.swift
//
//
//  Created by Dzmitry Letko on 16/10/2023.
//

import SwiftSyntax
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftParser

extension LabeledExprListSyntax {
    func expression(name: String) -> ExprSyntax? {
        first { $0.label?.text == name }?.expression
    }

    // swiftlint:disable:next discouraged_optional_boolean - nil distinguishes an absent argument from `false`
    func bool(name: String) -> Bool? {
        (expression(name: name)?.as(BooleanLiteralExprSyntax.self)?.literal.text).flatMap(Bool.init(_:))
    }

    func string(name: String) -> String? {
        expression(name: name)?.as(StringLiteralExprSyntax.self)?.representedLiteralValue
    }
}

extension LabeledExprListSyntax {
    func bool(name: String, default fallback: Bool, in context: some MacroExpansionContext) -> Bool {
        literal(name: name, kind: "a boolean literal", in: context) { $0.bool(name: name) } ?? fallback
    }

    func string(name: String, in context: some MacroExpansionContext) -> String? {
        literal(name: name, kind: "a string literal", in: context) { $0.string(name: name) }
    }
}

// MARK: - private
private extension LabeledExprListSyntax {
    func literal<Value>(name: String, kind: String, in context: some MacroExpansionContext, parse: (Self) -> Value?) -> Value? {
        guard let expression = expression(name: name) else { return nil }
        guard let value = parse(self) else {
            let message = MacroExpansionWarningMessage("`\(name):` is ignored – it must be \(kind) known at compile time")
            let diagnostic = Diagnostic(
                node: expression,
                message: message
            )

            context.diagnose(diagnostic)

            return nil
        }

        return value
    }
}
