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
    enum Kind {
        case standard
        case transient
        case hidden
    }

    let name: TokenSyntax?
    let options: ExprSyntax?
    let kind: Kind
}

extension RegisterAttribute {
    struct Candidate: AttributeCandidate {
        let kind: Kind
        let node: AttributeSyntax

        init?(node: AttributeSyntax) {
            switch node.attributeName.identifier {
            case "Register":
                kind = .standard

            case "RegisterTransient":
                kind = .transient

            case "Keep":
                kind = .hidden

            default:
                return nil
            }

            self.node = node
        }
    }

    static func parse(attributes: AttributeListSyntax, in context: some MacroExpansionContext) -> RegisterAttribute? {
        guard let candidate = Candidate.first(in: attributes, in: context) else { return nil }

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
            kind: candidate.kind
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
