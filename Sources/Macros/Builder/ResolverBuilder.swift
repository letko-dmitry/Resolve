//
//  ResolverBuilder.swift
//
//
//  Created by Dzmitry Letko on 16/10/2023.
//

import SwiftParser
import SwiftSyntax
import SwiftSyntaxBuilder

struct ResolverBuilder {
    struct Registrar {
        let name: TokenSyntax = "registrar"
        let type: TokenSyntax = "Resolve.\(Registrar.self)"
        let registrations: TokenSyntax = "Registrations"
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
            registrations().description
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

        return "private let _\(registrar.name) = \(registrar.type).Storage(\(registrar.registrations)())"
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
                if registrable.function.throwable {
                    """
                    \(declaration.access)var \(registrable.name): \(registrable.function.type) {
                        get async throws {
                            try await \(value(registrable.name, registrable.attribute.options))
                        }
                    }
                    """
                } else {
                    """
                    \(declaration.access)var \(registrable.name): \(registrable.function.type) {
                        get async {
                            await \(value(registrable.name, registrable.attribute.options))
                        }
                    }
                    """
                }
            }
        }
    }

    func performableMethods() -> MemberBlockItemListSyntax {
        MemberBlockItemListSyntax(separator: "\n\n") {
            for performable in performables.all {
                if performable.function.throwable {
                    """
                    \(declaration.access)func \(performable.name)() async throws {
                        try await \(value(performable.name, performable.attribute.options))
                    }
                    """
                } else {
                    """
                    \(declaration.access)func \(performable.name)() async {
                        await \(value(performable.name, performable.attribute.options))
                    }
                    """
                }
            }
        }
    }

    @CodeBlockItemListBuilder
    func resolve() -> CodeBlockItemListSyntax {
        if registrables.nontransient.isEmpty, performables.all.isEmpty {
            """
            @discardableResult
            \(raw: declaration.access)func resolve() -> Resolved {
                return .init()
            }
            """
        } else {
            """
            \(raw: discardable)\(raw: declaration.access)func resolve() async \(raw: throwable ? "throws " : "")-> Resolved {
                \(taskStarts())

                \(resolution())
            }
            """
        }
    }

    // Every task is started before any is awaited, so the whole graph is in flight at once without a child task each.
    func taskStarts() -> CodeBlockItemListSyntax {
        CodeBlockItemListSyntax(separator: "\n") {
            for registrable in registrables.nontransient {
                start(registrable.name, registrable.attribute.options)
            }

            for performable in performables.all {
                start(performable.name, performable.attribute.options)
            }
        }
    }

    func resolution() -> CodeBlockItemListSyntax {
        CodeBlockItemListSyntax(separator: "\n\n") {
            performables.all.map { "\($0.function.throwable ? "try " : "")await \(value($0.name, $0.attribute.options))" }.joined(separator: "\n")

            if registrables.nontransient.isEmpty {
                "return .init()"
            } else {
                """
                return \(throwableRegistrables ? "try " : "")await .init(
                    \(registrables.nontransient.map { "\($0.name.unescaped): \(value($0.name, $0.attribute.options))" }.joined(separator: ",\n    "))
                )
                """
            }
        }
    }

    // One registration per factory, reached through `_registrar` from the getters, the performables and `resolve()`.
    func registrations() -> MemberBlockItemListSyntax {
        guard !registrables.all.isEmpty || !performables.all.isEmpty else { return "" }

        let registrations = MemberBlockItemListSyntax(separator: "\n\n") {
            for registrable in registrables.all {
                registration(
                    name: registrable.name,
                    throwable: registrable.function.throwable,
                    options: registrable.attribute.options,
                    call: call(registrable.function.name, registrable.function.parameter, registrable.function.concurrent, registrable.function.throwable)
                )
            }

            for performable in performables.all {
                registration(
                    name: performable.name,
                    throwable: performable.function.throwable,
                    options: performable.attribute.options,
                    call: call(performable.function.name, performable.function.parameter, performable.function.concurrent, performable.function.throwable)
                )
            }
        }

        return """
        private final class \(registrar.registrations): Sendable {
            \(registrations)
        }
        """
    }

    func registration(name: TokenSyntax, throwable: Bool, options: ExprSyntax?, call: String) -> String {
        let options = options.map { "(options: \($0.trimmed))" } ?? ""

        return """
        let \(name) = Resolve.Registration\(throwable ? "Throwable" : "")\(options) { (resolver: Resolver) in
            \(call)
        }
        """
    }

    func call(_ function: TokenSyntax, _ parameter: ResolverParameter?, _ concurrent: Bool, _ throwable: Bool) -> String {
        let argument = parameter.map { parameter in parameter.label.map { "\($0): resolver" } ?? "resolver" } ?? ""

        return "\(throwable ? "try " : "")\(concurrent ? "await " : "")resolver._\(declaration.name).\(function)(\(argument))"
    }

    func start(_ name: TokenSyntax, _ options: ExprSyntax?) -> String {
        "\(reference(name, options)).start(self)"
    }

    func value(_ name: TokenSyntax, _ options: ExprSyntax?) -> String {
        "\(reference(name, options)).value(self)"
    }

    func reference(_ name: TokenSyntax, _ options: ExprSyntax?) -> String {
        switch options?.trimmedDescription {
        case nil, ".default", "Registrar.Options.default", "Resolve.Registrar.Options.default":
            "_\(registrar.name).local.\(name)"

        case ".once", "Registrar.Options.once", "Resolve.Registrar.Options.once", ".singleton", "Registrar.Options.singleton", "Resolve.Registrar.Options.singleton":
            "_\(registrar.name).global.\(name)"

        default:
            // As a member, `local` or `global` would be the storage's own instance rather than the registration.
            switch name.unescaped {
            case "local", "global": "_\(registrar.name)[dynamicMember: \\.\(name)]"
            default: "_\(registrar.name).\(name)"
            }
        }
    }
}

// MARK: - private
private extension ResolverBuilder {
    var throwable: Bool {
        throwableRegistrables || performables.all.contains(where: \.function.throwable)
    }

    var throwableRegistrables: Bool {
        registrables.nontransient.contains(where: \.function.throwable)
    }

    // Only an empty `Resolved` is safe to discard.
    var discardable: String {
        registrables.nontransient.isEmpty ? "@discardableResult\n" : ""
    }
}
