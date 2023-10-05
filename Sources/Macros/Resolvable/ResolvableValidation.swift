//
//  ResolvableValidation.swift
//
//
//  Created by Dzmitry Letko on 05/10/2023.
//

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacroExpansion
import Foundation

struct ResolvableValidation {
    let dependencies: [ResolvableBuilder.Dependency]
    
    func validate(in context: some MacroExpansionContext) {
        directUse(in: context)
        uniqueness(in: context)
    }
}

// MARK: - private
private extension ResolvableValidation {
    func uniqueness(in context: some MacroExpansionContext) {
        let dependenciesByName = Dictionary(grouping: dependencies) { dependency in
            dependency.name.text
        }
        
        for (name, dependencies) in dependenciesByName where dependencies.count >= 2 {
            // swiftlint:disable:next force_unwrapping
            let firstNode = Syntax(dependencies.first!.node)
            
            dependencies.dropFirst().forEach { dependency in
                let message = MacroExpansionErrorMessage("Invalid redeclaration of '\(name)'")
                let diagnostic = Diagnostic(
                    node: dependency.node,
                    message: message,
                    highlights: [firstNode]
                )
                
                context.diagnose(diagnostic)
            }
        }
    }
    
    func directUse(in context: some MacroExpansionContext) {
        dependencies.forEach { called in
            let node = Syntax(called.node)
            
            dependencies.forEach { calling in
                guard called.node != calling.node else { return }
                guard let block = calling.node.body else { return }
                guard let position = block.description.utf8.firstRange(of: "\(called.function.name)(".utf8) else { return }
                
                let message = MacroExpansionErrorMessage(
                    """
                    Do not call other dependency functions directly. Add `Resolver` parameter to your function and use it to get an access to resolved instance
                    """
                )
                let offset = block.description.utf8.distance(
                    from: block.description.utf8.startIndex,
                    to: position.lowerBound
                )
                let diagnostic = Diagnostic(
                    node: block,
                    position: block.position.advanced(by: offset),
                    message: message,
                    highlights: [node]
                )
                
                context.diagnose(diagnostic)
            }
        }
    }
}
