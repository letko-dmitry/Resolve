import Foundation
import SwiftDiagnostics
import SwiftParserDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacroExpansion

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
        
        let arguments = node.arguments?.as(LabeledExprListSyntax.self)?.compactMap { $0.as(LabeledExprSyntax.self) }
        
        let sortExpression = arguments?.first { $0.label?.text == "sort" }?.expression.as(BooleanLiteralExprSyntax.self)
        let sort = (sortExpression?.literal.text).flatMap(Bool.init(_:)) ?? true
        
        return ResolvableBuilder(
            declaration: declaration,
            dependencies: sort ? dependencies.sorted(using: SortDescriptor(\.name.text)) : dependencies
        ).build()
    }
}

// MARK: - Dependency
private extension ResolvableBuilder.Dependency {
    init?(function declaration: FunctionDeclSyntax, in context: some MacroExpansionContext) {
        guard let parameters = Parameters(attributes: declaration.attributes, in: context) else { return nil }
        guard let function = Function(function: declaration, in: context) else { return nil }
        
        self.init(
            function: function,
            parameters: parameters,
            node: declaration
        )
    }
}

// MARK: - Dependency.Parameters
private extension ResolvableBuilder.Dependency.Parameters {
    struct Registrable {
        let syntax: AttributeSyntax
        let transient: Bool
    }
    
    init?(attributes: AttributeListSyntax, in context: some MacroExpansionContext) {
        let registrables: [Registrable]? = attributes.as(AttributeListSyntax.self)?.compactMap { element in
            guard let syntax = element.as(AttributeSyntax.self) else { return nil }
            guard let name = syntax.attributeName.as(IdentifierTypeSyntax.self)?.name.text else { return nil }
            
            switch name {
            case "Register": return Registrable(syntax: syntax, transient: false)
            case "RegisterTransient": return Registrable(syntax: syntax, transient: true)
            default: return nil
            }
        }
        guard let registrables, let registrable = registrables.first else { return nil }
        
        if registrables.count > 1 {
            let message = MacroExpansionWarningMessage("We do not expect more that one attribute – the first one is taken")
            let drop = Set(registrables.dropFirst().map { $0.syntax })
            let new = attributes.filter { element in
                if let attribute = element.as(AttributeSyntax.self) {
                    return !drop.contains(attribute)
                } else {
                    return false
                }
            }
            
            let diagnostic = Diagnostic(
                node: registrable.syntax,
                message: message,
                highlights: drop.map { Syntax($0) },
                fixIt: .init(
                    message: MacroExpansionFixItMessage("Remove unused attributes"),
                    changes: [
                        .replace(
                            oldNode: Syntax(attributes),
                            newNode: Syntax(new)
                        )
                    ]
                )
            )
            
            context.diagnose(diagnostic)
        }
        
        let arguments = registrable.syntax.arguments?.as(LabeledExprListSyntax.self)?.compactMap { $0.as(LabeledExprSyntax.self) }
        
        let nameExpression = arguments?.first { $0.label?.text == "name" }?.expression.as(StringLiteralExprSyntax.self)
        let name = nameExpression?.representedLiteralValue
        
        let optionsExpression = arguments?.first { $0.label?.text == "options" }?.expression
        
        self.init(
            name: name.map(TokenSyntax.init(stringLiteral:)),
            options: optionsExpression,
            transient: registrable.transient
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
        
        let concurrent: Bool
        
        if function.signature.effectSpecifiers?.asyncSpecifier != nil {
            concurrent = true
        } else {
            let attributeNameMainActor = String(describing: MainActor.self)
            let attributes = function.attributes.as(AttributeListSyntax.self)?.compactMap { $0.as(AttributeSyntax.self) }
            
            let hasAttributeNameMainActor = attributes?.contains { attribute in
                attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text == attributeNameMainActor
            }
            
            concurrent = hasAttributeNameMainActor ?? false
        }
        
        self.init(
            name: function.name,
            parameter: parameter,
            concurrent: concurrent,
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
