//
//  FunctionCallExprSyntax.swift
//
//
//  Created by Dzmitry Letko on 09/08/2026.
//

import SwiftSyntax

extension FunctionCallExprSyntax {
    var awaited: Bool {
        [parent, parent?.parent].contains { $0?.as(AwaitExprSyntax.self) != nil }
    }
}
