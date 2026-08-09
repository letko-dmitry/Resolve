//
//  Register.swift
//
//
//  Created by Dzmitry Letko on 01/10/2023.
//

public import SwiftSyntax
public import SwiftSyntaxMacros

public struct Register: PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        ValidationMacroPlacement.validate(attribute: node, declaration: declaration, in: context)

        return []
    }
}
