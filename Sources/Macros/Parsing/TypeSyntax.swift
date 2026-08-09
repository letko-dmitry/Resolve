//
//  TypeSyntax.swift
//
//
//  Created by Dzmitry Letko on 09/08/2026.
//

import SwiftSyntax

extension TypeSyntax {
    var identifier: String {
        if let member = self.as(MemberTypeSyntax.self) {
            return member.name.trimmedDescription
        }

        if let identifier = self.as(IdentifierTypeSyntax.self) {
            return identifier.name.trimmedDescription
        }

        return trimmedDescription
    }

    var opaque: Bool {
        tokens(viewMode: .sourceAccurate).contains { $0.tokenKind == .keyword(.some) }
    }
}
