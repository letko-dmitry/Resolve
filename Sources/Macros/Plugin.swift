//
//  Plugin.swift
//
//
//  Created by Dzmitry Letko on 01/10/2023.
//

import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct Plugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        Resolvable.self,
        Register.self
    ]
}
