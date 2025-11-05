//
//  Perform.swift
//
//
//  Created by Dzmitry Letko on 16/10/2023.
//

public import SwiftSyntax
public import SwiftSyntaxMacros

import SwiftDiagnostics

public struct Perform: PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        if !declaration.is(FunctionDeclSyntax.self) {
            let message = MacroExpansionWarningMessage("Only methods are allowed for performing")
            let diagnostic = Diagnostic(
                node: node,
                message: message
            )
            
            context.diagnose(diagnostic)
        }
        
        return []
    }
}
