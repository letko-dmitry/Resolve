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
            let properties = MemberBlockItemListSyntax(separator: "\n") {
                for registrable in registrables.nontransient {
                    "\(access)let \(registrable.name): \(registrable.function.type)"
                }
            }

            return """
            \(raw: access)struct Resolved: Sendable {
                \(properties)
            }
            """
        }
    }
}
