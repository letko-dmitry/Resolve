//
//  PerformAttribute.swift
//  
//
//  Created by Dzmitry Letko on 16/10/2023.
//

import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacroExpansion
import SwiftDiagnostics

struct PerformAttribute {
    let options: ExprSyntax?
}

extension PerformAttribute {
    static func parse(arguments: AttributeSyntax.Arguments?) -> PerformAttribute? {
        let arguments = arguments?.as(LabeledExprListSyntax.self)
        
        return .init(options: arguments?.expression(name: "options"))
    }
    
    static func parse(_ node: AttributeSyntax) -> PerformAttribute? {
        switch node.attributeName.description {
        case "Perform":
            return .parse(arguments: node.arguments)
            
        default:
            return nil
        }
    }
}

extension PerformAttribute {
    struct Candidate {
        let attribute: PerformAttribute
        let node: AttributeSyntax
        
        init?(node: AttributeSyntax) {
            guard let attribute = PerformAttribute.parse(node) else { return nil }
            
            self.attribute = attribute
            self.node = node
        }
    }
    
    static func parse(attributes: AttributeListSyntax, in context: some MacroExpansionContext) -> PerformAttribute? {
        let candidates = attributes.compactMap { element in
            element.as(AttributeSyntax.self).flatMap(Candidate.init(node:))
        }
        
        guard let candidate = candidates.first else { return nil }
        
        if candidates.count > 1 {
            let message = MacroExpansionWarningMessage("We do not expect more that one attribute – the first one is taken")
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
        
        return candidate.attribute
    }
}
