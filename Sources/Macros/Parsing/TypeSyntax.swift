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

    var isVoid: Bool {
        switch trimmedDescription {
        case "Void", "()", "Swift.Void": true
        default: false
        }
    }

    // `identifier` flattens a member type, which is right for an attribute name but not here – only
    // the `Resolver` generated inside `enclosing` is accepted, spelled plainly or qualified by it.
    func isResolver(of enclosing: TokenSyntax) -> Bool {
        if let identifier = self.as(IdentifierTypeSyntax.self) {
            return identifier.name.trimmedDescription == "Resolver" && identifier.genericArgumentClause == nil
        }

        if let member = self.as(MemberTypeSyntax.self) {
            return member.name.trimmedDescription == "Resolver"
                && member.genericArgumentClause == nil
                && member.baseType.trimmedDescription == enclosing.text
        }

        return false
    }
}
