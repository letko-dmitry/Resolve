//
//  FunctionDeclSyntax.swift
//
//
//  Created by Dzmitry Letko on 16/10/2023.
//

import SwiftSyntax
import SwiftParser

extension FunctionDeclSyntax {
    var concurrent: Bool {
        if signature.effectSpecifiers?.asyncSpecifier != nil {
            return true
        }
        
        let attributeNameMainActor = String(describing: MainActor.self)
        let attributes = attributes.compactMap { $0.as(AttributeSyntax.self) }
        
        return attributes.contains { attribute in
            attribute.attributeName.description == attributeNameMainActor
        }
    }
    
    var throwable: Bool {
        signature.effectSpecifiers?.throwsClause?.throwsSpecifier != nil
    }
}
