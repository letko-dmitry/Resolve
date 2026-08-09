//
//  ResolvableValidationDirectUseReport.swift
//
//
//  Created by Dzmitry Letko on 09/08/2026.
//

import Algorithms
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

extension ResolvableValidation {
    struct DirectUseReport {
        struct Candidate {
            let functionName: TokenSyntax
            let exposedName: TokenSyntax
            let node: FunctionDeclSyntax
            let concurrent: Bool
            let scan: BodyScan

            init(_ registrable: Registrable) {
                node = registrable.node
                functionName = registrable.function.name
                exposedName = registrable.name
                concurrent = registrable.function.concurrent
                scan = .make(body: registrable.node.body)
            }

            init(_ performable: Performable) {
                node = performable.node
                functionName = performable.function.name
                exposedName = performable.name
                concurrent = performable.function.concurrent
                scan = .make(body: performable.node.body)
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
            let cases: [Case] = product(candidates, candidates).compactMap { called, calling in
                guard called.node != calling.node else { return nil }

                let misuses = calling.scan.calls(of: called.functionName.text).map { call in
                    Case.Misuse(function: call, concurrent: call.awaited)
                }

                guard !misuses.isEmpty else { return nil }

                return .init(calling: calling, called: called, misuses: misuses)
            }

            return .init(cases: cases)
        }

        func print(in context: some MacroExpansionContext) {
            guard !cases.isEmpty else { return }

            let errorMessage = MacroExpansionErrorMessage(
                """
                Do not call other dependency functions directly. Add a `Resolver` parameter to your function and use it to get access to the resolved instance
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
                        functionNew = "resolver.\(directUseCase.called.exposedName)"
                    } else {
                        functionNew = "await resolver.\(directUseCase.called.exposedName)"
                    }

                    let functionFix = FixIt.Change.replace(
                        oldNode: Syntax(misuse.function),
                        newNode: Syntax(functionNew)
                    )

                    let highlights: [any SyntaxProtocol] = [misuse.function, directUseCase.called.node, parametersOld]
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
