//
//  Registrable.swift
//  
//
//  Created by Dzmitry Letko on 16/10/2023.
//

import Foundation
import SwiftSyntax
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftSyntaxBuilder

struct Registrables {
    let all: [Registrable]
    let nontransient: [Registrable]
    
    init(all: [Registrable], sort: Bool) {
        let all = sort ? all.sorted(using: SortDescriptor(\.name.text)) : all
        
        self.all = all
        self.nontransient = all.filter { !$0.attribute.transient }
    }
}

struct Registrable {
    struct Function {
        struct Parameter {
            let label: TokenSyntax?
        }
        
        let name: TokenSyntax
        let parameter: Parameter?
        let concurrent: Bool
        let throwable: Bool
        let type: TypeSyntax
    }
    
    let function: Function
    let attribute: RegisterAttribute
    let node: FunctionDeclSyntax
    
    var name: TokenSyntax {
        attribute.name ?? function.name
    }
}

extension Registrable {
    static func parse(function declaration: FunctionDeclSyntax, in context: some MacroExpansionContext) -> Registrable? {
        guard let attribute = RegisterAttribute.parse(attributes: declaration.attributes, in: context) else { return nil }
        guard let function = Function.parse(function: declaration, in: context) else { return nil }
        
        return .init(
            function: function,
            attribute: attribute,
            node: declaration
        )
    }
}

// MARK: - Registrable.Function
extension Registrable.Function {
    static func parse(function: FunctionDeclSyntax, in context: some MacroExpansionContext) -> Registrable.Function? {
        let type: TypeSyntax?
        
        if let returnClause = function.signature.returnClause {
            type = returnClause.type.trimmed
        } else {
            type = nil
            
            let message = MacroExpansionErrorMessage("There must be a return type")
            let diagnostic = Diagnostic(
                node: function,
                message: message
            )
            
            context.diagnose(diagnostic)
        }
        
        let parameter: Parameter?
        let parameterOk: Bool
        
        do {
            parameter = try .parse(parameters: function.signature.parameterClause.parameters, in: context)
            parameterOk = true
        } catch {
            parameter = nil
            parameterOk = false
            
            if let error = error as? Parameter.ParseError {
                let message = MacroExpansionErrorMessage("We do not expect any parameters except the one of type `Resolver`")
                let diagnostic = Diagnostic(
                    node: error.node,
                    message: message
                )
                
                context.diagnose(diagnostic)
            }
        }
        
        guard let type, parameterOk else { return nil }
        
        return .init(
            name: function.name,
            parameter: parameter,
            concurrent: function.concurrent,
            throwable: function.throwable,
            type: type
        )
    }
}

// MARK: - Registrable.Function.Parameter
extension Registrable.Function.Parameter {
    struct ParseError: @unchecked Sendable, Error {
        enum Kind {
            case count
            case type
            case syntax
        }
        
        let kind: Kind
        let node: Syntax
        
        init(kind: Kind, node: some SyntaxProtocol) {
            self.kind = kind
            self.node = Syntax(node)
        }
    }
    
    static func parse(parameters: FunctionParameterListSyntax, in context: some MacroExpansionContext) throws -> Registrable.Function.Parameter? {
        guard !parameters.isEmpty else { return nil }
        guard let first = parameters.first, parameters.count == 1 else { throw ParseError(kind: .count, node: parameters) }
        guard first.type.description == "Resolver" else { throw ParseError(kind: .type, node: first) }
        
        switch first.firstName.tokenKind {
        case .wildcard:
            return .init(label: nil)
            
        case let .identifier(identifier):
            return .init(label: .init(stringLiteral: identifier))
            
        default:
            throw ParseError(kind: .syntax, node: first.firstName)
        }
    }
}
