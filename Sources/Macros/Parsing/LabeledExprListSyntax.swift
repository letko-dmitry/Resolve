//
//  LabeledExprListSyntax.swift
//  
//
//  Created by Dzmitry Letko on 16/10/2023.
//

import SwiftSyntax
import SwiftParser

extension LabeledExprListSyntax {
    func expression(name: String) -> ExprSyntax? {
        first { $0.label?.text == name }?.expression
    }
    
    func bool(name: String) -> Bool? {
        (expression(name: name)?.as(BooleanLiteralExprSyntax.self)?.literal.text).flatMap(Bool.init(_:))
    }
    
    func string(name: String) -> String? {
        expression(name: name)?.as(StringLiteralExprSyntax.self)?.representedLiteralValue
    }
}
