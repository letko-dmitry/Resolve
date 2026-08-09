//
//  ResolvableValidationCycleReport.swift
//
//
//  Created by Dzmitry Letko on 09/08/2026.
//

import Algorithms
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros
import OrderedCollections

extension ResolvableValidation {
    struct CycleReport {
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

        let cycles: [[Candidate]]

        static func make(registrables: [Registrable], performables: [Performable]) -> CycleReport {
            let candidates = registrables.map(Candidate.init(_:)) + performables.map(Candidate.init(_:))
            let candidatesByName = OrderedDictionary(candidates.map { ($0.name.text, $0) }) { first, _ in first }
            let edges = candidates.reduce(into: OrderedDictionary<String, OrderedSet<String>>()) { edges, candidate in
                edges[candidate.name.text] = candidate.dependencies.filter { candidatesByName[$0] != nil }
            }

            return .init(cycles: Search(edges: edges).cycles().map { cycle in
                cycle.compactMap { candidatesByName[$0] }
            })
        }

        func print(in context: some MacroExpansionContext) {
            cycles.forEach { cycle in
                guard let first = cycle.first else { return }

                let path = chain(cycle, [first]).map { "'\($0.name)'" }.joined(separator: " → ")
                let message = MacroExpansionErrorMessage("Dependency cycle: \(path) – resolving it would never finish")
                let notes = cycle.dropFirst().map { candidate in
                    Note(
                        node: Syntax(candidate.node.name),
                        message: MacroExpansionNoteMessage("'\(candidate.name)' takes part in the cycle")
                    )
                }

                let diagnostic = Diagnostic(
                    node: first.node.name,
                    message: message,
                    notes: Array(notes)
                )

                context.diagnose(diagnostic)
            }
        }
    }
}

// MARK: - CycleReport.Candidate
extension ResolvableValidation.CycleReport.Candidate {
    var dependencies: OrderedSet<String> {
        guard let parameter = node.signature.parameterClause.parameters.first else { return [] }
        guard let body = node.body else { return [] }

        let resolver = (parameter.secondName ?? parameter.firstName).text

        guard resolver != "_" else { return [] }

        return ResolvableValidation.BodyScan.make(body: body).members(of: resolver)
    }
}

// MARK: - CycleReport.Search
extension ResolvableValidation.CycleReport {
    struct Search {
        let edges: OrderedDictionary<String, OrderedSet<String>>

        func cycles() -> [OrderedSet<String>] {
            var found: OrderedSet<OrderedSet<String>> = []
            var visited: Set<String> = []
            var path: OrderedSet<String> = []

            func walk(_ name: String) {
                if let index = path.firstIndex(of: name) {
                    found.append(OrderedSet(path[index...]))

                    return
                }

                guard visited.insert(name).inserted else { return }

                path.append(name)
                edges[name]?.forEach(walk)
                path.removeLast()
            }

            edges.keys.forEach(walk)

            return Array(found)
        }
    }
}
