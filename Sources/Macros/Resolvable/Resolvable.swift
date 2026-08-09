//
//  Resolvable.swift
//
//
//  Created by Dzmitry Letko on 01/10/2023.
//

public import SwiftSyntax
public import SwiftSyntaxMacros

public enum Resolvable: MemberMacro {
    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax, conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard let named = declaration.asProtocol((any NamedDeclSyntax).self),
              declaration.is(StructDeclSyntax.self) || declaration.is(ClassDeclSyntax.self) else {
            throw MacroExpansionErrorMessage("The macro must be attached to a class or a struct")
        }

        let arguments = node.arguments?.as(LabeledExprListSyntax.self)
        let sort = arguments?.bool(name: "sort", default: true, in: context) ?? true

        let functions = declaration.memberBlock.members.compactMap { $0.decl.as(FunctionDeclSyntax.self) }

        let declaration = ResolverBuilder.Declaration(
            type: named.name.trimmed,
            access: declaration.generatedAccessLevel
        )
        let validation = ResolvableValidation(
            registrables: functions.compactMap { function in
                Registrable.parse(function: function, in: context)
            },
            performables: functions.compactMap { function in
                Performable.parse(function: function, in: context)
            }
        )
        let resolvables = validation.validate(in: context)
        let registrables = Registrables(all: resolvables.registrables, sort: sort)
        let performables = Performables(all: resolvables.performables, sort: sort)

        return [
            ResolvedBuilder(registrables: registrables, access: declaration.access).build(),
            ResolverBuilder(declaration: declaration, performables: performables, registrables: registrables).build()
        ]
    }
}
