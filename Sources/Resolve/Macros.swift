//
//  Macros.swift
//
//
//  Created by Dzmitry Letko on 01/10/2023.
//

import Foundation

@attached(member, names: named(Resolved), named(Resolver))
public macro Resolvable(sort: Bool = true) = #externalMacro(module: "Macros", type: "Resolvable")

@attached(peer)
public macro Register(name: String? = nil, options: Registrar.Options = .default) = #externalMacro(module: "Macros", type: "Register")

@attached(peer)
public macro RegisterTransient(name: String? = nil, options: Registrar.Options = .default) = #externalMacro(module: "Macros", type: "Register")
