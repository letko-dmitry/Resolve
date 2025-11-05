//
//  Performable.swift
//
//
//  Created by Dzmitry Letko on 16/10/2023.
//

import Foundation
import SwiftSyntax
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftSyntaxBuilder

struct Performables {
    let all: [Performable]
    
    init(all: [Performable], sort: Bool) {
        self.all = sort ? all.sorted(using: SortDescriptor(\.name.text)) : all
    }
}

struct Performable {
    struct Function {
        struct Parameter {
            let label: TokenSyntax?
        }
        
        let name: TokenSyntax
        let parameter: Parameter?
        let concurrent: Bool
        let throwable: Bool
    }
    
    let function: Function
    let attribute: PerformAttribute
    let node: FunctionDeclSyntax
    
    var name: TokenSyntax {
        function.name
    }
}

extension Performable {
    static func parse(function declaration: FunctionDeclSyntax, in context: some MacroExpansionContext) -> Performable? {
        guard let attribute = PerformAttribute.parse(attributes: declaration.attributes, in: context) else { return nil }
        guard let function = Function.parse(function: declaration, in: context) else { return nil }
        
        return .init(
            function: function,
            attribute: attribute,
            node: declaration
        )
    }
}

// MARK: - Performable.Function
extension Performable.Function {
    static func parse(function: FunctionDeclSyntax, in context: some MacroExpansionContext) -> Performable.Function? {
        guard function.signature.returnClause == nil else {
            let message = MacroExpansionErrorMessage("There must be a return type")
            let diagnostic = Diagnostic(
                node: function,
                message: message
            )
            
            context.diagnose(diagnostic)
            
            return nil
        }
        
        let parameter: Parameter?
        
        do {
            parameter = try .parse(parameters: function.signature.parameterClause.parameters, in: context)
        } catch {
            if let error = error as? Parameter.ParseError {
                let message = MacroExpansionErrorMessage("We do not expect any parameters except the one of type `Resolver`")
                let diagnostic = Diagnostic(
                    node: error.node,
                    message: message
                )
                
                context.diagnose(diagnostic)
            }
            
            return nil
        }
        
        return .init(
            name: function.name,
            parameter: parameter,
            concurrent: function.concurrent,
            throwable: function.throwable
        )
    }
}

// MARK: - Performable.Function.Parameter
extension Performable.Function.Parameter {
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
    
    static func parse(parameters: FunctionParameterListSyntax, in context: some MacroExpansionContext) throws -> Performable.Function.Parameter? {
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
