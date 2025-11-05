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
    
    func build() -> DeclSyntax {
        if registrables.nontransient.isEmpty {
            return """
            struct Resolved: Sendable { }
            """
        } else {
            let properties = MemberBlockItemListSyntax(separator: "\n") {
                for registrable in registrables.nontransient {
                    "let \(registrable.name): \(registrable.function.type)"
                }
            }
            
            return """
            struct Resolved: Sendable {
                \(properties)
            }
            """
        }
    }
}
