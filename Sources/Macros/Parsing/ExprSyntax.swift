//
//  ExprSyntax.swift
//
//
//  Created by Dzmitry Letko on 09/08/2026.
//

import SwiftSyntax

extension ExprSyntax {
    var isSelf: Bool {
        self.as(DeclReferenceExprSyntax.self)?.baseName.tokenKind == .keyword(.self)
    }
}
