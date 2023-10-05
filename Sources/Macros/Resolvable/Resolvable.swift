import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacroExpansion
import Foundation

public enum Resolvable: MemberMacro {
    enum ParseError: String, Error {
        case unknownDeclaration = "The macros must be attached to a class or a struct"
    }
    
    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard let named = declaration.asProtocol(NamedDeclSyntax.self) else {
            throw ParseError.unknownDeclaration
        }
        
        let functions = declaration.memberBlock.members.compactMap { $0.decl.as(FunctionDeclSyntax.self) }
        
        let declaration = ResolvableBuilder.Declaration(type: named.name.trimmed)
        let dependencies = functions.compactMap { function in
            ResolvableBuilder.Dependency(function: function, in: context)
        }
      
        guard !dependencies.isEmpty else {
            return ResolvableBuilder(declaration: declaration).build()
        }
        
        ResolvableValidation(dependencies: dependencies).validate(in: context)
        
        return ResolvableBuilder(
            declaration: declaration,
            dependencies: dependencies
        ).build()
    }
}

// MARK: - Dependency
private extension ResolvableBuilder.Dependency {
    init?(function declaration: FunctionDeclSyntax, in context: some MacroExpansionContext) {
        guard let options = Options(attributes: declaration.attributes) else { return nil }
        guard let function = Function(function: declaration, in: context) else { return nil }
        
        self.init(
            function: function,
            options: options,
            node: declaration
        )
    }
}

// MARK: - Dependency.Options
private extension ResolvableBuilder.Dependency.Options {
    init?(attributes: AttributeListSyntax) {
        let attributes = attributes.as(AttributeListSyntax.self)?.compactMap { $0.as(AttributeSyntax.self) }
        let attribute = attributes?.first {
            $0.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "Register"
        }
        
        guard let attribute else { return nil }
        
        let arguments = attribute.arguments?.as(LabeledExprListSyntax.self)?.compactMap { $0.as(LabeledExprSyntax.self) }
        
        let nameExpression = arguments?.first { $0.label?.text == "name" }?.expression.as(StringLiteralExprSyntax.self)
        let name = nameExpression?.representedLiteralValue
        
        let transientExpression = arguments?.first { $0.label?.text == "transient" }?.expression.as(BooleanLiteralExprSyntax.self)
        let transient = (transientExpression?.literal.text).flatMap(Bool.init(_:))
        
        self.init(
            name: name.map(TokenSyntax.init(stringLiteral:)),
            transient: transient ?? false
        )
    }
}

// MARK: - Dependency.Function
private extension ResolvableBuilder.Dependency.Function {
    init?(function: FunctionDeclSyntax, in context: some MacroExpansionContext) {
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
            parameter = try Parameter(parameters: function.signature.parameterClause.parameters, in: context)
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
        
        self.init(
            name: function.name,
            parameter: parameter,
            concurrent: function.signature.effectSpecifiers?.asyncSpecifier != nil,
            throwable: function.signature.effectSpecifiers?.throwsSpecifier != nil,
            type: type
        )
    }
}

// MARK: - Dependency.Function
private extension ResolvableBuilder.Dependency.Function.Parameter {
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
    
    init?(parameters: FunctionParameterListSyntax, in context: some MacroExpansionContext) throws {
        guard !parameters.isEmpty else { return nil }
        guard let first = parameters.first, parameters.count == 1 else { throw ParseError(kind: .count, node: parameters) }
        guard first.type.as(IdentifierTypeSyntax.self)?.name.text == "Resolver" else { throw ParseError(kind: .type, node: first) }
        
        switch first.firstName.tokenKind {
        case .wildcard:
            self.init(label: nil)
            
        case let .identifier(identifier):
            self.init(label: .init(stringLiteral: identifier))
            
        default:
            throw ParseError(kind: .syntax, node: first.firstName)
        }
    }
}
