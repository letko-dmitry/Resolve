//
//  DeclGroupSyntax.swift
//
//
//  Created by Dzmitry Letko on 09/08/2026.
//

import SwiftSyntax

extension DeclGroupSyntax {
    var generatedAccessLevel: String {
        for modifier in modifiers {
            switch modifier.name.tokenKind {
            case .keyword(.open), .keyword(.public): return "public "
            case .keyword(.package): return "package "
            default: continue
            }
        }

        return ""
    }
}
