//
//  RegisterAttribute.swift
//
//
//  Created by Dzmitry Letko on 16/10/2023.
//

import SwiftSyntax
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftSyntaxBuilder

struct RegisterAttribute {
    let name: TokenSyntax?
    let options: ExprSyntax?
    let transient: Bool
}

extension RegisterAttribute {
    struct Candidate {
        let transient: Bool
        let node: AttributeSyntax

        init?(node: AttributeSyntax) {
            switch node.attributeName.identifier {
            case "Register":
                transient = false

            case "RegisterTransient":
                transient = true

            default:
                return nil
            }

            self.node = node
        }
    }

    static func parse(attributes: AttributeListSyntax, in context: some MacroExpansionContext) -> RegisterAttribute? {
        let candidates = attributes.compactMap { element in
            element.as(AttributeSyntax.self).flatMap(Candidate.init(node:))
        }

        guard let candidate = candidates.first else { return nil }

        if candidates.count > 1 {
            let message = MacroExpansionWarningMessage("We do not expect more than one attribute – the first one is taken")
            let drop = Set(candidates.dropFirst().map { $0.node })
            let new = attributes.filter { element in
                if let attribute = element.as(AttributeSyntax.self) {
                    return !drop.contains(attribute)
                } else {
                    return true
                }
            }

            let diagnostic = Diagnostic(
                node: candidate.node,
                message: message,
                highlights: drop.map { Syntax($0) },
                fixIt: .init(
                    message: MacroExpansionFixItMessage("Remove unused attributes"),
                    changes: [
                        .replace(
                            oldNode: Syntax(attributes),
                            newNode: Syntax(new)
                        )
                    ]
                )
            )

            context.diagnose(diagnostic)
        }

        return parse(candidate: candidate, in: context)
    }
}

// MARK: - private
private extension RegisterAttribute {
    static func parse(candidate: Candidate, in context: some MacroExpansionContext) -> RegisterAttribute {
        let arguments = candidate.node.arguments?.as(LabeledExprListSyntax.self)

        return .init(
            name: name(in: arguments, in: context),
            options: arguments?.expression(name: "options"),
            transient: candidate.transient
        )
    }

    static func name(in arguments: LabeledExprListSyntax?, in context: some MacroExpansionContext) -> TokenSyntax? {
        guard let name = arguments?.string(name: "name", in: context) else { return nil }
        guard name.isSwiftIdentifier else {
            let message = MacroExpansionErrorMessage("'\(name)' is not a valid identifier – it is used as the name of a property on `Resolved` and `Resolver`")
            let diagnostic = Diagnostic(
                node: arguments?.expression(name: "name") ?? ExprSyntax(StringLiteralExprSyntax(content: name)),
                message: message
            )

            context.diagnose(diagnostic)

            return nil
        }

        return .init(stringLiteral: name)
    }
}
