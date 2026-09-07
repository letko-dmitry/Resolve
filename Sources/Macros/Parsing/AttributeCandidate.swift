//
//  AttributeCandidate.swift
//
//
//  Created by Dzmitry Letko on 07/09/2026.
//

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

protocol AttributeCandidate {
    var node: AttributeSyntax { get }

    init?(node: AttributeSyntax)
}

extension AttributeCandidate {
    static func first(in attributes: AttributeListSyntax, in context: some MacroExpansionContext) -> Self? {
        let candidates = attributes.compactMap { element in
            element.as(AttributeSyntax.self).flatMap(Self.init(node:))
        }

        guard let candidate = candidates.first else { return nil }

        if candidates.count > 1 {
            let dropped = candidates.dropFirst().map { $0.node }
            let drop = Set(dropped)
            let new = attributes.filter { element in
                if let attribute = element.as(AttributeSyntax.self) {
                    return !drop.contains(attribute)
                } else {
                    return true
                }
            }

            let message = MacroExpansionWarningMessage("We do not expect more than one attribute – the first one is taken")
            let diagnostic = Diagnostic(
                node: candidate.node,
                message: message,
                highlights: dropped.map(Syntax.init),
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

        return candidate
    }
}
