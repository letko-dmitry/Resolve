//
//  Macros.swift
//
//
//  Created by Dzmitry Letko on 01/10/2023.
//

import Foundation

@attached(member, names: named(Resolved), named(Resolver))
public macro Resolvable() = #externalMacro(module: "Macros", type: "Resolvable")

@attached(peer)
public macro Register(name: String? = nil, transient: Bool = false) = #externalMacro(module: "Macros", type: "Register")
