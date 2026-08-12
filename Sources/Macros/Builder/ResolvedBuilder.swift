//
//  ResolvedBuilder.swift
//
//
//  Created by Dzmitry Letko on 16/10/2023.
//

import SwiftSyntax
import SwiftSyntaxBuilder

struct ResolvedBuilder {
    let registrables: Registrables
    let access: String

    func build() -> DeclSyntax {
        if registrables.nontransient.isEmpty {
            return """
            \(raw: access)struct Resolved: Sendable { }
            """
        } else {
            let members = MemberBlockItemListSyntax(separator: "\n") {
                for registrable in registrables.nontransient {
                    if registrable.hidden {
                        "private let \(registrable.name): \(registrable.function.type)"
                    } else {
                        "\(access)let \(registrable.name): \(registrable.function.type)"
                    }
                }

                initializer()
            }

            return """
            \(raw: access)struct Resolved: Sendable {
                \(members)
            }
            """
        }
    }
}

// MARK: - private
private extension ResolvedBuilder {
    func initializer() -> String {
        guard registrables.nontransient.contains(where: \.hidden) else { return "" }

        let parameters = registrables.nontransient.map { registrable in
            "\(registrable.name): \(registrable.function.type)"
        }
        let assignments = registrables.nontransient.map { registrable in
            "self.\(registrable.name) = \(registrable.name)"
        }

        return [
            "",
            "init(",
            "    " + parameters.joined(separator: ",\n    "),
            ") {",
            "    " + assignments.joined(separator: "\n    "),
            "}"
        ].joined(separator: "\n")
    }
}
