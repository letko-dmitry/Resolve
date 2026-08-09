//
//  ResolvableValidationUniquenessReport.swift
//
//
//  Created by Dzmitry Letko on 09/08/2026.
//

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros
import OrderedCollections

extension ResolvableValidation {
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

        var dropped: Set<FunctionDeclSyntax> {
            Set(cases.flatMap { $0.redeclarations.map { $0.node } })
        }

        static func make(registrables: [Registrable], performables: [Performable]) -> UniquenessReport {
            let candidates = registrables.map(Candidate.init(_:)) + performables.map(Candidate.init(_:))
            let candidatesByName = OrderedDictionary(grouping: candidates) { $0.name.text }
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
                let message = MacroExpansionErrorMessage("Invalid redeclaration of '\(uniquenessCase.first.name)'")
                let note = Note(
                    node: Syntax(uniquenessCase.first.node.name),
                    message: MacroExpansionNoteMessage("'\(uniquenessCase.first.name)' previously declared here")
                )

                uniquenessCase.redeclarations.forEach { redeclaration in
                    let diagnostic = Diagnostic(
                        node: redeclaration.node.name,
                        message: message,
                        notes: [note]
                    )

                    context.diagnose(diagnostic)
                }
            }
        }
    }
}
