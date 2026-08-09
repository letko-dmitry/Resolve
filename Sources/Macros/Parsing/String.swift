//
//  String.swift
//
//
//  Created by Dzmitry Letko on 09/08/2026.
//

import SwiftParser
import SwiftSyntax

extension String {
    var isSwiftIdentifier: Bool {
        !Parser.parse(source: "let \(self) = 0").hasError
    }
}
