//
//  Register.swift
//
//
//  Created by Dzmitry Letko on 01/10/2023.
//

import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacroExpansion
import SwiftDiagnostics

public struct Register: PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        if !declaration.is(FunctionDeclSyntax.self) {
            let message = MacroExpansionWarningMessage("Only functions are allowed for registration")
            let diagnostic = Diagnostic(
                node: node,
                message: message
            )
            
            context.diagnose(diagnostic)
        }
        
        return []
    }
}
