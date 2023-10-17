import Foundation
import SwiftSyntax
import SwiftSyntaxMacros

public enum Resolvable: MemberMacro {
    enum ParseError: String, Error {
        case unknownDeclaration = "The macros must be attached to a class or a struct"
    }
    
    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard let named = declaration.asProtocol(NamedDeclSyntax.self) else {
            throw ParseError.unknownDeclaration
        }
        
        let arguments = node.arguments?.as(LabeledExprListSyntax.self)
        let sort = arguments?.bool(name: "sort") ?? true
        
        let functions = declaration.memberBlock.members.compactMap { $0.decl.as(FunctionDeclSyntax.self) }
        
        let declaration = ResolverBuilder.Declaration(type: named.name.trimmed)
        let registrables = Registrables(
            all: functions.compactMap { function in
                Registrable.parse(function: function, in: context)
            },
            sort: sort
        )
        let performables = Performables(
            all: functions.compactMap { function in
                Performable.parse(function: function, in: context)
            },
            sort: sort
        )
        
        ResolvableValidation(registrables: registrables.all, performables: performables.all).validate(in: context)
        
        return [
            ResolvedBuilder(registrables: registrables).build(),
            ResolverBuilder(declaration: declaration, performables: performables, registrables: registrables).build()
        ]
    }
}

