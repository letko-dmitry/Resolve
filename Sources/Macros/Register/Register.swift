//
//  Register.swift
//
//
//  Created by Dzmitry Letko on 01/10/2023.
//

import SwiftSyntax
import SwiftSyntaxMacros

public struct Register: PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        return []
    }
}
