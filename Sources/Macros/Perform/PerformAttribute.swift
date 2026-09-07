//
//  PerformAttribute.swift
//
//
//  Created by Dzmitry Letko on 16/10/2023.
//

import SwiftSyntax
import SwiftSyntaxMacros
import SwiftDiagnostics

struct PerformAttribute {
    let options: ExprSyntax?
}

extension PerformAttribute {
    struct Candidate: AttributeCandidate {
        let node: AttributeSyntax

        init?(node: AttributeSyntax) {
            guard node.attributeName.identifier == "Perform" else { return nil }

            self.node = node
        }
    }

    static func parse(attributes: AttributeListSyntax, in context: some MacroExpansionContext) -> PerformAttribute? {
        guard let candidate = Candidate.first(in: attributes, in: context) else { return nil }

        let arguments = candidate.node.arguments?.as(LabeledExprListSyntax.self)

        return .init(options: arguments?.expression(name: "options"))
    }
}
