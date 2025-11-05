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
    static func parse(transient: Bool, arguments: AttributeSyntax.Arguments?) -> RegisterAttribute? {
        let arguments = arguments?.as(LabeledExprListSyntax.self)
        
        return .init(
            name: arguments?.string(name: "name").map(TokenSyntax.init(stringLiteral:)),
            options: arguments?.expression(name: "options"),
            transient: transient
        )
    }
    
    static func parse(_ node: AttributeSyntax) -> RegisterAttribute? {
        switch node.attributeName.description {
        case "Register":
            return .parse(transient: false, arguments: node.arguments)
            
        case "RegisterTransient":
            return .parse(transient: true, arguments: node.arguments)
            
        default:
            return nil
        }
    }
}

extension RegisterAttribute {
    struct Candidate {
        let attribute: RegisterAttribute
        let node: AttributeSyntax
        
        init?(node: AttributeSyntax) {
            guard let attribute = RegisterAttribute.parse(node) else { return nil }
            
            self.attribute = attribute
            self.node = node
        }
    }
    
    static func parse(attributes: AttributeListSyntax, in context: some MacroExpansionContext) -> RegisterAttribute? {
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
