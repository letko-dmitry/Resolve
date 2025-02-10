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
    }
    
    let declaration: Declaration
    let performables: Performables
    let registrables: Registrables
    let registrar: Registrar = .init()
    
    func build() -> DeclSyntax {
        func resolver(_ body: () -> MemberBlockItemListSyntax) -> DeclSyntax {
            return """
            struct Resolver: Sendable {
            \(body())
            }
            """
        }
        
        return resolver {
            if registrables.all.isEmpty && performables.all.isEmpty {
                return """
                    \(containerVariable())
                
                    \(resolverInit())
                            
                    \(resolve())
                """
            } else if registrables.all.isEmpty {
                return """
                    \(registrarVariable())
                    \(containerVariable())

                    \(resolverInit())

                    \(performableMethods())
                
                    \(resolve())
                """
            } else if performables.all.isEmpty {
                return """
                    \(registrarVariable())
                    \(containerVariable())

                    \(registrableGetters())
                
                    \(resolverInit())

                    \(resolve())
                """
            } else {
                return """
                    \(registrarVariable())
                    \(containerVariable())

                    \(registrableGetters())
                
                    \(resolverInit())

                    \(performableMethods())
                
                    \(resolve())
                """
            }
        }
    }
}

// MARK: - private
private extension ResolverBuilder {
    func registrarVariable() -> MemberBlockItemListSyntax {
        "private let _\(registrar.name) = \(registrar.type)(for: \(declaration.type).self, minimumCapacity: \(raw: (performables.all.count &+ registrables.all.count).description))"
    }
    
    func containerVariable() -> MemberBlockItemListSyntax {
        "private let _\(declaration.name): \(declaration.type)"
    }
    
    func resolverInit() -> MemberBlockItemListSyntax {
        """
        init(_ \(declaration.name): \(declaration.type)) {
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
                        "register(for: \"\(registrable.name)\", options: \(options))"
                    } else {
                        "register(for: \"\(registrable.name)\")"
                    }
                }
                
                if registrable.function.throwable {
                    """
                    var \(registrable.name): \(registrable.function.type) {
                        get async throws {
                            try await _\(registrar.name).\(register) {
                                \(functionCall)
                            }
                        }
                    }
                    """
                } else {
                    """
                    var \(registrable.name): \(registrable.function.type) {
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
                        "register(for: \"\(performable.name)\", options: \(options))"
                    } else {
                        "register(for: \"\(performable.name)\")"
                    }
                }
                
                if performable.function.throwable {
                    """
                    func \(performable.name)() async throws {
                        try await _\(registrar.name).\(register) {
                            \(functionCall)
                        }
                    }
                    """
                } else {
                    """
                    func \(performable.name)() async {
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
                "\(registrable.name): \(registrable.name)"
            }
            
            """
            return \(raw: throwableRegistrables ? "try " : "")await .init(
                \(raw: arguments.joined(separator: ",\n\t"))
            )
            """
        }
    }
    
    @CodeBlockItemListBuilder
    func resolve() -> CodeBlockItemListSyntax {
        if registrables.nontransient.isEmpty && performables.all.isEmpty {
            """
            @discardableResult
            func resolver() -> Resolved {
                \(resolverReturn())
            }
            """
        } else if registrables.nontransient.isEmpty {
            """
            @discardableResult
            func resolve() async \(raw: throwablePerformables ? "throws " : "")-> Resolved {
                \(performableTasks())
            
                \(resolverReturn())
            }
            """
        } else if performables.all.isEmpty {
            """
            func resolve() async \(raw: throwableRegistrables ? "throws " : "")-> Resolved {
                \(registrableVariables())
            
                \(resolverReturn())
            }
            """
        } else {
            """
            func resolve() async \(raw: (throwablePerformables || throwableRegistrables) ? "throws " : "")-> Resolved {
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
