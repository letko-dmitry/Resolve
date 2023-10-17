//
//  ResolvableValidation.swift
//
//
//  Created by Dzmitry Letko on 05/10/2023.
//

import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacroExpansion

struct ResolvableValidation {
    let registrables: [Registrable]
    let performables: [Performable]
    
    func validate(in context: some MacroExpansionContext) {
        DirectUseReport.make(registrables: registrables, performables: performables).print(in: context)
        UniquenessReport.make(registrables: registrables, performables: performables).print(in: context)
    }
}

// MARK: - UniquenessReport
private extension ResolvableValidation {
    struct UniquenessReport {
        struct Candidate {
            let name: TokenSyntax
            let node: FunctionDeclSyntax
            
            init(_ registrable: Registrable) {
                node = registrable.node
                name = registrable.name
            }
            
            init(_ performable: Performable) {
                node = performable.node
                name = performable.name
            }
        }
        
        struct Case {
            let first: Candidate
            let redeclarations: [Candidate]
        }
        
        let cases: [Case]
        
        static func make(registrables: [Registrable], performables: [Performable]) -> UniquenessReport {
            let candidates = registrables.map(Candidate.init(_:)) + performables.map(Candidate.init(_:))
            let candidatesByName = Dictionary(grouping: candidates) { $0.name.text }
            let cases: [Case] = candidatesByName.compactMap { _, candidates in
                guard let first = candidates.first, candidates.count >= 2 else { return nil }
                
                return Case(
                    first: first,
                    redeclarations: Array(candidates.dropFirst())
                )
            }
            
            return .init(cases: cases)
        }
        
        func print(in context: some MacroExpansionContext) {
            cases.forEach { uniquenessCase in
                let firstNode = Syntax(uniquenessCase.first.node)
                let message = MacroExpansionErrorMessage("Invalid redeclaration of '\(uniquenessCase.first.name)'")
                
                uniquenessCase.redeclarations.forEach { redeclaration in
                    let highlights = [Syntax(redeclaration.node), firstNode]
                    let diagnostic = Diagnostic(
                        node: redeclaration.node,
                        message: message,
                        highlights: highlights
                    )
                    
                    context.diagnose(diagnostic)
                }
            }
        }
    }
}

// MARK: - DirectUseReport
private extension ResolvableValidation {
    struct DirectUseReport {
        struct Candidate {
            let name: TokenSyntax
            let node: FunctionDeclSyntax
            let concurrent: Bool
            
            init(_ registrable: Registrable) {
                node = registrable.node
                name = registrable.function.name
                concurrent = registrable.function.concurrent
            }
            
            init(_ performable: Performable) {
                node = performable.node
                name = performable.function.name
                concurrent = performable.function.concurrent
            }
        }
        
        struct Case {
            struct Misuse {
                let function: FunctionCallExprSyntax
                let concurrent: Bool
            }
            
            let calling: Candidate
            let called: Candidate
            let misuses: [Misuse]
        }
        
        let cases: [Case]
        
        static func make(registrables: [Registrable], performables: [Performable]) -> DirectUseReport {
            let candidates = registrables.map(Candidate.init(_:)) + performables.map(Candidate.init(_:))
            let cases: [Case] = candidates.flatMap { called in
                let sign = "\(called.name)(".utf8
                
                return candidates.compactMap { calling -> Case? in
                    guard called.node != calling.node else { return nil }
                    guard let callingCode = calling.node.body else { return nil }
                    
                    let callingCodeText = callingCode.description.utf8
                    let misuses: [Case.Misuse] = callingCodeText.ranges(of: sign).compactMap { range in
                        let offset = callingCodeText.distance(from: callingCodeText.startIndex, to: range.lowerBound)
                        let position = callingCode.position.advanced(by: offset)
                        
                        guard let function = callingCode.token(at: position)?.parent?.parent?.as(FunctionCallExprSyntax.self) else { return nil }
                        
                        let concurrent = [function.parent, function.parent?.parent].contains {
                            $0?.as(AwaitExprSyntax.self) != nil
                        }
                        
                        return .init(function: function, concurrent: concurrent)
                    }
                    
                    guard !misuses.isEmpty else { return nil }
                    
                    return .init(calling: calling, called: called, misuses: misuses)
                }
            }
            
            return .init(cases: cases)
        }
        
        func print(in context: some MacroExpansionContext) {
            guard !cases.isEmpty else { return }
            
            let errorMessage = MacroExpansionErrorMessage(
                """
                Do not call other dependency functions directly. Add `Resolver` parameter to your function and use it to get an access to resolved instance
                """
            )
            let fixItMessage = MacroExpansionFixItMessage("Replace direct call with usage of `Resolver`")
            
            cases.forEach { directUseCase in
                let parametersOld = directUseCase.calling.node.signature.parameterClause.parameters
                let parametersFix = FixIt.Change.replace(
                    oldNode: Syntax(parametersOld),
                    newNode: Syntax(
                        FunctionParameterListSyntax {
                            FunctionParameterSyntax("_ resolver: Resolver")
                        }
                    )
                )
                
                directUseCase.misuses.forEach { misuse in
                    let functionNew: CodeBlockItemSyntax
                    
                    if misuse.concurrent {
                        functionNew = "resolver.\(directUseCase.called.name)"
                    } else {
                        functionNew = "await resolver.\(directUseCase.called.name)"
                    }
                    
                    let functionFix = FixIt.Change.replace(
                        oldNode: Syntax(misuse.function),
                        newNode: Syntax(functionNew)
                    )
                    
                    let highlights: [SyntaxProtocol] = [misuse.function, directUseCase.called.node, parametersOld]
                    let diagnostic = Diagnostic(
                        node: misuse.function,
                        message: errorMessage,
                        highlights: highlights.map(Syntax.init),
                        fixIt: .init(
                            message: fixItMessage,
                            changes: [
                                parametersFix,
                                functionFix
                            ]
                        )
                    )
                    
                    context.diagnose(diagnostic)
                }
            }
        }
    }
}
