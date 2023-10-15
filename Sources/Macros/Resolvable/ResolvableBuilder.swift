//
//  ResolvableBuilder.swift
//
//
//  Created by Dzmitry Letko on 01/10/2023.
//

import Foundation
import SwiftSyntax
import SwiftSyntaxMacros

struct ResolvableBuilder {
    struct Registrar {
        let name: TokenSyntax = "registrar"
        let type: TokenSyntax = "Resolve.\(Registrar.self)"
    }
    
    struct Declaration {
        let name: TokenSyntax = "resolvable"
        let type: TokenSyntax
    }
    
    struct Dependency {
        struct Parameters {
            let name: TokenSyntax?
            let options: ExprSyntax?
            let transient: Bool
        }
        
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
        let parameters: Parameters
        let node: FunctionDeclSyntax
        
        var name: TokenSyntax {
            parameters.name ?? function.name
        }
    }
    
    struct Dependencies {
        let all: [Dependency]
        let nontransient: [Dependency]
    }
    
    enum Kind {
        case empty
        case dependencies(_ dependencies: Dependencies, registrar: Registrar = .init())
    }
    
    let declaration: Declaration
    let kind: Kind
    
    init(declaration: Declaration, dependencies: [Dependency]) {
        let dependencies = Dependencies(
            all: dependencies,
            nontransient: dependencies.filter { !$0.parameters.transient }
        )
        
        self.declaration = declaration
        self.kind = .dependencies(dependencies)
    }
    
    init(declaration: Declaration) {
        self.declaration = declaration
        self.kind = .empty
    }
    
    func build() -> [DeclSyntax] {
        return [
            resolved(),
            resolver()
        ]
    }
}

// MARK: - private
private extension ResolvableBuilder {
    func resolved() -> DeclSyntax {
        switch kind {
        case .empty:
            return """
            struct Resolved: Sendable { }
            """
            
        case let .dependencies(dependencies, _):
            let properties = dependencies.nontransient.map { dependency in
                "let \(dependency.name): \(dependency.function.type)"
            }
            
            return """
            struct Resolved: Sendable {
                \(raw: properties.joined(separator: "\n"))
            }
            """
        }
    }
    
    // swiftlint:disable:next function_body_length
    func resolver() -> DeclSyntax {
        switch kind {
        case .empty:
            return """
            struct Resolver: Sendable {
                private let _\(declaration.name): \(declaration.type)
            
                init(_ \(declaration.name): \(declaration.type)) {
                    self._\(declaration.name) = \(declaration.name)
                }
            
                func resolve() -> Resolved {
                    return .init()
                }
            }
            """
            
        case let .dependencies(dependencies, registrar):
            let getters = dependencies.all.map { dependency in
                let function = dependency.function
                let functionParameters: String
                
                if let parameter = function.parameter {
                    if let label = parameter.label {
                        functionParameters = "\(label): self"
                    } else {
                        functionParameters = "self"
                    }
                } else {
                    functionParameters = ""
                }

                let functionEffect = call(throwable: function.throwable, concurrent: function.concurrent)
                let functionCall = "\(functionEffect) _\(declaration.name).\(function.name)(\(functionParameters))".trimmingCharacters(in: .whitespaces)

                let register: String
                
                if let options = dependency.parameters.options {
                    register = "register(for: \"\(dependency.name)\", options: \(options))"
                } else {
                    register = "register(for: \"\(dependency.name)\")"
                }
                
                return """
                var \(dependency.name): \(dependency.function.type) {
                    get \(effect(throwable: dependency.function.throwable)) {
                        \(call(throwable: dependency.function.throwable)) _\(registrar.name).\(register) {
                            \(functionCall)
                        }
                    }
                }
                """
            }
            let variables = dependencies.nontransient.map { dependency in
                "async let \(dependency.name) = \(dependency.name)"
            }
            let arguments = dependencies.nontransient.map { dependency in
                "\(dependency.name): \(dependency.name)"
            }
            let throwable = dependencies.nontransient.contains { $0.function.throwable }
            
            return """
            struct Resolver: Sendable {
                private let _\(registrar.name) = \(registrar.type)(for: \(declaration.type).self)
                private let _\(declaration.name): \(declaration.type)
                \n\(raw: getters.joined(separator: "\n\n"))
            
                init(_ \(declaration.name): \(declaration.type)) {
                    self._\(declaration.name) = \(declaration.name)
                }
            
                func resolve() \(raw: effect(throwable: throwable)) -> Resolved {
                    \(raw: variables.joined(separator: "\n"))
            
                    return \(raw: call(throwable: throwable)) .init(
                        \(raw: arguments.joined(separator: ",\n"))
                    )
                }
            }
            """
        }
    }
}

// MARK: - private
private extension ResolvableBuilder {
    func effect(throwable: Bool) -> String {
        var effects: [String] = []
        effects.append("async")
        
        if throwable {
            effects.append("throws")
        }
        
        return effects.joined(separator: " ")
    }
    
    func call(throwable: Bool, concurrent: Bool = true) -> String {
        var effects: [String] = []
        
        if throwable {
            effects.append("try")
        }
        
        if concurrent {
            effects.append("await")
        }
        
        return effects.joined(separator: " ")
    }
}
