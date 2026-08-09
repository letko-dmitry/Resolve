//
//  TokenSyntax.swift
//
//
//  Created by Dzmitry Letko on 09/08/2026.
//

import SwiftSyntax

extension TokenSyntax {
    var unescaped: String {
        let text = text

        guard text.count > 2, text.hasPrefix("`"), text.hasSuffix("`") else { return text }

        return String(text.dropFirst().dropLast())
    }
}
