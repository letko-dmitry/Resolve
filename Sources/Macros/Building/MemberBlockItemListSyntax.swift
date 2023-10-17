//
//  MemberBlockItemListSyntax.swift
//
//
//  Created by Dzmitry Letko on 17/10/2023.
//

import SwiftSyntax

extension MemberBlockItemListSyntax {
    init(separator: String, @StringCollectionBuilder stringCollectionBuilder: () -> [String]) {
        self.init(stringLiteral: stringCollectionBuilder().joined(separator: separator))
    }
}
