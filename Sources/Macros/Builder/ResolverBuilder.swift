//
//  ResolverBuilder.swift
//
//
//  Created by Dzmitry Letko on 16/10/2023.
//

import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftParser

struct ResolverBuilder {
    struct Registrar {
        let name: TokenSyntax = "registrar"
        let type: TokenSyntax = "Resolve.\(Registrar.self)"
    }
    
    struct Declaration {
        let name: TokenSyntax = "resolvable"
        let type: TokenSyntax
        let access: String
    }

    let declaration: Declaration
    let performables: Performables
    let registrables: Registrables
    let registrar: Registrar = .init()

    func build() -> DeclSyntax {
        let members = MemberBlockItemListSyntax(separator: "\n\n") {
            variables().description
            registrableGetters().description
            resolverInit().description
            performableMethods().description
            resolve().description
        }

        return """
        \(raw: declaration.access)struct Resolver: Sendable {
            \(members)
        }
        """
    }
}

// MARK: - private
private extension ResolverBuilder {
    func variables() -> MemberBlockItemListSyntax {
        MemberBlockItemListSyntax(separator: "\n") {
            registrarVariable().description
            containerVariable().description
        }
    }

    func registrarVariable() -> MemberBlockItemListSyntax {
        guard !registrables.all.isEmpty || !performables.all.isEmpty else { return "" }

        return "private let _\(registrar.name) = \(registrar.type)(for: \(declaration.type).self, minimumCapacity: \(raw: (performables.all.count &+ registrables.all.count).description))"
    }
    
    func containerVariable() -> MemberBlockItemListSyntax {
        "private let _\(declaration.name): \(declaration.type)"
    }
    
    func resolverInit() -> MemberBlockItemListSyntax {
        """
        \(raw: declaration.access)init(_ \(declaration.name): \(declaration.type)) {
            self._\(declaration.name) = \(declaration.name)
        }
        """
    }
    
    func registrableGetters() -> MemberBlockItemListSyntax {
        MemberBlockItemListSyntax(separator: "\n\n") {
            for registrable in registrables.all {
                let function = registrable.function
                var functionParameters: String {
                    if let parameter = function.parameter {
                        if let label = parameter.label {
                            "\(label): self"
                        } else {
                            "self"
                        }
                    } else {
                        ""
                    }
                }
                
                let functionEffect = "\(registrable.function.throwable ? "try " : "")\(registrable.function.concurrent ? "await " : "")"
                let functionCall: ExprSyntax = "\(raw: functionEffect)_\(declaration.name).\(function.name)(\(raw: functionParameters))"
                
                var register: ExprSyntax {
                    if let options = registrable.attribute.options {
                        "register(for: \"\(raw: registrable.name.unescaped)\", options: \(options))"
                    } else {
                        "register(for: \"\(raw: registrable.name.unescaped)\")"
                    }
                }
                
                if registrable.function.throwable {
                    """
                    \(declaration.access)var \(registrable.name): \(registrable.function.type) {
                        get async throws {
                            try await _\(registrar.name).\(register) {
                                \(functionCall)
                            }
                        }
                    }
                    """
                } else {
                    """
                    \(declaration.access)var \(registrable.name): \(registrable.function.type) {
                        get async {
                            await _\(registrar.name).\(register) {
                                \(functionCall)
                            }
                        }
                    }
                    """
                }
            }
        }
    }
    
    func registrableVariables() -> CodeBlockItemListSyntax {
        CodeBlockItemListSyntax(separator: "\n") {
            for registrable in registrables.nontransient {
                "async let \(registrable.name) = \(registrable.name)"
            }
        }
    }
    
    func performableMethods() -> MemberBlockItemListSyntax {
        MemberBlockItemListSyntax(separator: "\n\n") {
            for performable in performables.all {
                let function = performable.function
                var functionParameters: String {
                    if let parameter = function.parameter {
                        if let label = parameter.label {
                            return "\(label): self"
                        } else {
                            return "self"
                        }
                    } else {
                        return ""
                    }
                }
                
                let functionEffect = "\(performable.function.throwable ? "try " : "")\(performable.function.concurrent ? "await " : "")"
                let functionCall: ExprSyntax = "\(raw: functionEffect)_\(declaration.name).\(function.name)(\(raw: functionParameters))"
                
                var register: ExprSyntax {
                    if let options = performable.attribute.options {
                        "register(for: \"\(raw: performable.name.unescaped)\", options: \(options))"
                    } else {
                        "register(for: \"\(raw: performable.name.unescaped)\")"
                    }
                }
                
                if performable.function.throwable {
                    """
                    \(declaration.access)func \(performable.name)() async throws {
                        try await _\(registrar.name).\(register) {
                            \(functionCall)
                        }
                    }
                    """
                } else {
                    """
                    \(declaration.access)func \(performable.name)() async {
                        await _\(registrar.name).\(register) {
                            \(functionCall)
                        }
                    }
                    """
                }
            }
        }
    }
    
    @CodeBlockItemListBuilder
    func performableTasks() -> CodeBlockItemListSyntax {
        if !performables.all.isEmpty {
            let tasks = CodeBlockItemListSyntax {
                for performable in performables.all {
                    if performable.function.throwable {
                        "group.addTask { try await \(performable.function.name)() }"
                    } else {
                        "group.addTask { await \(performable.function.name)() }"
                    }
                }
            }
            
            if throwablePerformables {
                """
                try await withThrowingDiscardingTaskGroup { group in
                    \(tasks)
                }
                """
            } else {
                """
                await withDiscardingTaskGroup { group in
                    \(tasks)
                }
                """
            }
        }
    }
    
    @CodeBlockItemListBuilder
    func resolverReturn() -> CodeBlockItemListSyntax {
        if registrables.nontransient.isEmpty {
            """
            return .init()
            """
        } else {
            let arguments = registrables.nontransient.map { registrable in
                "\(registrable.name.unescaped): \(registrable.name)"
            }
            
            """
            return \(raw: throwableRegistrables ? "try " : "")await .init(
                \(raw: arguments.joined(separator: ",\n    "))
            )
            """
        }
    }
    
    @CodeBlockItemListBuilder
    func resolve() -> CodeBlockItemListSyntax {
        if registrables.nontransient.isEmpty && performables.all.isEmpty {
            """
            @discardableResult
            \(raw: declaration.access)func resolve() -> Resolved {
                \(resolverReturn())
            }
            """
        } else if registrables.nontransient.isEmpty {
            """
            @discardableResult
            \(raw: declaration.access)func resolve() async \(raw: throwablePerformables ? "throws " : "")-> Resolved {
                \(performableTasks())

                \(resolverReturn())
            }
            """
        } else if performables.all.isEmpty {
            """
            \(raw: declaration.access)func resolve() async \(raw: throwableRegistrables ? "throws " : "")-> Resolved {
                \(registrableVariables())

                \(resolverReturn())
            }
            """
        } else {
            """
            \(raw: declaration.access)func resolve() async \(raw: (throwablePerformables || throwableRegistrables) ? "throws " : "")-> Resolved {
                \(registrableVariables())
            
                \(performableTasks())
            
                \(resolverReturn())
            }
            """
        }
    }
}

// MARK: - private
private extension ResolverBuilder {
    var throwablePerformables: Bool {
        performables.all.contains { $0.function.throwable }
    }
    
    var throwableRegistrables: Bool {
        registrables.nontransient.contains { $0.function.throwable }
    }
}
