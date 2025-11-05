//
//  CodeBlockItemListSyntax.swift
//
//
//  Created by Dzmitry Letko on 17/10/2023.
//

import SwiftSyntax
import SwiftSyntaxBuilder

extension CodeBlockItemListSyntax {
    init(separator: String, @StringCollectionBuilder stringCollectionBuilder: () -> [String]) {
        self.init(stringLiteral: stringCollectionBuilder().joined(separator: separator))
    }
}
